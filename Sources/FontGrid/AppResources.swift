import Foundation

/// Resilient locator for the SwiftPM resource bundle (`FontGrid_FontGrid.bundle`).
///
/// The compiler-generated `Bundle.module` accessor is unsafe in our packaged
/// `.app`. It only checks two locations and then `fatalError`s:
///   1. `Bundle.main.bundleURL/FontGrid_FontGrid.bundle` — the `.app` root,
///      but build-app.sh installs the bundle under `Contents/Resources`, so
///      this never matches in the packaged app.
///   2. an absolute `…/.build/.../FontGrid_FontGrid.bundle` path baked in at
///      compile time — present only on the build machine.
/// As a result the app appeared to work only on the machine that built it
/// (hitting the baked-in `.build` path) and crashed on every other Mac.
///
/// This locator looks where the bundle actually lives in both shapes and never
/// traps — falling back to `Bundle.main` so a miss degrades gracefully instead
/// of crashing:
///   - packaged `.app`: `Bundle.main.resourceURL` → `Contents/Resources`
///   - dev (`swift run`): `Bundle.main.bundleURL` → next to the binary in `.build`
enum AppResources {
    static let bundle: Bundle = {
        let roots = [Bundle.main.resourceURL, Bundle.main.bundleURL].compactMap { $0 }
        for root in roots {
            let url = root.appendingPathComponent("FontGrid_FontGrid.bundle")
            if let bundle = Bundle(url: url) { return bundle }
        }
        return Bundle.main
    }()
}
