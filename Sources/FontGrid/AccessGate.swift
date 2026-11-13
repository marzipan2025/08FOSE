import SwiftUI
import AppKit
import IOKit
import CryptoKit

// Email sign-up, one account per email.
//
// The app has no server of its own. Two Google pieces stand in for one:
//   - A Google Form takes (Email, Device ID, Code). The script on its
//     response sheet (Packaging/AccessSheet/Code.gs) keeps a Members tab,
//     one row per email, and mails the code.
//   - One tab of that sheet, published as CSV, lists every account as
//     (email hash, status, device IDs), so the app can check its own
//     account without any email being public. It also carries
//     "QUOTA_FULL,yyyy-MM-dd" (Seoul date) once the day's mail is used up.
//
// Statuses: Pending, Active, Rejoined (= Active), Inactive (blocked by the
// owner), Withdrawn (left from Settings). An account holds up to five Macs;
// a Mac belongs to one account at a time.
//
// This is a soft gate for ordinary users, not DRM: the code is generated
// here, and an offline Mac is never stopped.
enum AccessConfig {
    static let formURL = URL(string: "https://docs.google.com/forms/d/e/1FAIpQLSdnhMuwSaEhEdR1j_KovSQSUymzKhtOVK-iLd7_l7Z4GAkpvQ/formResponse")!
    static let emailEntry = "entry.1208547884"
    static let deviceEntry = "entry.426223974"
    static let codeEntry = "entry.1027996907"
    static let directoryURL = URL(string: "https://docs.google.com/spreadsheets/d/e/2PACX-1vT8p8rYH0bIDdlN39XZGrR1T4XIlPzYNE0LBaWxrjPJ4RgVN9tqHhatcyGFcYamqifFQQgqf7a_QagR/pub?gid=1101103727&single=true&output=csv")!

    // Six characters from 30: digits and capitals without the look-alikes
    // O/0, I/1 and S/5.
    static let codeAlphabet = Array("2346789ABCDEFGHJKLMNPQRTUVWXYZ")
    static let codeLength = 6
    static let maxDevices = 5

    // The published list lags a few minutes behind the sheet. Right after
    // verifying, a missing row means "not published yet", not "removed".
    static let publishGrace: TimeInterval = 60 * 60
}

@MainActor
final class AccessController: ObservableObject {
    enum Phase: Equatable {
        case email
        case code(email: String)
        case verified
        case blocked
    }

    @Published private(set) var phase: Phase
    @Published private(set) var busy = false
    // One line in the band: an error, or the "sent" confirmation.
    @Published var message: Message? = nil

    struct Message: Equatable {
        let text: String
        let isError: Bool
    }

    var isLocked: Bool { phase != .verified }

    /// The address this Mac was verified with, for the Account row in Settings.
    var verifiedEmail: String? { defaults.string(forKey: Key.verifiedEmail) }

    private let defaults = UserDefaults.standard
    private enum Key {
        static let verifiedEmail = "access.verifiedEmail"
        static let verifiedAt = "access.verifiedAt"
        static let noticePending = "access.verifiedNoticePending"
        static let pendingEmail = "access.pendingEmail"
        static let pendingCode = "access.pendingCode"
        static let blocked = "access.blocked"
        static let lastCheckDay = "access.lastCheckDay"
        static let all = [verifiedEmail, verifiedAt, noticePending, pendingEmail,
                          pendingCode, blocked, lastCheckDay]
    }

    let deviceID = AccessController.makeDeviceID()
    private var observers: [NSObjectProtocol] = []

    init() {
        let d = UserDefaults.standard
        if d.bool(forKey: Key.blocked) {
            phase = .blocked
        } else if d.string(forKey: Key.verifiedEmail) != nil {
            phase = .verified
        } else if let email = d.string(forKey: Key.pendingEmail),
                  d.string(forKey: Key.pendingCode) != nil {
            // Quit while waiting for the mail: pick up at the code screen.
            phase = .code(email: email)
        } else {
            phase = .email
        }
    }

    // MARK: - Lifecycle

    /// Called once from RootView. Checks now if today hasn't been checked,
    /// then again whenever the day changes: at midnight, after sleep, or when
    /// the app comes back to the front on a new day.
    func start() {
        guard observers.isEmpty else { return }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.checkIfNewDay() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.checkIfNewDay() }
        })
        observers.append(nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.checkIfNewDay() }
        })
        // A blocked Mac asks on every launch, so lifting the block in the
        // sheet frees it the next time it opens.
        if phase == .blocked { Task { await checkAccount() } } else { checkIfNewDay() }
    }

    private func checkIfNewDay() {
        guard phase == .verified || phase == .blocked else { return }
        guard defaults.string(forKey: Key.lastCheckDay) != Self.localDay() else { return }
        Task { await checkAccount() }
    }

    /// Silent: no spinner, no message unless something changes. Offline or
    /// any failure leaves things as they are and the next trigger tries again.
    private func checkAccount() async {
        guard let email = verifiedEmail else { return }
        // The sheet never heard about this Mac's verification: tell it first.
        if defaults.bool(forKey: Key.noticePending) {
            guard await Self.submit(email: email, device: deviceID, code: Self.verifiedMarker) else { return }
            defaults.set(false, forKey: Key.noticePending)
            defaults.set(Date(), forKey: Key.verifiedAt)   // restart the grace
        }
        guard let dir = await Self.fetchDirectory() else { return }
        defaults.set(Self.localDay(), forKey: Key.lastCheckDay)

        let account = dir.accounts[Self.hashEmail(email)]
        if account?.status == "Inactive" {
            defaults.set(true, forKey: Key.blocked)
            phase = .blocked
            return
        }
        let verifiedAt = defaults.object(forKey: Key.verifiedAt) as? Date ?? .distantPast
        let settled = Date().timeIntervalSince(verifiedAt) > AccessConfig.publishGrace
        let gone = account == nil || account?.status == "Withdrawn"
            || !(account?.devices.contains(deviceID) ?? false)
        if gone && settled {
            // Withdrawn elsewhere, removed from the sheet, or this Mac taken
            // off the account: sign in again.
            signOut()
            message = Message(text: "Please verify your email again.", isError: false)
            return
        }
        if phase == .blocked {
            defaults.set(false, forKey: Key.blocked)
            phase = .verified
        }
    }

    private func signOut() {
        for key in Key.all { defaults.removeObject(forKey: key) }
        phase = .email
    }

    // MARK: - Sign-up

    static func isValidEmail(_ s: String) -> Bool {
        s.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }

    func sendCode(to rawEmail: String) {
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidEmail(email) else {
            message = Message(text: "Enter a valid email address.", isError: true)
            return
        }
        guard !busy else { return }
        busy = true
        message = nil
        let resending = phase == .code(email: email)
        Task {
            defer { busy = false }
            if let dir = await Self.fetchDirectory() {
                if dir.quotaFullToday {
                    message = Message(text: "Too many sign-ups today. Please try again tomorrow.", isError: true)
                    return
                }
                if let account = dir.accounts[Self.hashEmail(email)] {
                    if account.status == "Inactive" {
                        message = Message(text: "This account has been blocked.", isError: true)
                        return
                    }
                    if account.status != "Withdrawn",
                       !account.devices.contains(deviceID),
                       account.devices.count >= AccessConfig.maxDevices {
                        message = Message(text: "This account is already used on \(AccessConfig.maxDevices) Macs.", isError: true)
                        return
                    }
                }
            }
            let code = Self.makeCode()
            guard await Self.submit(email: email, device: deviceID, code: code) else {
                message = Message(text: "Couldn't send the code. Check your connection and try again.", isError: true)
                return
            }
            defaults.set(email, forKey: Key.pendingEmail)
            defaults.set(code, forKey: Key.pendingCode)
            phase = .code(email: email)
            message = resending ? Message(text: "We sent a new code.", isError: false) : nil
        }
    }

    func verify(_ input: String) {
        guard case .code(let email) = phase,
              let expected = defaults.string(forKey: Key.pendingCode) else { return }
        guard Self.normalizeCode(input) == expected else {
            message = Message(text: "That code doesn't match.", isError: true)
            return
        }
        defaults.set(email, forKey: Key.verifiedEmail)
        defaults.set(Date(), forKey: Key.verifiedAt)
        defaults.set(true, forKey: Key.noticePending)
        defaults.set(false, forKey: Key.blocked)
        // Checked just now, in effect: the next look is tomorrow.
        defaults.set(Self.localDay(), forKey: Key.lastCheckDay)
        defaults.removeObject(forKey: Key.pendingEmail)
        defaults.removeObject(forKey: Key.pendingCode)
        message = nil
        phase = .verified
        let device = deviceID
        Task {
            if await Self.submit(email: email, device: device, code: Self.verifiedMarker) {
                defaults.set(false, forKey: Key.noticePending)
            }
        }
    }

    func changeEmail() {
        defaults.removeObject(forKey: Key.pendingEmail)
        defaults.removeObject(forKey: Key.pendingCode)
        message = nil
        phase = .email
    }

    /// From the blocked screen: leave the blocked account and sign up with
    /// a different address.
    func useAnotherEmail() {
        signOut()
        message = nil
    }

    /// Delete Account. The sheet masks the row and marks it Withdrawn; this
    /// Mac forgets its sign-up and returns to the email screen. Returns false
    /// (and changes nothing) when offline.
    func withdraw() async -> Bool {
        guard let email = verifiedEmail else { return false }
        guard await Self.submit(email: email, device: deviceID, code: Self.withdrawMarker) else { return false }
        signOut()
        message = nil
        return true
    }

    static let verifiedMarker = "VERIFIED"
    static let withdrawMarker = "WITHDRAW"

    /// Reset everything wipes the app's whole defaults domain. Sign-up state
    /// isn't app data, so Settings carries it across the reset with these.
    static func savedState() -> [String: Any] {
        var kept: [String: Any] = [:]
        for key in Key.all { if let v = UserDefaults.standard.object(forKey: key) { kept[key] = v } }
        return kept
    }

    static func restore(_ kept: [String: Any]) {
        for (key, value) in kept { UserDefaults.standard.set(value, forKey: key) }
    }

    /// Keeps only code characters, upper-cased, at most six.
    static func normalizeCode(_ s: String) -> String {
        let allowed = Set(AccessConfig.codeAlphabet)
        return String(s.uppercased().filter { allowed.contains($0) }.prefix(AccessConfig.codeLength))
    }

    // MARK: - Network

    private struct Account {
        let status: String
        let devices: Set<String>
    }

    private struct Directory {
        let accounts: [String: Account]
        let quotaFullToday: Bool
    }

    private static func fetchDirectory() async -> Directory? {
        // Google serves the published CSV with a 5-minute cache per URL, so
        // a throwaway parameter makes every request a fresh one.
        var components = URLComponents(url: AccessConfig.directoryURL, resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) +
            [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))]
        let request = URLRequest(url: components.url ?? AccessConfig.directoryURL,
                                 cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 10)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8) else { return nil }
        var accounts: [String: Account] = [:]
        var quotaFull = false
        let today = seoulDay()
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) }
            guard fields.count >= 2, !fields[0].isEmpty else { continue }
            if fields[0] == "QUOTA_FULL" {
                if fields[1] == today { quotaFull = true }
                continue
            }
            let devices = fields.count > 2
                ? Set(fields[2].split(separator: " ").map(String.init)) : []
            accounts[fields[0]] = Account(status: fields[1], devices: devices)
        }
        return Directory(accounts: accounts, quotaFullToday: quotaFull)
    }

    private static func submit(email: String, device: String, code: String) async -> Bool {
        var request = URLRequest(url: AccessConfig.formURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let fields = [(AccessConfig.emailEntry, email),
                      (AccessConfig.deviceEntry, device),
                      (AccessConfig.codeEntry, code)]
        request.httpBody = fields
            .map { "\($0.0)=\(formEncode($0.1))" }
            .joined(separator: "&")
            .data(using: .utf8)
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    private static func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    // MARK: - Helpers

    private static func makeCode() -> String {
        var rng = SystemRandomNumberGenerator()
        return String((0..<AccessConfig.codeLength).map { _ in
            AccessConfig.codeAlphabet.randomElement(using: &rng)!
        })
    }

    /// Must match hashEmail in Code.gs.
    static func hashEmail(_ email: String) -> String {
        let key = "08FOSE:" + email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return SHA256.hash(data: Data(key.utf8)).prefix(8)
            .map { String(format: "%02X", $0) }.joined()
    }

    /// The Mac's hardware UUID, hashed so the sheet never holds the raw value.
    /// Survives reinstalls and wiping the app's settings.
    private static func makeDeviceID() -> String {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("IOPlatformExpertDevice"))
        defer { if service != 0 { IOObjectRelease(service) } }
        var raw = "unknown"
        if service != 0,
           let value = IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString,
                                                       kCFAllocatorDefault, 0)?
               .takeRetainedValue() as? String {
            raw = value
        }
        let digest = SHA256.hash(data: Data(("08FOSE:" + raw).utf8))
        return digest.prefix(8).map { String(format: "%02X", $0) }.joined()
    }

    private static func localDay() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    // The script stamps QUOTA_FULL with the Seoul date.
    private static func seoulDay() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

// MARK: - Onboarding popup

/// A 640×480 card over the dimmed window until this Mac is verified, or for
/// good once its account is blocked. The top 380pt are left empty for
/// onboarding art; every control lives in the 100pt band at the bottom.
/// Clicks behind it are swallowed; RootView swallows shortcuts.
struct AccessGateView: View {
    @ObservedObject var access: AccessController
    @Environment(\.accentColors) private var accent
    @Environment(\.colorScheme) private var colorScheme

    static let size = CGSize(width: 640, height: 480)
    static let bandHeight: CGFloat = 100
    static let neutralFill = Color.primary.opacity(0.06)

    @State private var email = ""
    @State private var code = ""
    @FocusState private var focused: Bool
    @State private var primaryHovering = false
    @State private var secondaryHovering = false
    @State private var resendHovering = false
    @State private var changeHovering = false

    var body: some View {
        ZStack {
            Color.black.opacity(colorScheme == .light ? 0.25 : 0.45)
                .contentShape(Rectangle())
                .onTapGesture { }
            card
        }
        .ignoresSafeArea()
        .onAppear { focusSoon() }
        .onChange(of: access.phase) { _ in
            code = ""
            focusSoon()
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            // Reserved for onboarding art.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            band
                .frame(height: Self.bandHeight)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        // Hairline 99pt above the bottom edge, just over the control band,
        // across the full width, in the grey buttons' fill.
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Self.neutralFill)
                .frame(height: 1)
                .padding(.bottom, 99)
        }
        .background(Theme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.panelBackground)
                .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(colorScheme == .light ? Color(white: 0.56) : Color.white.opacity(0.8),
                        lineWidth: 1)
        )
    }

    // Prompt, then field + action, then message (+ links). 16 + 8 + 30 + 8 + 14
    // inside 12pt top and bottom padding.
    private var band: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch access.phase {
            case .email:            emailStep
            case .code(let email):  codeStep(email)
            case .blocked:          blockedStep
            case .verified:         EmptyView()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Steps

    @ViewBuilder private var emailStep: some View {
        prompt("Enter your email to use 08FOSE.")
        HStack(spacing: 8) {
            field("Email", text: $email, monospaced: false)
                .onSubmit { access.sendCode(to: email) }
            primaryButton(access.busy ? "Sending…" : "Send Code") {
                access.sendCode(to: email)
            }
            .disabled(access.busy)
        }
        messageLine
    }

    @ViewBuilder private func codeStep(_ address: String) -> some View {
        prompt("We sent a code to \(address).")
        HStack(spacing: 8) {
            field("6 characters", text: $code, monospaced: true)
                .frame(width: 200)
                .onChange(of: code) { new in
                    let clean = AccessController.normalizeCode(new)
                    if clean != new { code = clean }
                    if access.message?.isError == true { access.message = nil }
                }
                .onSubmit { access.verify(code) }
            primaryButton("Verify") { access.verify(code) }
                .disabled(code.count < AccessConfig.codeLength)
            Spacer(minLength: 8)
            neutralButton(access.busy ? "Sending…" : "Resend Code", hovering: $resendHovering) {
                access.sendCode(to: address)
            }
            .disabled(access.busy)
            neutralButton("Change Email", hovering: $changeHovering) {
                email = address
                access.changeEmail()
            }
        }
        messageLine
    }

    @ViewBuilder private var blockedStep: some View {
        Text("This account has been blocked.")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(height: 16)
        HStack(spacing: 8) {
            primaryButton("Use Another Email") { access.useAnotherEmail() }
            secondaryButton("Quit") { NSApp.terminate(nil) }
            Spacer(minLength: 0)
        }
        Color.clear.frame(height: 14)
    }

    // MARK: Parts

    private func prompt(_ s: String) -> some View {
        Text(s)
            .font(.system(size: Theme.bodySize))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(height: 16)
    }

    private func field(_ placeholder: String, text: Binding<String>, monospaced: Bool) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(monospaced ? .system(size: 15, design: .monospaced) : .system(size: 13))
            .tracking(monospaced ? 3 : 0)
            .autocorrectionDisabled()
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: Theme.pillRadius).fill(Theme.surfaceFill))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.pillRadius)
                    .stroke(focused ? accent.fill.opacity(0.5) : Theme.border, lineWidth: 1)
            )
            .focused($focused)
    }

    private var messageText: some View {
        Text(access.message?.text ?? " ")
            .font(.system(size: Theme.smallSize))
            .foregroundStyle(access.message?.isError == true ? Color.red : Color.secondary)
            .lineLimit(1)
    }

    // Fixed slot so the band doesn't jump when a message appears.
    private var messageLine: some View {
        messageText.frame(height: 14)
    }

    private func focusSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = true }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: Theme.bodySize, weight: .medium))
                .foregroundStyle(accent.text)
                .padding(.horizontal, 16)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: Theme.pillRadius)
                        .fill(accent.fill.opacity(primaryHovering ? 0.24 : 0.15))
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { primaryHovering = $0 }
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: Theme.bodySize, weight: .medium))
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 16)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: Theme.pillRadius)
                        .fill(secondaryHovering ? Theme.surfaceFillHover : Theme.surfaceFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.pillRadius)
                        .stroke(Theme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { secondaryHovering = $0 }
    }

    // Verify's shape and size, in grey instead of the accent.
    private func neutralButton(_ title: String, hovering: Binding<Bool>,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: Theme.bodySize, weight: .medium))
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 16)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: Theme.pillRadius)
                        .fill(hovering.wrappedValue ? Color.primary.opacity(0.12) : Self.neutralFill)
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering.wrappedValue = $0 }
    }
}
