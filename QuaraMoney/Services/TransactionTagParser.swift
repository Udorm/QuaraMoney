import Foundation

/// Parses inline `#hashtag` tags out of transaction note text.
///
/// Tags live directly in the note — there is no separate tag field. A tag is
/// `#` followed by letters, combining marks, digits, or underscores. Combining
/// marks (`\p{M}`) are required for Khmer, whose vowel signs and diacritics
/// are marks rather than standalone letters.
enum TransactionTagParser {

    private static let tagPattern = /#([\p{L}\p{M}\p{N}_]+)/
    private static let completeTagPattern = /^[\p{L}\p{M}\p{N}_]+$/

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

    /// Normalizes user-entered tag text for storage. A single leading `#` is
    /// optional; whitespace and punctuation inside a tag are rejected.
    static func normalizedTag(_ text: String) -> String? {
        var candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.hasPrefix("#") {
            candidate.removeFirst()
        }
        guard !candidate.isEmpty,
              candidate.wholeMatch(of: completeTagPattern) != nil else { return nil }
        return candidate
    }

    /// Appends a tag without duplicating an existing case-insensitive match.
    /// The note remains the source of truth; callers should re-parse `tags`
    /// after assigning the returned value.
    static func adding(tag: String, to text: String?) -> String? {
        guard let tag = normalizedTag(tag) else { return text }
        let existing = Set(tags(in: text).map { $0.lowercased() })
        guard !existing.contains(tag.lowercased()) else { return text }

        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "#\(tag)"
        }
        let separator = text.last?.isWhitespace == true ? "" : " "
        return "\(text)\(separator)#\(tag)"
    }

    /// Removes every case-insensitive occurrence of a tag token while leaving
    /// all unrelated note text untouched.
    static func removing(tag: String, from text: String?) -> String? {
        guard let text, let tag = normalizedTag(tag) else { return text }
        let ranges = text.matches(of: tagPattern).compactMap { match in
            String(match.1).caseInsensitiveCompare(tag) == .orderedSame ? match.range : nil
        }
        guard !ranges.isEmpty else { return text }

        var result = text
        for range in ranges.reversed() {
            result.removeSubrange(range)
        }

        // Removing a standalone token commonly leaves doubled spaces. Collapse
        // horizontal runs only; preserve newlines and other deliberate layout.
        result = result.replacingOccurrences(of: #"[\t ]{2,}"#, with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}
