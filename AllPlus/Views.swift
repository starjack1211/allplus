import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct RootView: View {
    var body: some View {
        TabView {
            UnitsView().tabItem { Label("單元", systemImage: "books.vertical") }
            QuizSetupView().tabItem { Label("測驗", systemImage: "checkmark.seal") }
            SettingsView().tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
    }
}
struct UnitsView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var adding = false
    @State private var title = ""
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("把今天讀到的，變成記得的。")
                            .font(.title2.bold())
                        Text("ALL+ STUDY NOTEBOOK").font(.caption.monospaced()).foregroundStyle(.secondary)
                        HStack {
                            Label("\(store.library.units.count) 單元", systemImage: "square.stack")
                            Spacer()
                            Text("\(store.library.units.flatMap(\.entries).count) 個學習項目")
                        }.font(.subheadline)
                    }.padding(.vertical, 12)
                }
                Section("我的單元 · 點編輯可拖曳排序") {
                    if store.library.units.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("從一頁雜誌開始").font(.headline)
                            Text("新增單元，再拍攝 Vocabulary 與 Language Spotlight。照片會先校正並去陰影，再辨識成清單。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 12)
                    }
                    ForEach(store.library.units) { unit in
                        NavigationLink(value: unit.id) {
                            HStack(spacing: 14) {
                                Image(systemName: "book.closed.fill").font(.title2).foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(unit.title).font(.headline)
                                    Text("\(unit.entries.filter { $0.kind == .word }.count) 單字 · \(unit.entries.filter { $0.kind == .phrase }.count) 片語")
                                        .font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 6)
                            }
                        }
                    }.onMove { source, destination in
                        store.library.units.move(fromOffsets: source, toOffset: destination); store.save()
                    }
                }
            }
            .navigationTitle("All+ 單字本")
            .navigationDestination(for: UUID.self) { UnitView(unitID: $0) }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { EditButton() }
                ToolbarItem(placement: .navigationBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("新增單元") }
            }
            .alert("新增單元", isPresented: $adding) {
                TextField("例如：11 月・紐約漫遊", text: $title)
                Button("取消", role: .cancel) { title = "" }
                Button("建立") {
                    let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty { store.library.units.append(Unit(title: clean)); store.save() }
                    title = ""
                }
            }
        }
    }
}

struct UnitView: View {
    @EnvironmentObject var store: LibraryStore
    let unitID: UUID
    @State private var kind: EntryKind = .word
    @State private var query = ""
    @State private var importing = false
    @State private var editing: Entry?
    @State private var renaming = false
    @State private var title = ""
    @State private var deleting = false
    @Environment(\.dismiss) private var dismiss
    @AppStorage("omitNotes") private var omitNotes = true
    private var unit: Unit? { store.library.units.first { $0.id == unitID } }
    private var entries: [Entry] {
        (unit?.entries ?? []).filter {
            $0.kind == kind && (query.isEmpty || $0.english.localizedCaseInsensitiveContains(query) || $0.meaning.contains(query))
        }
    }
    var body: some View {
        List {
            Section {
                Button { importing = true } label: {
                    Label("拍照／選照片辨識", systemImage: "camera.viewfinder").font(.headline).padding(.vertical, 10)
                }
                Picker("類別", selection: $kind) {
                    ForEach(EntryKind.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
            }
            Section("\(entries.count) 個\(kind.rawValue) · 點選可編輯") {
                if entries.isEmpty { Text("還沒有內容，拍照辨識或按右上角手動新增。").foregroundStyle(.secondary) }
                ForEach(entries) { entry in
                    Button { editing = entry } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(entry.english).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                                Text(entry.partOfSpeech.isEmpty ? "片語／待補詞性" : entry.partOfSpeech).font(.caption).foregroundStyle(.tint)
                                Text(TextTools.meaning(entry.meaning, omitNotes: omitNotes)).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if entry.starred { Image(systemName: "star.fill").foregroundStyle(.orange) }
                        }.padding(.vertical, 6)
                    }
                    .swipeActions(edge: .leading) {
                        Button { var copy = entry; copy.starred.toggle(); store.update(copy, in: unitID) } label: { Label("收藏", systemImage: "star") }.tint(.orange)
                    }
                    .swipeActions {
                        Button("刪除", role: .destructive) {
                            guard let index = store.library.units.firstIndex(where: { $0.id == unitID }) else { return }
                            store.library.units[index].entries.removeAll { $0.id == entry.id }; store.save()
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "搜尋英文或中文")
        .navigationTitle(unit?.title ?? "單元").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { editing = Entry(english: "", meaning: "", partOfSpeech: "", kind: kind) } label: { Image(systemName: "plus") }.accessibilityLabel("手動新增")
            Menu {
                Button("重新命名") { title = unit?.title ?? ""; renaming = true }
                Button("刪除此單元", role: .destructive) { deleting = true }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .sheet(isPresented: $importing) { ImportView(unitID: unitID) }
        .sheet(item: $editing) { entry in
            EntryEditor(entry: entry) { result in
                if unit?.entries.contains(where: { $0.id == result.id }) == true { store.update(result, in: unitID) }
                else { store.add([result], to: unitID) }
            }
        }
        .alert("重新命名", isPresented: $renaming) {
            TextField("單元名稱", text: $title)
            Button("取消", role: .cancel) {}
            Button("儲存") {
                if let index = store.library.units.firstIndex(where: { $0.id == unitID }), !title.trimmingCharacters(in: .whitespaces).isEmpty {
                    store.library.units[index].title = title; store.save()
                }
            }
        }
        .confirmationDialog("確定刪除整個單元及其內容？", isPresented: $deleting, titleVisibility: .visible) {
            Button("刪除單元", role: .destructive) { store.library.units.removeAll { $0.id == unitID }; store.save(); dismiss() }
        }
    }
}

struct EntryEditor: View {
    @State var entry: Entry
    var onSave: (Entry) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Picker("類別", selection: $entry.kind) { ForEach(EntryKind.allCases) { Text($0.rawValue).tag($0) } }
                TextField("英文", text: $entry.english).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("詞性，例如 n. / v. 或 phr.", text: $entry.partOfSpeech).textInputAutocapitalization(.never)
                TextField("中文意思", text: $entry.meaning, axis: .vertical).lineLimit(3...8)
                Toggle("加入收藏", isOn: $entry.starred)
            }.navigationTitle("編輯學習項目").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("儲存") { entry.english = entry.english.trimmingCharacters(in: .whitespacesAndNewlines); onSave(entry); dismiss() }
                            .disabled(entry.english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || entry.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var cloud: CloudService
    @AppStorage("omitNotes") private var omitNotes = true
    @State private var backupURL: URL?
    @State private var importing = false
    @State private var overwrite = false
    @State private var restoring = false
    var body: some View {
        NavigationStack {
            Form {
                Section("閱讀偏好") { Toggle("省略中文意思中的括號說明", isOn: $omitNotes) }
                Section("Google 帳號與雲端保存") {
                    if let email = cloud.email {
                        Label(email, systemImage: "person.crop.circle.badge.checkmark")
                        Button("備份目前資料至雲端") { overwrite = true }.disabled(cloud.busy)
                        Button("從雲端取回（合併新項目）") { restoring = true }.disabled(cloud.busy)
                        Button("登出") { cloud.signOut() }.disabled(cloud.busy)
                    } else {
                        Button("使用 Google 登入") { Task { await cloud.signIn() } }.disabled(cloud.busy || !cloud.configured)
                    }
                    Text(cloud.status).font(.caption).foregroundStyle(.secondary)
                    if cloud.busy { ProgressView() }
                    Text("平時自動保存在手機。雲端為手動備份；登入其他手機後可取回。照片只用於手機辨識，不會上傳雲端。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("資料備份") {
                    Button("準備匯出 JSON") {
                        do { backupURL = try store.exportURL() } catch { store.error = error.localizedDescription }
                    }
                    if let url = backupURL { ShareLink("分享／儲存備份檔", item: url) }
                    Button("匯入 JSON（合併新項目）") { importing = true }
                }
                Section("關於") {
                    Text("All+ 單字本 1.0").font(.headline)
                    Text("個人學習工具，並非雜誌官方 App。辨識結果請校對後儲存。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("我的學習")
                .onAppear { cloud.refresh() }
                .confirmationDialog("雲端同一帳號的舊備份將被取代，是否繼續？", isPresented: $overwrite, titleVisibility: .visible) {
                    Button("備份目前資料") { Task { await cloud.backup(store.library) } }
                }
                .confirmationDialog("合併雲端新增的單元與項目；已有項目的本機版本會保留。", isPresented: $restoring, titleVisibility: .visible) {
                    Button("取回並合併") { Task { if let library = await cloud.restore() { store.merge(library) } } }
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    do {
                        let url = try result.get(); let allowed = url.startAccessingSecurityScopedResource()
                        defer { if allowed { url.stopAccessingSecurityScopedResource() } }
                        let data = try Data(contentsOf: url)
                        guard data.count < 20_000_000 else { throw CocoaError(.fileReadTooLarge) }
                        store.merge(try JSONDecoder().decode(Library.self, from: data))
                    } catch { store.error = "匯入失敗：\(error.localizedDescription)" }
                }
        }
    }
}
