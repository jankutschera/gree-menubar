import Combine
import ServiceManagement
import SwiftUI

@main
struct ACApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        // `AC --snapshot out.png` renders the popover to a PNG (visual check without clicking).
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                MainActor.assumeIsolated {
                    let model = ACModel()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        MainActor.assumeIsolated {
                            let r = ImageRenderer(content: ContentView(ac: model))
                            r.scale = 2
                            if let cg = r.cgImage {
                                let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
                                try? data?.write(to: URL(fileURLWithPath: path))
                            }
                            exit(0)
                        }
                    }
                }
            }
        }
        // `AC --login-item on|off` registers/unregisters launch at login, then exits.
        if let i = CommandLine.arguments.firstIndex(of: "--login-item"), i + 1 < CommandLine.arguments.count {
            do {
                if CommandLine.arguments[i + 1] == "on" { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch { print("ERROR:", error.localizedDescription) }
            print("login item status:", SMAppService.mainApp.status.rawValue, "(1 = enabled, 2 = needs approval in System Settings)")
            exit(0)
        }
        // `AC --status` prints the live state and exits (used to verify the connection).
        guard CommandLine.arguments.contains("--status") else { return }
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                let c = GreeClient()
                // `--set SetTem=23` sends one command before reading back.
                if let i = CommandLine.arguments.firstIndex(of: "--set"), i + 1 < CommandLine.arguments.count {
                    let kv = CommandLine.arguments[i + 1].split(separator: "=")
                    if kv.count == 2, let v = Int(kv[1]) { try await c.command([(String(kv[0]), v)]) }
                }
                print(try await c.status().sorted { $0.key < $1.key })
            } catch { print("ERROR:", error.localizedDescription) }
            done.signal()
        }
        done.wait()
        exit(0)
    }

    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// Status item + popover (instead of MenuBarExtra) so a right-click can show a Quit menu.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let ac = ACModel()
    private let popover = NSPopover()
    private var item: NSStatusItem?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let host = NSHostingController(rootView: ContentView(ac: ac))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.item = item
        guard let button = item.button else { return }
        button.image = NSImage(systemSymbolName: "air.conditioner.horizontal", accessibilityDescription: "AC")
        button.imagePosition = .imageLeft
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        ac.$s.sink { s in
            let temp = s["SetTem"].map(String.init) ?? ""
            button.title = s["Pow"] == 1 ? " \(temp)°" : ""
        }.store(in: &bag)
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        try? service.status == .enabled ? service.unregister() : service.register()
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let login = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
            login.target = self
            login.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit AC", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            item?.menu = menu
            sender.performClick(nil)
            item?.menu = nil
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
