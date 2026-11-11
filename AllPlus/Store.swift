import SwiftUI

@MainActor final class LibraryStore: ObservableObject {
    @Published var library = Library()
    @Published var error: String?
    private let directory: URL
    private var file: URL { directory.appendingPathComponent("library.json") }
    init() {
        directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        load()
    }
    private func load() {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do { library = try JSONDecoder().decode(Library.self, from: Data(contentsOf: file)) }
        catch { self.error = "讀取資料失敗，原始檔已保留：\(error.localizedDescription)" }
    }
    func save() {
        do { try JSONEncoder().encode(library).write(to: file, options: .atomic) }
        catch { self.error = "儲存失敗：\(error.localizedDescription)" }
    }
    func add(_ entries: [Entry], to id: UUID) {
        guard let index = library.units.firstIndex(where: { $0.id == id }) else { return }
        library.units[index].entries += TextTools.deduplicated(entries, existing: library.units[index].entries)
        save()
    }
    func update(_ entry: Entry, in id: UUID) {
        guard let u = library.units.firstIndex(where: { $0.id == id }),
              let e = library.units[u].entries.firstIndex(where: { $0.id == entry.id }) else { return }
        library.units[u].entries[e] = entry
        save()
    }
    func markWrong(_ id: UUID) {
        for u in library.units.indices {
            if let e = library.units[u].entries.firstIndex(where: { $0.id == id }) {
                library.units[u].entries[e].wrongCount += 1
            }
        }
        save()
    }
    func exportURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AllPlus-backup.json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(library).write(to: url, options: .atomic)
        return url
    }
    func merge(_ incoming: Library) {
        for unit in incoming.units {
            if let index = library.units.firstIndex(where: { $0.id == unit.id }) {
                let localIDs = Set(library.units[index].entries.map(\.id))
                library.units[index].entries += unit.entries.filter { !localIDs.contains($0.id) }
            } else { library.units.append(unit) }
        }
        save()
    }
}
