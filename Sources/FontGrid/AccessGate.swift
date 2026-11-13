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

    // First line of the published list (written by Code.gs). A response
    // without it — an empty sheet mid-rewrite, a Google error page served
    // with 200 — is not the list, and must never read as "account removed".
    static let directoryMarker = "08FOSE_DIRECTORY"

    // The script accepts VERIFIED for 6 hours after a code request; the app
    // stops accepting the code a little earlier so the two never disagree.
    static let codeLifetime: TimeInterval = 5 * 60 * 60
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

    /// The Terms checkbox on the popup. Required before a code is sent.
    @Published var termsAgreed: Bool = UserDefaults.standard.bool(forKey: Key.termsAgreed) {
        didSet {
            defaults.set(termsAgreed, forKey: Key.termsAgreed)
            if termsAgreed, message?.text == Self.agreeFirst { message = nil }
        }
    }
    static let agreeFirst = "Agree to the Terms of Service to continue."

    /// The address this Mac was verified with, for the Account row in Settings.
    var verifiedEmail: String? { defaults.string(forKey: Key.verifiedEmail) }

    private let defaults = UserDefaults.standard
    private enum Key {
        static let verifiedEmail = "access.verifiedEmail"
        static let verifiedAt = "access.verifiedAt"
        static let noticePending = "access.verifiedNoticePending"
        static let pendingEmail = "access.pendingEmail"
        static let pendingCode = "access.pendingCode"
        static let pendingAt = "access.pendingAt"
        static let blocked = "access.blocked"
        static let lastCheckDay = "access.lastCheckDay"
        static let termsAgreed = "access.termsAgreed"
        static let all = [verifiedEmail, verifiedAt, noticePending, pendingEmail,
                          pendingCode, pendingAt, blocked, lastCheckDay, termsAgreed]
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
    /// Run on each of the triggers below (day change, wake, activation), so
    /// other once-a-day work — the update check — can ride along. Not on
    /// start(): the launch has its own update check.
    var onCheckTrigger: (() -> Void)?

    func start() {
        guard observers.isEmpty else { return }
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.checkIfNewDay(); self?.onCheckTrigger?() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.checkIfNewDay(); self?.onCheckTrigger?() }
        })
        observers.append(nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.checkIfNewDay(); self?.onCheckTrigger?() }
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
        termsAgreed = false
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
        guard termsAgreed else {
            message = Message(text: Self.agreeFirst, isError: true)
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
            defaults.set(Date(), forKey: Key.pendingAt)
            phase = .code(email: email)
            message = resending ? Message(text: "We sent a new code.", isError: false) : nil
        }
    }

    func verify(_ input: String) {
        guard case .code(let email) = phase,
              let expected = defaults.string(forKey: Key.pendingCode) else { return }
        guard !pendingCodeExpired else {
            message = Message(text: "That code has expired. Press Resend Code for a new one.", isError: true)
            return
        }
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
        defaults.removeObject(forKey: Key.pendingAt)
        message = nil
        phase = .verified
        let device = deviceID
        Task {
            if await Self.submit(email: email, device: device, code: Self.verifiedMarker) {
                defaults.set(false, forKey: Key.noticePending)
            }
        }
    }

    /// A code older than the script's window would pass here and then be
    /// turned away by the sheet. No timestamp (never happens) counts as old.
    private var pendingCodeExpired: Bool {
        let at = defaults.object(forKey: Key.pendingAt) as? Date ?? .distantPast
        return Date().timeIntervalSince(at) > AccessConfig.codeLifetime
    }

    func changeEmail() {
        defaults.removeObject(forKey: Key.pendingEmail)
        defaults.removeObject(forKey: Key.pendingCode)
        defaults.removeObject(forKey: Key.pendingAt)
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
        var marked = false
        let today = seoulDay()
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) }
            guard fields.count >= 2, !fields[0].isEmpty else { continue }
            if fields[0] == AccessConfig.directoryMarker { marked = true; continue }
            if fields[0] == "QUOTA_FULL" {
                if fields[1] == today { quotaFull = true }
                continue
            }
            let devices = fields.count > 2
                ? Set(fields[2].split(separator: " ").map(String.init)) : []
            accounts[fields[0]] = Account(status: fields[1], devices: devices)
        }
        guard marked else { return nil }
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
    @State private var showingTerms = false
    @State private var termsLinkHovering = false
    @State private var closeHovering = false

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
            topArea
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

    // Everything above the control band. The upper part is reserved for
    // onboarding art and feature notes; the Terms panel covers it when open.
    // The agreement row sits at its foot, under the panel too.
    // The guide area (the artwork's frame, scaled to the popup's width) and,
    // right under it, the agreement row. The guide or the Terms panel sits
    // on the artwork (the guide steps aside while Terms is open).
    private var topArea: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                GuideBackdrop()
                if showingTerms {
                    termsPanel
                        .transition(.opacity)
                } else if access.phase != .blocked {
                    GuideView()
                        .transition(.opacity)
                }
            }
            .frame(width: GuideView.width, height: GuideView.height)
            Group {
                if access.phase != .blocked {
                    agreeRow
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeOut(duration: 0.15), value: showingTerms)
    }

    // Title at the top; the text starts 120pt below the popup's top edge and
    // scrolls inside the rest of the area.
    private var termsPanel: some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .top) {
                Text("Terms of Service")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button { showingTerms = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(closeHovering
                                                  ? Color.primary.opacity(0.12) : Self.neutralFill))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .onHover { closeHovering = $0 }
                .help("Close")
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)
            // Columns run edge to edge so they scroll out under the sides;
            // the first one starts at the usual 24pt inset.
            TermsColumns(text: AccessTerms.attributed(), inset: 24)
                .frame(height: AccessTerms.blockHeight)
                .padding(.top, AccessTerms.bodyTop)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Transparent: the backdrop artwork shows through behind the text.
        .contentShape(Rectangle())
    }

    // Checkbox, then "I agree to the Terms of Service" with the last part a
    // link that opens the panel above.
    private var agreeRow: some View {
        HStack(spacing: 10) {
            Button { access.termsAgreed.toggle() } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(access.termsAgreed ? accent.fill : Self.neutralFill)
                    if access.termsAgreed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel("Agree to the Terms of Service")
            .accessibilityValue(access.termsAgreed ? "On" : "Off")
            HStack(spacing: 0) {
                Text("I agree to the ")
                    .foregroundStyle(.secondary)
                    .onTapGesture { access.termsAgreed.toggle() }
                Button { showingTerms = true } label: {
                    Text("Terms of Service")
                        .foregroundStyle(accent.text)
                        .underline(true, color: termsLinkHovering ? accent.text : accent.text.opacity(0.4))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .onHover { termsLinkHovering = $0 }
            }
            .font(.system(size: Theme.bodySize))
        }
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

// MARK: - Guide

/// The artwork behind the guide: the 729×380 design frame scaled to the
/// popup's width, top-centre, never cropped.
struct GuideBackdrop: View {
    var body: some View {
        Image("OnboardingBackground")
            .resizable()
            .scaledToFit()
            .frame(width: GuideView.width, height: GuideView.height, alignment: .top)
            .opacity(0.3)   // 30% of the PNG's own strength, so the guide reads first
            .accessibilityHidden(true)
    }
}

/// The onboarding / user guide. Pages are laid out in the 729×380 design
/// frame (Figma "image", node 5721:399) and scaled to the popup's width;
/// text uses the app's own sizes. Shown in the sign-up popup's top area and
/// on its own from Settings › User guide. More pages (images, Lottie,
/// video) slot into `page(_:)`.
struct GuideView: View {
    @Environment(\.accentColors) private var accent
    @EnvironmentObject private var toasts: ToastCenter
    @State private var index = 0
    @State private var buttonHovering = false
    @State private var prevHovering = false
    @State private var nextHovering = false

    /// Settings › User guide: ←/→ page from the start. In the sign-up popup
    /// they only take over once Take a Tour is pressed, so until then the
    /// arrows stay with the email field.
    var alwaysArmed = false
    @State private var armed = false

    static let designSize = CGSize(width: 729, height: 380)
    static let width: CGFloat = 640
    static var scale: CGFloat { width / designSize.width }
    static var height: CGFloat { (designSize.height * scale).rounded() }
    static var pageCount: Int { 1 + sections.count }   // welcome, then each section
    // The design's 11px text, scaled with the frame like everything else
    // (10pt: the app's section-header size).
    static let textSize: CGFloat = Theme.sectionHeaderSize

    var body: some View {
        page(index)
            .frame(width: Self.width, height: Self.height, alignment: .topLeading)
            .clipped()
            .background(
                GuideArrowKeys(enabled: alwaysArmed || armed) { step in
                    if step > 0 { next() } else { previous() }
                }
            )
    }

    private func takeTour() {
        armed = true
        // Leave the email field so ←/→ reach the guide instead of its cursor.
        NSApp.keyWindow?.makeFirstResponder(nil)
        next()
    }

    private var hasNext: Bool { index < Self.pageCount - 1 }

    // On the last page Next is disabled; the guide then stays until the
    // popup closes (Settings) or the user signs in below (first run).
    private func next() {
        if hasNext { index += 1 }
    }

    private func previous() {
        if index > 0 { index -= 1 }
    }

    /// Design-frame units to points.
    private func d(_ v: CGFloat) -> CGFloat { v * Self.scale }

    @ViewBuilder private func page(_ i: Int) -> some View {
        switch i {
        case 0:  welcome
        default: sectionPage(Self.sections[i - 1])
        }
    }

    private var welcome: some View {
        ZStack(alignment: .topLeading) {
            Image("GuideLogo")
                .resizable()
                .interpolation(.high)
                .frame(width: d(371), height: d(371))
                .offset(x: 16, y: d(5) - 4)  // 16pt right of, 4pt above the Figma position
                .accessibilityHidden(true)

            Image("GuideTitle")
                .renderingMode(.template)
                .resizable()
                .foregroundStyle(.primary)
                .frame(width: d(142), height: d(44))
                .offset(x: d(390), y: d(51))
                .accessibilityLabel("08FOSE User Guide")

            Text("Version \(Theme.appVersion)")
                .font(.system(size: Self.textSize))
                .foregroundStyle(accent.text)
                .offset(x: d(392), y: d(124))

            Text("Fonts shown in 08FOSE are installed on your Mac and remain the property of their respective owners. Each font's own license governs how it may be used. 08FOSE includes no fonts; it previews the ones you have and can save the text you type as an image. Built with Apple system frameworks (SwiftUI, AppKit). No third-party code is bundled.")
                .font(.system(size: Self.textSize))
                .foregroundStyle(.primary)
                .lineSpacing(1.5)
                .frame(width: d(290), alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .offset(x: d(392), y: d(166))

            Button(action: takeTour) {
                Image("GuideTakeATour")
                    .renderingMode(.template)
                    .resizable()
                    .foregroundStyle(.primary)
                    // The SVG's 137×13 glyphs, centred in the Figma text
                    // node's 140×23 box.
                    .frame(width: d(137), height: d(13))
                    .frame(width: d(140), height: d(23))
                    .opacity(buttonHovering ? 0.6 : 1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .onHover { buttonHovering = $0 }
            .accessibilityLabel("Take a Tour")
            .offset(x: d(390), y: d(314))
        }
    }
}

extension GuideView {
    /// One guide section: a numbered diagram on the left, number and title,
    /// a text that names each numbered part (bold) and explains it (light).
    struct Section {
        let number: String
        let title: String
        let image: String
        let parts: [(name: String, text: String)]
        /// A closing page's plain text instead of numbered parts. An
        /// `email` inside it becomes a link that copies the address.
        var closing: (text: String, email: String)? = nil
    }

    static let contactEmail = "artbrainbyeongsu@gmail.com"

    // Text stays within 10 lines of the 290-unit column.
    static let sections: [Section] = [
        Section(number: "01", title: "The Window", image: "GuideLayout", parts: [
            ("1 Filters", "Narrow the list by weight count, script, pins, notes or muted fonts. Below them, set columns, font size, theme and wallpaper."),
            ("2 Grid", "Every installed font, set in your own sample text. Click a cell to see its weights, details and glyphs; the index at its side jumps to a letter."),
            ("3 Library", "The fonts you've pinned, the tags from your notes and the glyphs you've copied, side by side."),
            ("4 Sample bar", "Type here to change what every cell shows.")
        ]),
        Section(number: "02", title: "Sample Text", image: "GuideSection2", parts: [
            ("1 Input source", "The key shows which keyboard you are typing in. Click it to switch, say from English to Korean, without leaving the app."),
            ("2 Sample bar", "Type a word or a whole sentence here and every font in the grid sets it at once, so you can compare them as you write.")
        ]),
        Section(number: "03", title: "Font Cells", image: "GuideSection3", parts: [
            ("1 Name", "The font's family name."),
            ("2 Weights", "How many weights the family has; VF marks a variable font. Hover over a cell to see its weights right away."),
            ("3 Note", "This dot means the font has a note, and its cell gets an outline. Words written with # in a note work as tags too."),
            ("4 Pin", "Shows the font is pinned. Click it to pin or unpin; your pinned fonts are listed at the top right of the app.")
        ]),
        Section(number: "04", title: "Font Details", image: "GuideSection4", parts: [
            ("1 Header", "The font's name and weights, with buttons to pin it, copy its name, show it in Finder or mute it."),
            ("2 Samples", "Your text in each weight. Type over it to try your own, or export the sample."),
            ("3 Glyphs", "Every glyph in the font. Click one to copy it to the clipboard."),
            ("4 Info", "Technical details: format, file size, scripts, features, copyright and more."),
            ("5 Note", "Fix a sample text for this font, or write #words to tag it.")
        ]),
        Section(number: "04-1", title: "Font Header", image: "GuideSection5", parts: [
            ("1 Pin", "Adds the font to your pinned list at the top right of the app. Click again to unpin."),
            ("2 Copy name", "Copies the family name to the clipboard, ready to paste into a design app."),
            ("3 Show in Finder", "Opens the folder that holds the font file, with the file selected."),
            ("4 Mute", "Puts a font you rarely use to sleep. With Hide muted on it leaves the grid; the Muted filter lists only muted fonts.")
        ]),
        Section(number: "04-2", title: "Font Samples", image: "GuideSection6", parts: [
            ("1 Try it out", "Click a sample to type your own text in that weight. Each row keeps its own words; they aren't saved, and they clear when you open another font."),
            ("2 Export", "Opens a menu to save the row as PNG or SVG straight to Downloads, or to copy it and paste into Figma and other design apps as editable vectors. The artwork is white in dark mode and black in light mode.")
        ]),
        Section(number: "04-3", title: "Glyphs", image: "GuideSection7", parts: [
            ("1 Weight", "Choose which weight's glyphs to show."),
            ("2 Copy", "Click a glyph to copy it. It's also kept in the Glyphs list at the bottom right, ready to copy again."),
            ("3 No character", "An outlined cell is a glyph with no character of its own, so it can't be copied."),
            ("4 Add", "⌘\u{2011}click a glyph to add it to the end of every sample above. This works for outlined glyphs too, so you can export them as PNG or SVG."),
            ("5 Inspect", "Roll over a glyph and hold Space to blow it up across the card, or ⌥ Option to see it as outlines.")
        ]),
        Section(number: "04-4", title: "Note & Specimen", image: "GuideSection8", parts: [
            ("1 Note", "Write anything about the font. A font with a note gets a round dot and an outline in the grid."),
            ("2 Tags", "Words written with # become tags. They gather in the Tags list at the right, where picking one shows only the fonts that carry it."),
            ("3 Specimen", "Text set here replaces the sample for this font only, in the grid and in every weight above. Its dot in the grid turns square.")
        ]),
        Section(number: "05", title: "Go Explore!", image: "GuideSection9", parts: [],
                closing: ("That's the tour, but not the whole story! 08FOSE is full of little touches we haven't mentioned, and a few easter eggs are hiding in there too. Click around, try things and see what turns up. Got an idea, a wish or a question? Drop a line to \(contactEmail). I'd love to hear from you!", contactEmail))
    ]

    // Figma node 5721:486.
    func sectionPage(_ section: Section) -> some View {
        ZStack(alignment: .topLeading) {
            Image(section.image)
                .resizable()
                .interpolation(.high)
                .frame(width: d(362), height: d(380))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(section.number)
                    .font(.system(size: Self.sectionSize, weight: .ultraLight, design: .monospaced))
                Text(section.title)
                    .font(.system(size: Self.sectionSize, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(.primary)
            .offset(x: d(390), y: d(51))

            bodyText(section)
            .font(.system(size: Self.textSize))
            .foregroundStyle(.primary)
            .lineSpacing(1.5)
            .frame(width: d(290), alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .offset(x: d(392), y: d(123))
            .environment(\.openURL, OpenURLAction(handler: copyEmail))

            navButton("GuidePrev", label: "Previous", hovering: $prevHovering, action: previous)
                .offset(x: d(392), y: d(314))
            navButton("GuideNext", label: "Next", enabled: hasNext,
                      hovering: $nextHovering, action: next)
                .offset(x: d(624), y: d(314))
        }
    }

    static let sectionSize: CGFloat = 15

    func bodyText(_ section: Section) -> Text {
        if let closing = section.closing {
            var text = AttributedString(closing.text)
            if let range = text.range(of: closing.email) {
                text[range].link = URL(string: "mailto:\(closing.email)")
                text[range].foregroundColor = Self.partNameColor
                text[range].underlineStyle = .single
            }
            return Text(text).fontWeight(.light)
        }
        return section.parts.reduce(Text("")) { text, part in
            // No-break space keeps a number on the same line as its name.
            text + Text(part.name.replacingOccurrences(of: " ", with: "\u{00A0}") + " ")
                .fontWeight(.bold)
                .foregroundColor(Self.partNameColor)
                 + Text(part.text + " ").fontWeight(.light)
        }
    }

    /// The closing page's email link: copy the address instead of opening Mail.
    func copyEmail(_ url: URL) -> OpenURLAction.Result {
        guard url.scheme == "mailto" else { return .systemAction }
        let address = String(url.absoluteString.dropFirst("mailto:".count))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address, forType: .string)
        toasts.show(Toast(style: .success, title: "Email copied", detail: address))
        return .handled
    }
    /// #EA5009, the orange of the diagrams' numbered badges.
    static let partNameColor = Color(red: 0xEA / 255, green: 0x50 / 255, blue: 0x09 / 255)

    // The SVG's 64×13 glyphs centred in the Figma text node's 65×23 box,
    // on the same line as Take a Tour.
    func navButton(_ asset: String, label: String, enabled: Bool = true,
                   hovering: Binding<Bool>,
                   action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(asset)
                .renderingMode(.template)
                .resizable()
                .foregroundStyle(.primary)
                .frame(width: d(64), height: d(13))
                .frame(width: d(65), height: d(23))
                .opacity(enabled ? (hovering.wrappedValue ? 0.6 : 1) : 0.4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!enabled)
        .onHover { hovering.wrappedValue = enabled && $0 }
        .accessibilityLabel(label)
    }
}

/// ←/→ turn the guide's pages while it holds the keyboard. Arrows still go
/// to a focused text field (the email or code field), and ⌘/⌥/⌃/⇧ combos
/// are left alone. While this is armed, the app's other arrow handlers (the
/// detail view's font stepping, the shortcut monitor) let the keys through.
struct GuideArrowKeys: NSViewRepresentable {
    var enabled: Bool
    var onStep: (Int) -> Void

    @MainActor static var isActive: Bool { Coordinator.current?.enabled == true }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.enabled = enabled
        context.coordinator.onStep = onStep
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(enabled: enabled, onStep: onStep)
    }

    @MainActor final class Coordinator {
        static weak var current: Coordinator?
        var enabled: Bool
        var onStep: (Int) -> Void
        private var monitor: Any?

        init(enabled: Bool, onStep: @escaping (Int) -> Void) {
            self.enabled = enabled
            self.onStep = onStep
        }

        func install() {
            guard monitor == nil else { return }
            Coordinator.current = self
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.enabled,
                      event.keyCode == 123 || event.keyCode == 124 else { return event }
                if NSApp.modalWindow != nil { return event }
                if event.window?.firstResponder is NSText { return event }
                if !event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
                    return event
                }
                self.onStep(event.keyCode == 124 ? 1 : -1)
                return nil
            }
        }

        func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            if Coordinator.current === self { Coordinator.current = nil }
        }
    }
}

/// Settings › User guide: the guide on its own, without the sign-up band.
struct GuidePopup: View {
    let onClose: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var closeHovering = false

    var body: some View {
        ZStack {
            Color.black.opacity(colorScheme == .light ? 0.25 : 0.45)
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
            card
        }
        .ignoresSafeArea()
    }

    private var card: some View {
        ZStack(alignment: .topLeading) {
            GuideBackdrop()
            GuideView(alwaysArmed: true)
        }
        .frame(width: GuideView.width, height: GuideView.height)
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.primary.opacity(closeHovering ? 0.12 : 0.06)))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .onHover { closeHovering = $0 }
            .help("Close")
            .padding(.top, 18)
            .padding(.trailing, 18)
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
}

// MARK: - Terms text

/// Shown in the popup's Terms panel: one running text, each section's title
/// in bold, the rest light, set in 400pt columns of 12 lines that continue
/// to the right. DRAFT wording, to be reviewed by the owner.
enum AccessTerms {
    static let bodyTop: CGFloat = 100   // from the popup's top edge
    static let fontSize: CGFloat = 12
    static let lineHeight: CGFloat = 18
    static let linesPerColumn = 12
    static let columnWidth: CGFloat = 400
    static let columnGap: CGFloat = 30
    static var blockHeight: CGFloat { lineHeight * CGFloat(linesPerColumn) }

    static let intro = "08FOSE is a free app for browsing the fonts installed on your Mac. By checking the box, you agree to the terms below."

    static let sections: [(title: String, text: String)] = [
        ("What we collect.", "Your email address, and an ID for your Mac. The Mac ID is made from your Mac's hardware number by a one-way conversion; the hardware number itself is never sent."),
        ("Why.", "Only to verify that you can use 08FOSE and to manage access, for example to stop an account from using the app. We do not send newsletters or ads, and we do not share or sell your email."),
        ("Where it is kept.", "In a Google Sheet owned by the 08FOSE developer. Google stores it on its servers, which may be outside your country. Verification codes are sent through Google's mail service."),
        ("How long.", "Until you delete your account. One account can be used on up to 5 Macs."),
        ("Deleting your account.", "Settings › Account › Delete account. Your email and Mac IDs are masked right away. A one-way hash of your email is kept so that signing up again with the same address is recognized as rejoining."),
        ("Blocking.", "The developer may block an account that misuses the app. A blocked account can no longer use 08FOSE."),
        ("The app itself.", "08FOSE is provided as is, without warranty. Fonts shown in it belong to their owners and are governed by their own licenses."),
        ("Contact.", "For questions or deletion requests, write to")
    ]
    // Ends the text, underlined and linked to a new mail.
    static let contactEmail = "artbrainbyeongsu@gmail.com"


    static func attributed() -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.minimumLineHeight = lineHeight
        para.maximumLineHeight = lineHeight
        func run(_ s: String, _ weight: NSFont.Weight) -> NSAttributedString {
            NSAttributedString(string: s, attributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: para
            ])
        }
        let out = NSMutableAttributedString(attributedString: run(intro + " ", .light))
        for section in sections {
            out.append(run(section.title + " ", .bold))
            out.append(run(section.text + " ", .light))
        }
        let mail = NSMutableAttributedString(attributedString: run(contactEmail, .light))
        if let url = URL(string: "mailto:" + contactEmail) {
            mail.addAttributes([.link: url,
                                .underlineStyle: NSUnderlineStyle.single.rawValue],
                               range: NSRange(location: 0, length: mail.length))
        }
        out.append(mail)
        return out
    }
}

/// One text flowing through fixed-size columns, left to right, inside a
/// sideways scroll view with no scroller. A vertical wheel or swipe scrolls
/// sideways too. TextKit does the flow: one layout manager, one text
/// container per column.
struct TermsColumns: NSViewRepresentable {
    let text: NSAttributedString
    var inset: CGFloat = 24

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = SidewaysScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .allowed

        let width = AccessTerms.columnWidth
        let height = AccessTerms.blockHeight
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)

        let doc = FlippedView()
        var x = inset
        for _ in 0..<50 {
            let container = NSTextContainer(size: NSSize(width: width, height: height))
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            let view = NSTextView(frame: NSRect(x: x, y: 0, width: width, height: height),
                                  textContainer: container)
            view.isEditable = false
            view.isSelectable = true
            view.drawsBackground = false
            view.textContainerInset = .zero
            view.isVerticallyResizable = false
            view.isHorizontallyResizable = false
            // Links keep the text colour, underlined, rather than system blue.
            view.linkTextAttributes = [.foregroundColor: NSColor.labelColor,
                                       .underlineStyle: NSUnderlineStyle.single.rawValue,
                                       .cursor: NSCursor.pointingHand]
            doc.addSubview(view)
            x += width + AccessTerms.columnGap
            if NSMaxRange(layout.glyphRange(for: container)) >= layout.numberOfGlyphs { break }
        }
        doc.frame = NSRect(x: 0, y: 0, width: x - AccessTerms.columnGap + inset, height: height)
        scroll.documentView = doc
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}

    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    private final class SidewaysScrollView: NSScrollView {
        override func scrollWheel(with event: NSEvent) {
            guard event.scrollingDeltaX == 0, event.scrollingDeltaY != 0 else {
                super.scrollWheel(with: event)
                return
            }
            let clip = contentView
            let step = event.hasPreciseScrollingDeltas ? 1 : 10
            let maxX = max(0, (documentView?.frame.width ?? 0) - clip.bounds.width)
            var origin = clip.bounds.origin
            origin.x = min(max(0, origin.x - event.scrollingDeltaY * CGFloat(step)), maxX)
            clip.scroll(to: origin)
            reflectScrolledClipView(clip)
        }
    }
}
