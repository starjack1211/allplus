import SwiftUI
import FirebaseCore
import GoogleSignIn

@main struct AllPlusApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var cloud = CloudService()
    init() {
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let options = FirebaseOptions(contentsOfFile: path) { FirebaseApp.configure(options: options) }
    }
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).environmentObject(cloud)
                .tint(Color(red: 0.16, green: 0.37, blue: 0.31))
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
                .alert("資料提示", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                    Button("知道了") { store.error = nil }
                } message: { Text(store.error ?? "") }
        }
    }
}
