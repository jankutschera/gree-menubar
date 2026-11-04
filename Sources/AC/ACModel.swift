import Foundation

@MainActor
final class ACModel: ObservableObject {
    @Published private(set) var s: [String: Int] = [:]
    @Published private(set) var error: String?
    private let client = GreeClient()
    private var timer: Timer?

    static let demoState = ["Pow": 1, "Mod": 1, "SetTem": 22, "WdSpd": 0, "SwUpDn": 1, "SvSt": 1, "Lig": 1, "TemSen": 63]

    var on: Bool { s["Pow"] == 1 }
    var setTemp: Int { s["SetTem"] ?? 24 }
    /// Gree reports the room sensor with a +40 offset.
    var roomTemp: Int? { s["TemSen"].map { $0 >= 40 ? $0 - 40 : $0 } }

    init(demo: [String: Int]? = nil) {
        // AC_DEMO=1 (or an explicit state) shows fixed data without touching the network: README media.
        if let demo = demo ?? (ProcessInfo.processInfo.environment["AC_DEMO"] != nil ? Self.demoState : nil) {
            s = demo
            return
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        Task {
            do { s = try await client.status(); error = nil } catch { self.error = error.localizedDescription }
        }
    }

    func set(_ pairs: [(String, Int)]) {
        for (k, v) in pairs { s[k] = v }
        Task {
            do { try await client.command(pairs); error = nil } catch { self.error = error.localizedDescription }
        }
    }

    func toggle(_ key: String) { set([(key, s[key] == 1 ? 0 : 1)]) }
}
