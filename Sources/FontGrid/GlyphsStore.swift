import Foundation

/// One glyph the user copied out of a detail card, kept so it can be copied
/// again without going back to find it.
///
/// The FACE is recorded, not just the family: the glyph grid draws with
/// whichever member the card had selected, so a glyph copied while looking at
/// Light has to come back as Light. The family rides along because reopening
/// the font is a family-level action.
struct CopiedGlyph: Codable, Hashable, Identifiable {
    let character: String
    let psName: String       // the exact face the glyph was seen in
    let familyName: String   // what "open this font" reopens

    // A glyph is the same entry when it is the same character in the same face.
    // Copying it again moves it back to the front rather than adding a twin.
    var id: String { "\(psName)\u{1}\(character)" }
}

@MainActor
final class GlyphsStore: ObservableObject {
    // Newest first — the opposite of PinsStore's ordering, because this list is
    // a trail of what was just copied rather than a collection being curated.
    @Published private(set) var glyphs: [CopiedGlyph] = []
    private let key = "FontGrid.copiedGlyphs"

    init() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([CopiedGlyph].self, from: data)
        else { return }
        glyphs = saved
    }

    /// Record a copy. An entry already in the list moves to the front instead of
    /// being duplicated, so copying the same glyph twice leaves one card.
    ///
    /// Deliberately unbounded: in practice these stay well under a hundred, and
    /// a cap would silently drop the oldest, which is the opposite of what a
    /// keep-for-later list is for.
    func record(character: String, psName: String, familyName: String) {
        let entry = CopiedGlyph(character: character, psName: psName, familyName: familyName)
        glyphs.removeAll { $0.id == entry.id }
        glyphs.insert(entry, at: 0)
        save()
    }

    func remove(_ entry: CopiedGlyph) {
        glyphs.removeAll { $0.id == entry.id }
        save()
    }

    /// Wipe the list. Used by Settings → Data.
    func clearAll() {
        glyphs.removeAll()
        save()
    }

    /// Merge imported glyphs, newest-first order preserved and existing entries
    /// left where they are.
    func merge(_ incoming: [CopiedGlyph]) {
        let known = Set(glyphs.map(\.id))
        glyphs.append(contentsOf: incoming.filter { !known.contains($0.id) })
        save()
    }

    /// Snapshot for export.
    var exportList: [CopiedGlyph] { glyphs }

    private func save() {
        guard let data = try? JSONEncoder().encode(glyphs) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
