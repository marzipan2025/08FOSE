import Foundation

/// Per-family custom sample text. When a family has a non-empty sample, the
/// font detail view shows that text (in the accent color) for every weight
/// instead of the global preview text. Persisted like memos, keyed by family
/// name so it survives relaunches and travels through export/import.
@MainActor
final class SampleStore: ObservableObject {
    @Published private(set) var samples: [String: String] = [:]
    private let key = "FontGrid.samples"

    init() {
        if let saved = UserDefaults.standard.dictionary(forKey: key) as? [String: String] {
            samples = saved
        }
    }

    func sample(for name: String) -> String { samples[name] ?? "" }

    func hasSample(for name: String) -> Bool {
        !(samples[name]?.isEmpty ?? true)
    }

    func setSample(_ text: String, for name: String) {
        if text.isEmpty {
            samples.removeValue(forKey: name)
        } else {
            samples[name] = text
        }
        UserDefaults.standard.set(samples, forKey: key)
    }

    /// Remove every custom sample. Used by Settings → Data.
    func clearAll() {
        samples.removeAll()
        UserDefaults.standard.set(samples, forKey: key)
    }

    /// Merge imported samples into the current set. A font keeps its existing
    /// sample when one is already set; otherwise it takes the imported value.
    func merge(_ incoming: [String: String]) {
        for (name, incomingSample) in incoming where !incomingSample.isEmpty {
            if (samples[name] ?? "").isEmpty {
                samples[name] = incomingSample
            }
        }
        UserDefaults.standard.set(samples, forKey: key)
    }

    /// Snapshot for export.
    var exportMap: [String: String] { samples }
}
