import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn

@MainActor final class CloudService: ObservableObject {
    @Published var email: String?
    @Published var status = "尚未連線"
    @Published var busy = false
    var configured: Bool { FirebaseApp.app() != nil }
    var signedIn: Bool { configured && Auth.auth().currentUser != nil }
    func refresh() { email = configured ? Auth.auth().currentUser?.email : nil }
    func signIn() async {
        guard let clientID = FirebaseApp.app()?.options.clientID else { status = "請先加入 Firebase iOS 設定檔，重新編譯。"; return }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        busy = true; defer { busy = false }
        do {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: root)
            guard let token = result.user.idToken?.tokenString else { status = "無法取得登入憑證"; return }
            let credential = GoogleAuthProvider.credential(withIDToken: token, accessToken: result.user.accessToken.tokenString)
            _ = try await Auth.auth().signIn(with: credential)
            refresh(); status = "登入成功，可備份或取回資料"
        } catch { status = "登入未完成：\(error.localizedDescription)" }
    }
    private func document() -> DocumentReference? {
        guard configured, let uid = Auth.auth().currentUser?.uid else { return nil }
        return Firestore.firestore().collection("users").document(uid).collection("backups").document("library")
    }
    func backup(_ library: Library) async {
        guard let ref = document() else { status = "請先登入 Google"; return }
        busy = true; defer { busy = false }
        do {
            let data = try JSONEncoder().encode(library)
            guard data.count < 850_000 else { status = "資料超過單次雲端備份容量，請先匯出 JSON 備份。"; return }
            try await ref.setData(["json": String(decoding: data, as: UTF8.self), "updatedAt": FieldValue.serverTimestamp()])
            status = "已備份至 Google 帳號 · \(Date().formatted(date: .omitted, time: .shortened))"
        } catch { status = "備份失敗：\(error.localizedDescription)" }
    }
    func restore() async -> Library? {
        guard let ref = document() else { status = "請先登入 Google"; return nil }
        busy = true; defer { busy = false }
        do {
            let snapshot = try await ref.getDocument(source: .server)
            guard let json = snapshot.data()?["json"] as? String else { status = "此帳號尚無備份"; return nil }
            let library = try JSONDecoder().decode(Library.self, from: Data(json.utf8))
            status = "已取回雲端資料"; return library
        } catch { status = "取回失敗：\(error.localizedDescription)"; return nil }
    }
    func signOut() {
        do { try Auth.auth().signOut(); GIDSignIn.sharedInstance.signOut(); email = nil; status = "已登出，本機資料仍保留" }
        catch { status = error.localizedDescription }
    }
}
