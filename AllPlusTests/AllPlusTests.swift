import XCTest
import CoreImage
@testable import AllPlus

final class AllPlusTests: XCTestCase {
    func testNumberedVocabularyAndWrappedMeaningExcludesExamples() {
        let text = """
        Vocabulary
        * 1. gallery [ˈgæləri] n. 畫廊、藝廊；美術館、展覽館
        Mr. Fisher recently bought a statue.
        * 2. architecture [arkətektʃər] n. 建築風格；建築設計；
        建築學
        The architecture reflects creativity.
        """
        let entries = MagazineParser.parse(text)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].english, "gallery")
        XCTAssertEqual(entries[0].partOfSpeech, "n.")
        XCTAssertEqual(entries[1].meaning, "建築風格；建築設計；建築學")
    }
    func testPhraseAndGrammarBoundary() {
        let text = """
        Language Spotlight
        1. bear witness to sth 見證、證明……
        此片語意為親眼目睹。
        • The photographs bear witness to the storm.
        2. pay one’s respects 致上敬意
        此片語尤指親身前往。
        Sentence Patterns
        1. be said to V. 據說
        """
        let entries = MagazineParser.parse(text)
        XCTAssertEqual(entries.map(\.english), ["bear witness to sth", "pay one’s respects"])
        XCTAssertTrue(entries.allSatisfy { $0.kind == .phrase })
    }
    func testReferenceWordsAndDeduplication() {
        let text = """
        參考字彙
        ◆ world-class [wɜrld klæs] adj. 世界一流的；頂尖的
        ◆ world-class [wɜrld klæs] adj. 世界一流的；頂尖的
        ◆ boutique [buˈtik] n. 精品店
        """
        let entries = MagazineParser.parse(text)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].kind, .word)
    }
    func testNestedParentheticalsAndFallback() {
        XCTAssertEqual(TextTools.meaning("高檔的（強調價格（及品質））；尖端的", omitNotes: true), "高檔的；尖端的")
        XCTAssertEqual(TextTools.meaning("（使）鬆開；放鬆", omitNotes: false), "（使）鬆開；放鬆")
        XCTAssertEqual(TextTools.meaning("（說明）", omitNotes: true), "（說明）")
    }
    func testNormalizationForTypedAnswers() {
        XCTAssertEqual(TextTools.normalized("  Pay  one’s respects. "), "pay one's respects")
        XCTAssertNotEqual(TextTools.normalized("gallery"), TextTools.normalized("galleries"))
    }
    func testUnmarkedOCRLineMultiplePartsAndLeadingParenthesis() {
        let entries = MagazineParser.parse("Vocabulary\nloosen [lusn] v. （使）鬆開；放鬆\n* 2. abstract [æbstrækt] adj. 抽象的 n. 摘要")
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].english, "loosen")
        XCTAssertEqual(entries[0].meaning, "（使）鬆開；放鬆")
        XCTAssertEqual(entries[1].partOfSpeech, "adj. / n.")
    }
    func testChoicesAreUniqueAndContainAnswer() {
        let entry = Entry(english: "gallery", meaning: "畫廊（美術）", partOfSpeech: "n.")
        let pool = [entry, Entry(english: "art", meaning: "畫廊", partOfSpeech: "n."),
                    Entry(english: "sensor", meaning: "感測器", partOfSpeech: "n.")]
        let choices = QuizEngine.options(for: entry, pool: pool, reverse: false, omitNotes: true)
        XCTAssertEqual(Set(choices), Set(["畫廊", "感測器"]))
        XCTAssertEqual(QuizEngine.options(for: entry, pool: [entry], reverse: true, omitNotes: true), ["gallery"])
    }
    func testRoundTripPreservesOrderAndLearningProgress() throws {
        var entry = Entry(english: "gallery", meaning: "畫廊", partOfSpeech: "n.")
        entry.starred = true; entry.wrongCount = 3
        let library = Library(units: [Unit(title: "B", entries: [entry]), Unit(title: "A")])
        let decoded = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(decoded, library)
        XCTAssertEqual(decoded.units.map(\.title), ["B", "A"])
    }
    func testShadowRemovalKeepsTextDarkAndEqualizesPaper() {
        let extent = CGRect(x: 0, y: 0, width: 600, height: 300)
        let base = CIImage(color: CIColor(red: 0.8, green: 0.8, blue: 0.8)).cropped(to: extent)
        let shadow = CIImage(color: CIColor(red: 0.35, green: 0.35, blue: 0.35))
            .cropped(to: CGRect(x: 0, y: 0, width: 300, height: 300)).composited(over: base)
        let ink = CIImage(color: CIColor(red: 0.02, green: 0.02, blue: 0.02))
            .cropped(to: CGRect(x: 80, y: 130, width: 8, height: 30)).composited(over: shadow)
        let normalized = ImagePreparation.removeShadows(ink)
        let context = CIContext()
        func luminance(_ x: Int, _ y: Int) -> UInt8 {
            var pixel = [UInt8](repeating: 0, count: 4)
            context.render(normalized, toBitmap: &pixel, rowBytes: 4,
                           bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBA8,
                           colorSpace: CGColorSpaceCreateDeviceRGB())
            return pixel[0]
        }
        XCTAssertGreaterThan(luminance(80, 80), 210)
        XCTAssertGreaterThan(luminance(500, 80), 210)
        XCTAssertLessThan(luminance(84, 145), 100)
        XCTAssertEqual(normalized.extent, extent)
    }
}
