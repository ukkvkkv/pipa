import SwiftUI

@main
struct PipaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        Paths.migrateOldName()
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        Window("Pipa", id: "main") {
            ContentView()
                .environment(model)
                .frame(width: 680, height: 408)   // + шапка 52 = 680×460
                .task { await model.start() }
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Перейти") {
                ForEach(Array(Section.allCases.enumerated()), id: \.element) { i, s in
                    Button(s.title) { model.section = s }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                }
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Размер окна постоянный — зелёной кнопке разворачивать нечего.
        DispatchQueue.main.async {
            for w in NSApp.windows where w.styleMask.contains(.titled) {
                w.standardWindowButton(.zoomButton)?.isEnabled = false
                w.titleVisibility = .hidden   // macOS 14: toolbar(removing: .title) там нет
            }
        }
    }
}

