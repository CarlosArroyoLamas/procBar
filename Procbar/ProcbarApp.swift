import SwiftUI

@main
struct ProcbarApp: App {
    var body: some Scene {
        MenuBarExtra("Procbar", systemImage: "square.stack.3d.up.fill") {
            Text("Hello, Procbar")
                .padding()
        }
        .menuBarExtraStyle(.window)

        Settings {
            Text("Settings — to be built")
                .padding()
        }
    }
}
