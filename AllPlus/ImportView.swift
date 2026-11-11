import SwiftUI
import PhotosUI
import VisionKit
import ImageIO

struct DocumentScanner: UIViewControllerRepresentable {
    var completed: ([UIImage]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completed: completed) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController(); controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        var completed: ([UIImage]) -> Void
        init(completed: @escaping ([UIImage]) -> Void) { self.completed = completed }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            completed((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { completed([]) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { completed([]) }
    }
}

struct ImportView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let unitID: UUID
    @State private var photos: [PhotosPickerItem] = []
    @State private var scanning = false
    @State private var busy = false
    @State private var rawText = ""
    @State private var drafts: [Entry] = []
    @State private var message = ""
    @State private var editor: Entry?
    @State private var layout: PageLayout = .columns
    @State private var preview: UIImage?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("拍清楚，校對一次，就能開始複習。") .font(.headline)
                    Text("先校正頁面、去陰影，再進行中英辨識。整頁拍攝可選左右兩欄；若只拍單欄，請切換版面。略過例句和練習題。")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("照片版面", selection: $layout) {
                        ForEach(PageLayout.allCases) { Text($0.rawValue).tag($0) }
                    }.disabled(busy)
                    Button { scanning = true } label: { Label("拍攝雜誌", systemImage: "doc.viewfinder") }
                        .disabled(busy || !VNDocumentCameraViewController.isSupported)
                    PhotosPicker(selection: $photos, maxSelectionCount: 10, matching: .images) {
                        Label("從照片選取（最多 10 張）", systemImage: "photo.on.rectangle")
                    }.disabled(busy)
                    if busy { ProgressView("正在校正、去陰影與辨識…") }
                    if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
                }
                if let preview = preview {
                    Section("去陰影預覽（最近處理的一張）") {
                        Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 280)
                        Text("若仍有反光、模糊或文字被裁切，建議重拍；去陰影無法還原被遮住的文字。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("辨識文字（可修正後重新提取）") {
                    TextEditor(text: $rawText).frame(minHeight: 130).font(.caption)
                    Button("從文字重新提取") { drafts = MagazineParser.parse(rawText); message = "提取 \(drafts.count) 項，請檢查並補充詞性。" }
                        .disabled(rawText.isEmpty || busy)
                }
                Section("待存入 \(drafts.count) 項 · 點選校對，左滑刪除") {
                    ForEach(drafts) { item in
                        Button { editor = item } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(item.english).font(.headline).foregroundStyle(.primary)
                                    Text(item.kind.rawValue).font(.caption).foregroundStyle(.tint)
                                }
                                Text("\(item.partOfSpeech.isEmpty ? "待補詞性" : item.partOfSpeech)  \(item.meaning)")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }.onDelete { drafts.remove(atOffsets: $0) }
                    Button("手動補一筆") { editor = Entry(english: "", meaning: "", partOfSpeech: "") }
                }
            }.navigationTitle("照片匯入").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("存入單元") { store.add(drafts, to: unitID); dismiss() }.disabled(drafts.isEmpty || busy)
                    }
                }
                .interactiveDismissDisabled(busy)
                .sheet(isPresented: $scanning) {
                    DocumentScanner { images in scanning = false; Task { await recognize(images) } }
                }
                .sheet(item: $editor) { entry in
                    EntryEditor(entry: entry) { updated in
                        if let index = drafts.firstIndex(where: { $0.id == updated.id }) { drafts[index] = updated }
                        else { drafts.append(updated) }
                    }
                }
                .onChange(of: photos) { items in
                    guard !items.isEmpty else { return }
                    Task {
                        busy = true
                        var loaded = 0
                        for item in items {
                            if let data = try? await item.loadTransferable(type: Data.self), let image = downsample(data) {
                                loaded += 1
                                await recognize([image])
                                busy = true
                            }
                        }
                        busy = false
                        if loaded < items.count { message += " 有 \(items.count - loaded) 張無法讀取，請重新選取。" }
                        photos = []
                    }
                }
        }
    }
    private func downsample(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 3600,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
    @MainActor private func recognize(_ images: [UIImage]) async {
        guard !images.isEmpty else { return }
        busy = true; defer { busy = false }
        var errors = 0
        for image in images {
            do {
                let page = try await ImagePreparation.prepare(image)
                preview = UIImage(cgImage: page.cleaned)
                let text = try await OCR.recognize(page, layout: layout)
                rawText += (rawText.isEmpty ? "" : "\n\n") + text
                drafts += TextTools.deduplicated(MagazineParser.parse(text), existing: drafts)
            } catch { errors += 1 }
        }
        message = "已提取 \(drafts.count) 項。辨識可能有誤，請校對再存入。" + (errors > 0 ? "其中 \(errors) 張辨識失敗，請重拍。" : "")
    }
}
