import Foundation

enum EntryKind: String, Codable, CaseIterable, Identifiable {
    case word = "單字", phrase = "片語"
    var id: String { rawValue }
}
struct Entry: Identifiable, Codable, Equatable {
    var id = UUID()
    var english: String
    var meaning: String
    var partOfSpeech: String
    var kind: EntryKind = .word
    var starred = false
    var wrongCount = 0
}
struct Unit: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var entries: [Entry] = []
}
struct Library: Codable, Equatable {
    var units: [Unit] = []
}
enum TextTools {
    // Change presentation only; preserve the complete original definition in storage.
    static func meaning(_ text: String, omitNotes: Bool) -> String {
        guard omitNotes else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        var output = "", depth = 0
        for character in text {
            if character == "（" || character == "(" { depth += 1 }
            else if character == "）" || character == ")" { depth = max(0, depth - 1) }
            else if depth == 0 { output.append(character) }
        }
        let clean = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? text : clean
    }
    static func normalized(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
    }
    static func deduplicated(_ entries: [Entry], existing: [Entry] = []) -> [Entry] {
        var keys = Set(existing.map { "\($0.kind.rawValue):\(normalized($0.english))" })
        return entries.filter { keys.insert("\($0.kind.rawValue):\(normalized($0.english))").inserted }
    }
}
