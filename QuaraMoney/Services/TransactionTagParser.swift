import Foundation

/// Parses inline `#hashtag` tags out of transaction note text.
///
/// Tags live directly in the note — there is no separate tag field. A tag is
/// `#` followed by letters, combining marks, digits, or underscores. Combining
/// marks (`\p{M}`) are required for Khmer, whose vowel signs and diacritics
/// are marks rather than standalone letters.
enum TransactionTagParser {

    private static let tagPattern = /#([\p{L}\p{M}\p{N}_]+)/

    /// All complete tags in `text`, in order of first appearance, without the
    /// leading `#`, deduplicated case-insensitively (first spelling wins).
    static func tags(in text: String?) -> [String] {
        guard let text, text.contains("#") else { return [] }
        var seen = Set<String>()
        var result: [String] = []
        for match in text.matches(of: tagPattern) {
            let tag = String(match.1)
            if seen.insert(tag.lowercased()).inserted {
                result.append(tag)
            }
        }
        return result
    }

    /// The partial tag being typed at the very end of `text`, without the `#`.
    /// Returns an empty string right after the user types `#`, and `nil` when
    /// the text does not end in a hashtag token.
    ///
    /// A plain SwiftUI `TextField` exposes no cursor position, so autocomplete
    /// only engages for a token at the end of the note — the common typing
    /// position.
    static func activeTagToken(in text: String) -> String? {
        guard let match = text.firstMatch(of: /#([\p{L}\p{M}\p{N}_]*)$/) else { return nil }
        return String(match.1)
    }
}
