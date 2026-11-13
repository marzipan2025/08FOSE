import SwiftUI
import AppKit
import IOKit
import CryptoKit

// Email sign-up and remote block list.
//
// The app has no server of its own. Two Google pieces stand in for one:
//   - A Google Form takes (Email, Device ID, Code). A script bound to its
//     response sheet mails the code to that address.
//   - One tab of that sheet, published as CSV, lists the device IDs marked
//     "비활성" in the Status column. The script also writes
//     "QUOTA_FULL yyyy-MM-dd" (Seoul date) there once the day's mail quota
//     is used up.
//
// This is a soft gate for ordinary users, not DRM: the code is generated
// here, and an offline Mac is never stopped. What it does do is keep a
// blocked Mac blocked (the flag is remembered locally) until the list says
// otherwise.
enum AccessConfig {
    static let formURL = URL(string: "https://docs.google.com/forms/d/e/1FAIpQLSdnhMuwSaEhEdR1j_KovSQSUymzKhtOVK-iLd7_l7Z4GAkpvQ/formResponse")!
    static let emailEntry = "entry.1208547884"
    static let deviceEntry = "entry.426223974"
    static let codeEntry = "entry.1027996907"
    static let blockListURL = URL(string: "https://docs.google.com/spreadsheets/d/e/2PACX-1vT8p8rYH0bIDdlN39XZGrR1T4XIlPzYNE0LBaWxrjPJ4RgVN9tqHhatcyGFcYamqifFQQgqf7a_QagR/pub?gid=1101103727&single=true&output=csv")!

    // Six characters from 30: digits and capitals without the look-alikes
    // O/0, I/1 and S/5.
    static let codeAlphabet = Array("2346789ABCDEFGHJKLMNPQRTUVWXYZ")
    static let codeLength = 6
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
    // One line under the field: an error, or the "sent" confirmation.
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
        static let pendingEmail = "access.pendingEmail"
        static let pendingCode = "access.pendingCode"
        static let blocked = "access.blocked"
        static let lastCheckDay = "access.lastCheckDay"
        static let all = [verifiedEmail, pendingEmail, pendingCode, blocked, lastCheckDay]
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
        if phase == .blocked { Task { await checkBlockList() } } else { checkIfNewDay() }
    }

    private func checkIfNewDay() {
        guard phase == .verified || phase == .blocked else { return }
        guard defaults.string(forKey: Key.lastCheckDay) != Self.localDay() else { return }
        Task { await checkBlockList() }
    }

    /// Silent: no spinner, no message. Offline or any failure leaves things
    /// as they are and the next trigger tries again.
    private func checkBlockList() async {
        guard let list = await Self.fetchBlockList() else { return }
        defaults.set(Self.localDay(), forKey: Key.lastCheckDay)
        if list.devices.contains(deviceID) {
            defaults.set(true, forKey: Key.blocked)
            phase = .blocked
        } else if phase == .blocked {
            defaults.set(false, forKey: Key.blocked)
            phase = defaults.string(forKey: Key.verifiedEmail) != nil ? .verified : .email
        }
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
            if let list = await Self.fetchBlockList(), list.quotaFullToday {
                message = Message(text: "Too many sign-ups today. Please try again tomorrow.", isError: true)
                return
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
        defaults.removeObject(forKey: Key.pendingEmail)
        defaults.removeObject(forKey: Key.pendingCode)
        message = nil
        phase = .verified
        // A Mac blocked before (and then wiped) is caught here, not tomorrow.
        Task { await checkBlockList() }
    }

    /// Delete Account. Sends the same form with the code "WITHDRAW"; the
    /// sheet's script masks this Mac's rows, marks them 비활성 and deletes the
    /// raw form responses. Then this Mac forgets its sign-up and returns to
    /// the email screen. Returns false (and changes nothing) when offline.
    func withdraw() async -> Bool {
        guard let email = verifiedEmail else { return false }
        guard await Self.submit(email: email, device: deviceID, code: Self.withdrawMarker) else { return false }
        for key in Key.all { defaults.removeObject(forKey: key) }
        message = nil
        phase = .email
        return true
    }

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

    func changeEmail() {
        defaults.removeObject(forKey: Key.pendingEmail)
        defaults.removeObject(forKey: Key.pendingCode)
        message = nil
        phase = .email
    }

    /// Keeps only code characters, upper-cased, at most six.
    static func normalizeCode(_ s: String) -> String {
        let allowed = Set(AccessConfig.codeAlphabet)
        return String(s.uppercased().filter { allowed.contains($0) }.prefix(AccessConfig.codeLength))
    }

    // MARK: - Network

    private struct BlockList {
        let devices: Set<String>
        let quotaFullToday: Bool
    }

    private static func fetchBlockList() async -> BlockList? {
        // Google serves the published CSV with a 5-minute cache per URL, so
        // a throwaway parameter makes every request a fresh one.
        var components = URLComponents(url: AccessConfig.blockListURL, resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) +
            [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))]
        var request = URLRequest(url: components.url ?? AccessConfig.blockListURL,
                                 cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 10)
        request.httpMethod = "GET"
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8) else { return nil }
        let cells = text
            .split(whereSeparator: \.isNewline)
            .flatMap { $0.split(separator: ",", omittingEmptySubsequences: false) }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) }
            .filter { !$0.isEmpty }
        let flag = "QUOTA_FULL " + seoulDay()
        return BlockList(devices: Set(cells), quotaFullToday: cells.contains(flag))
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

// MARK: - Gate view

/// Covers the whole window until this Mac is verified, or for good once it
/// is blocked. Clicks behind it are swallowed; RootView swallows shortcuts.
struct AccessGateView: View {
    @ObservedObject var access: AccessController
    @Environment(\.accentColors) private var accent
    @Environment(\.colorScheme) private var colorScheme

    @State private var email = ""
    @State private var code = ""
    @FocusState private var focused: Bool
    @State private var primaryHovering = false
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
        VStack(alignment: .leading, spacing: 0) {
            switch access.phase {
            case .email:            emailStep
            case .code(let email):  codeStep(email)
            case .blocked:          blockedStep
            case .verified:         EmptyView()
            }
        }
        .padding(20)
        .frame(width: 320, alignment: .leading)
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

    // MARK: Steps

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Verify Your Email")
            note("Enter your email to use 08FOSE.")
            field("Email", text: $email, monospaced: false)
                .onSubmit { access.sendCode(to: email) }
                .padding(.top, 14)
            messageLine
            HStack {
                Spacer()
                popupButton(access.busy ? "Sending…" : "Send Code",
                            tint: accent.text, hovering: $primaryHovering) {
                    access.sendCode(to: email)
                }
                .disabled(access.busy)
            }
            .padding(.top, 10)
        }
    }

    private func codeStep(_ address: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Enter Code")
            note("We sent a code to \(address).")
            field("6 characters", text: $code, monospaced: true)
                .onChange(of: code) { new in
                    let clean = AccessController.normalizeCode(new)
                    if clean != new { code = clean }
                    if access.message?.isError == true { access.message = nil }
                }
                .onSubmit { access.verify(code) }
                .padding(.top, 14)
            messageLine
            HStack(spacing: 4) {
                textButton(access.busy ? "Sending…" : "Resend Code", hovering: $resendHovering) {
                    access.sendCode(to: address)
                }
                .disabled(access.busy)
                textButton("Change Email", hovering: $changeHovering) {
                    email = address
                    access.changeEmail()
                }
                Spacer()
                popupButton("Verify", tint: accent.text, hovering: $primaryHovering) {
                    access.verify(code)
                }
                .disabled(code.count < AccessConfig.codeLength)
            }
            .padding(.top, 10)
        }
    }

    private var blockedStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("This account has been blocked.")
            HStack {
                Spacer()
                popupButton("Quit", tint: .secondary, hovering: $primaryHovering) {
                    NSApp.terminate(nil)
                }
            }
            .padding(.top, 16)
        }
    }

    // MARK: Parts

    private func title(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func note(_ s: String) -> some View {
        Text(s)
            .font(.system(size: Theme.smallSize))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    private func field(_ placeholder: String, text: Binding<String>, monospaced: Bool) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(monospaced ? .system(size: 16, design: .monospaced) : .system(size: 14))
            .tracking(monospaced ? 3 : 0)
            .autocorrectionDisabled()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: Theme.surfaceRadius).fill(Theme.surfaceFill))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.surfaceRadius)
                    .stroke(focused ? accent.fill.opacity(0.5) : Theme.border, lineWidth: 1)
            )
            .focused($focused)
    }

    // Fixed slot so the card doesn't jump when a message appears.
    private var messageLine: some View {
        Text(access.message?.text ?? " ")
            .font(.system(size: Theme.smallSize))
            .foregroundStyle(access.message?.isError == true ? Color.red : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
    }

    private func focusSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = true }
    }

    private func popupButton(_ title: String, tint: Color,
                             hovering: Binding<Bool>, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: Theme.smallSize + 1, weight: .medium))
                .foregroundStyle(tint)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: Theme.pillRadius)
                        .fill(tint.opacity(hovering.wrappedValue ? 0.24 : 0.12))
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering.wrappedValue = $0 }
    }

    private func textButton(_ title: String, hovering: Binding<Bool>,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: Theme.smallSize))
                .foregroundStyle(Color.secondary)
                .underline(hovering.wrappedValue)
                .padding(.vertical, 5)
                .padding(.trailing, 8)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering.wrappedValue = $0 }
    }
}
