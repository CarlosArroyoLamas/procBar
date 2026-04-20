import SwiftUI

@main
struct ProcbarApp: App {
    var body: some Scene {
        MenuBarExtra {
            Text("Hello, Procbar")
                .padding()
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)

        Settings {
            Text("Settings — to be built")
                .padding()
        }
    }
}
