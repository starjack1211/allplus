import SwiftUI
import AVFoundation

enum QuizMode: String, CaseIterable, Identifiable {
    case choice = "英選中", reverse = "中選英", spelling = "拼字", cards = "翻卡"
    var id: String { rawValue }
}
struct QuizSession: Identifiable {
    let id = UUID()
    var entries: [Entry]
    var mode: QuizMode
}
enum QuizEngine {
    static func options(for entry: Entry, pool: [Entry], reverse: Bool, omitNotes: Bool) -> [String] {
        func label(_ e: Entry) -> String { reverse ? e.english : TextTools.meaning(e.meaning, omitNotes: omitNotes) }
        let correct = label(entry)
        let others = Array(Set(pool.filter { $0.id != entry.id }.map(label))).filter { $0 != correct }.shuffled()
        return ([correct] + Array(others.prefix(3))).shuffled()
    }
}
struct QuizSetupView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var selected: Set<UUID> = []
    @State private var mode: QuizMode = .choice
    @State private var scope = "全部"
    @State private var filter = "全部"
    @State private var count = 20
    @State private var session: QuizSession?
    private var pool: [Entry] {
        TextTools.deduplicated(store.library.units.filter { selected.contains($0.id) }.flatMap(\.entries).filter {
            (scope == "全部" || $0.kind.rawValue == scope) && (filter == "全部" || (filter == "收藏" ? $0.starred : $0.wrongCount > 0))
        })
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("今天，想挑戰哪些單元？").font(.title2.bold()).padding(.vertical, 8)
                    Picker("測驗方式", selection: $mode) { ForEach(QuizMode.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("內容", selection: $scope) { ForEach(["全部", "單字", "片語"], id: \.self) { Text($0) } }
                    Picker("範圍", selection: $filter) { ForEach(["全部", "收藏", "錯題"], id: \.self) { Text($0) } }
                    Picker("題數", selection: $count) { ForEach([10, 20, 30, 50, 100], id: \.self) { Text("\($0) 題").tag($0) } }
                }
                Section("選擇單元（可複選）") {
                    Button(selected.count == store.library.units.count ? "全部取消" : "全部選取") {
                        selected = selected.count == store.library.units.count ? [] : Set(store.library.units.map(\.id))
                    }
                    ForEach(store.library.units) { unit in
                        Button {
                            if selected.contains(unit.id) { selected.remove(unit.id) } else { selected.insert(unit.id) }
                        } label: {
                            HStack {
                                Text(unit.title).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: selected.contains(unit.id) ? "checkmark.circle.fill" : "circle")
                            }
                        }
                    }
                }
                Section {
                    Text("符合範圍：\(pool.count) 項；本次 \(min(count, pool.count)) 題。") .font(.caption).foregroundStyle(.secondary)
                    Button("開始測驗") { session = QuizSession(entries: Array(pool.shuffled().prefix(count)), mode: mode) }
                        .font(.headline).disabled(pool.isEmpty)
                    if pool.count == 1 && (mode == .choice || mode == .reverse) {
                        Text("目前只有一項，選擇題將只有一個答案；可改用拼字或翻卡。") .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.navigationTitle("測驗練習")
                .fullScreenCover(item: $session) { QuizView(session: $0, optionPool: pool) }
        }
    }
}
struct QuizView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let session: QuizSession
    let optionPool: [Entry]
    @AppStorage("omitNotes") private var omitNotes = true
    @State private var index = 0
    @State private var options: [String] = []
    @State private var typed = ""
    @State private var answered = false
    @State private var correct = false
    @State private var score = 0
    @State private var wrong: [Entry] = []
    @State private var revealed = false
    @State private var speaker = AVSpeechSynthesizer()
    private var finished: Bool { index >= session.entries.count }
    private var entry: Entry { session.entries[min(index, session.entries.count - 1)] }
    private var answer: String { session.mode == .reverse || session.mode == .spelling ? entry.english : TextTools.meaning(entry.meaning, omitNotes: omitNotes) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if finished {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(.tint)
                        Text("練習完成").font(.largeTitle.bold())
                        Text("\(score) / \(session.entries.count)").font(.system(size: 48, weight: .bold, design: .rounded))
                        Text(wrong.isEmpty ? "全部答對了！" : "有 \(wrong.count) 題需要再複習，已加入錯題範圍。") .foregroundStyle(.secondary)
                        ForEach(wrong) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.english).font(.headline)
                                Text("\(item.partOfSpeech) \(TextTools.meaning(item.meaning, omitNotes: omitNotes))").foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Button("完成") { dismiss() }.buttonStyle(.borderedProminent)
                    } else {
                        ProgressView(value: Double(index), total: Double(session.entries.count))
                        HStack { Text("第 \(index + 1) / \(session.entries.count) 題"); Spacer(); Text(session.mode.rawValue) }.font(.caption).foregroundStyle(.secondary)
                        VStack(spacing: 16) {
                            Text(session.mode == .reverse || session.mode == .spelling ? TextTools.meaning(entry.meaning, omitNotes: omitNotes) : entry.english)
                                .font(.system(size: 30, weight: .bold)).multilineTextAlignment(.center)
                            Text(entry.partOfSpeech).font(.subheadline).foregroundStyle(.secondary)
                            if session.mode != .spelling && session.mode != .reverse {
                                Button { speak(entry.english) } label: { Label("聽發音", systemImage: "speaker.wave.2") }
                            }
                        }.frame(maxWidth: .infinity, minHeight: 190).padding().background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                        if session.mode == .cards {
                            if revealed {
                                Text(TextTools.meaning(entry.meaning, omitNotes: omitNotes)).font(.title2)
                                HStack {
                                    Button("還不熟") { grade(false) }.buttonStyle(.bordered)
                                    Button("記住了") { grade(true) }.buttonStyle(.borderedProminent)
                                }.disabled(answered)
                            } else { Button("翻開答案") { revealed = true }.buttonStyle(.borderedProminent) }
                        } else if session.mode == .spelling {
                            TextField("輸入英文單字或完整片語", text: $typed).textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .disabled(answered).onSubmit { if !answered && !typed.isEmpty { grade(TextTools.normalized(typed) == TextTools.normalized(answer)) } }
                            Button("確認答案") { grade(TextTools.normalized(typed) == TextTools.normalized(answer)) }.buttonStyle(.borderedProminent).disabled(answered || typed.isEmpty)
                        } else {
                            ForEach(options, id: \.self) { option in
                                Button { grade(option == answer) } label: {
                                    Text(option).frame(maxWidth: .infinity, alignment: .leading).padding()
                                        .background(answered && option == answer ? Color.green.opacity(0.18) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                                }.disabled(answered)
                            }
                        }
                        if answered {
                            Label(correct ? "答對了" : "再記一次", systemImage: correct ? "checkmark.circle.fill" : "arrow.clockwise")
                                .foregroundStyle(correct ? .green : .orange).font(.headline)
                            Text("\(entry.english) — \(TextTools.meaning(entry.meaning, omitNotes: omitNotes))").multilineTextAlignment(.center)
                            Button(index + 1 == session.entries.count ? "查看結果" : "下一題") { index += 1; prepare() }.buttonStyle(.borderedProminent)
                        }
                    }
                }.padding(24)
            }.background(Color(.systemGroupedBackground))
                .navigationTitle("每日練習").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("結束") { speaker.stopSpeaking(at: .immediate); dismiss() } } }
                .onAppear { prepare() }.onDisappear { speaker.stopSpeaking(at: .immediate) }
        }
    }
    private func prepare() {
        answered = false; typed = ""; revealed = false
        if !finished { options = QuizEngine.options(for: entry, pool: optionPool, reverse: session.mode == .reverse, omitNotes: omitNotes) }
    }
    private func grade(_ result: Bool) {
        guard !answered else { return }
        correct = result; answered = true
        if result { score += 1 } else { wrong.append(entry); store.markWrong(entry.id) }
    }
    private func speak(_ text: String) {
        speaker.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text); utterance.voice = AVSpeechSynthesisVoice(language: "en-US"); utterance.rate = 0.45
        speaker.speak(utterance)
    }
}
