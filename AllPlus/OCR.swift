import UIKit
import Vision
import ImageIO

enum OCR {
    static func recognize(_ page: PreparedPage, layout: PageLayout) async throws -> String {
        return try await Task.detached(priority: .userInitiated) {
            var columns: [String] = []
            let fractions: [CGFloat] = layout == .columns ? [0, 0.5] : [0]
            for x in fractions {
                func recognizeImage(_ image: CGImage) throws -> [VNRecognizedTextObservation] {
                    let rect = CGRect(x: CGFloat(image.width) * x, y: 0,
                                      width: CGFloat(image.width) / CGFloat(fractions.count), height: CGFloat(image.height))
                    guard let crop = image.cropping(to: rect) else { return [] }
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.recognitionLanguages = ["zh-Hant", "en-US"]
                    request.usesLanguageCorrection = true
                    request.customWords = ["Vocabulary", "Language Spotlight", "adj.", "adv.", "interj.", "sth", "sb"]
                    try VNImageRequestHandler(cgImage: crop).perform([request])
                    return request.results ?? []
                }
                // Read the de-shadowed page first. Compare against the original only when
                // their line boxes align closely, so an extra English example isn't merged.
                let cleaned = try recognizeImage(page.cleaned)
                let original = try recognizeImage(page.original)
                var results = cleaned
                for observation in original {
                    if let index = results.firstIndex(where: { overlap($0.boundingBox, observation.boundingBox) > 0.5 }) {
                        let cleanConfidence = results[index].topCandidates(1).first?.confidence ?? 0
                        let originalConfidence = observation.topCandidates(1).first?.confidence ?? 0
                        if originalConfidence > cleanConfidence + 0.08 { results[index] = observation }
                    } else if (observation.topCandidates(1).first?.confidence ?? 0) > 0.55 {
                        results.append(observation)
                    }
                }
                let sorted = results.sorted { a, b in
                    if abs(a.boundingBox.midY - b.boundingBox.midY) < min(a.boundingBox.height, b.boundingBox.height) * 0.45 {
                        return a.boundingBox.minX < b.boundingBox.minX
                    }
                    return a.boundingBox.midY > b.boundingBox.midY
                }
                // Vision sometimes splits one glossary line into English and Chinese boxes.
                var lines: [(CGRect, String)] = []
                for result in sorted {
                    guard let text = result.topCandidates(1).first?.string else { continue }
                    if let last = lines.last, abs(last.0.midY - result.boundingBox.midY) < min(last.0.height, result.boundingBox.height) * 0.45 {
                        lines[lines.count - 1] = (last.0.union(result.boundingBox), last.1 + " " + text)
                    } else { lines.append((result.boundingBox, text)) }
                }
                columns.append(lines.map { $0.1 }.joined(separator: "\n"))
            }
            return columns.joined(separator: "\n\n")
        }.value
    }
    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let area = intersection.width * intersection.height
        return area / max(0.000001, a.width * a.height + b.width * b.height - area)
    }
}

enum MagazineParser {
    static func parse(_ text: String) -> [Entry] {
        var entries: [Entry] = []
        var pending: Entry?
        var active = true
        func flush() {
            if let item = pending, !item.english.isEmpty, item.meaning.range(of: "[\u{4e00}-\u{9fff}]", options: .regularExpression) != nil {
                entries.append(item)
            }
            pending = nil
        }
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.localizedCaseInsensitiveContains("Vocabulary") || line.contains("參考字彙") || line.localizedCaseInsensitiveContains("Language Spotlight") {
                flush(); active = true; continue
            }
            if ["Sentence Patterns", "動手寫寫看", "補充說明", "Reading Comprehension", "Discussion Starter", "Integrated Questions", "Mixed-Format", "聽力測驗"].contains(where: { line.localizedCaseInsensitiveContains($0) }) {
                flush(); active = false; continue
            }
            guard active else { continue }
            let numbered = line.range(of: #"^[*＊◆♦◇•\s↓⊕]*\d+\s*[.、．]\s*"#, options: .regularExpression)
            let bullet = line.range(of: #"^[*＊◆♦◇•\s]+"#, options: .regularExpression)
            let marked = numbered != nil || bullet != nil || line.hasPrefix("補")
            var cleaned = line
            if let prefix = numbered ?? bullet { cleaned.removeSubrange(prefix) }
            if cleaned.hasPrefix("補") { cleaned.removeFirst(); cleaned = cleaned.trimmingCharacters(in: .whitespaces) }
            // Only glossary lines have an English headword followed by Chinese on the same line.
            let posPattern = #"\b(?:adj|adv|vt|vi|v|n|prep|conj|pron|interj|phr)\s*\."#
            let containsPOS = cleaned.range(of: posPattern, options: [.regularExpression, .caseInsensitive]) != nil
            if let chinese = cleaned.range(of: "[\u{4e00}-\u{9fff}]", options: .regularExpression), marked || containsPOS {
                var head = String(cleaned[..<chinese.lowerBound])
                var meaning = String(cleaned[chinese.lowerBound...])
                let beforeChinese = head.trimmingCharacters(in: .whitespaces)
                if beforeChinese.hasSuffix("（") || beforeChinese.hasSuffix("(") {
                    meaning = String(beforeChinese.suffix(1)) + meaning
                    head = String(beforeChinese.dropLast())
                }
                let posRegex = try! NSRegularExpression(pattern: posPattern, options: .caseInsensitive)
                let matches = posRegex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))
                var parts: [String] = []
                for match in matches {
                    if let range = Range(match.range, in: cleaned) {
                        let part = String(cleaned[range]).lowercased()
                        if !parts.contains(part) { parts.append(part) }
                    }
                }
                head = head.replacingOccurrences(of: #"[\[［].*?[\]］]"#, with: "", options: .regularExpression)
                head = head.replacingOccurrences(of: posPattern, with: "", options: [.regularExpression, .caseInsensitive])
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "（(")))
                guard head.range(of: #"^[A-Za-z][A-Za-z\s/'’.,+\-]*$"#, options: .regularExpression) != nil else { flush(); continue }
                flush()
                meaning = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
                let kind: EntryKind = head.contains(" ") || head.contains("/") ? .phrase : .word
                pending = Entry(english: head, meaning: meaning, partOfSpeech: parts.isEmpty && kind == .phrase ? "phr." : parts.joined(separator: " / "), kind: kind)
            } else if var item = pending {
                // A Chinese-only wrapped line can continue a definition; stop at examples or prose.
                let startsChinese = line.range(of: "^[（(；;、\u{4e00}-\u{9fff}]", options: .regularExpression) != nil
                let explanation = ["此片語", "此為", "表示", "動詞", "字源", "同義", "請", "第"].contains(where: { line.hasPrefix($0) })
                if startsChinese && !explanation && line.count < 65 {
                    item.meaning += line; pending = item
                } else { flush() }
            }
        }
        flush()
        return TextTools.deduplicated(entries)
    }
}
