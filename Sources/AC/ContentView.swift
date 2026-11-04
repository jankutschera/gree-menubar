import SwiftUI

private let accent = Color(red: 0.88, green: 0.78, blue: 0.62)
private let card = Color(white: 0.10)
private let dim = Color.white.opacity(0.55)
private let hairline = Color.white.opacity(0.08)

private let modes = [(0, "Auto", "sparkles"), (1, "Cool", "snowflake"), (2, "Dry", "drop"),
                     (3, "Fan", "fan"), (4, "Heat", "flame")]
private let fans = [(0, "Auto"), (1, "Low"), (2, "Medium"), (3, "High")]
private let airflow = [(0, "Off"), (1, "Swing"), (2, "Top"), (3, "Upper"), (4, "Middle"), (5, "Lower"), (6, "Bottom")]

struct ContentView: View {
    @ObservedObject var ac: ACModel
    @State private var draft = 24.0
    @State private var dragging = false
    @State private var sendTask: Task<Void, Never>?
    @State private var showMore = false
    @State private var hovered: String?

    init(ac: ACModel) {
        _ac = ObservedObject(wrappedValue: ac)
        _draft = State(initialValue: Double(ac.setTemp))
    }

    private var ready: Bool { !ac.s.isEmpty }

    var body: some View {
        VStack(spacing: 18) {
            header
            ACHero(on: ac.on, temp: Int(draft)).frame(height: 150)
            temperature
            slider
            tiles
            footer
            if showMore { more }
        }
        .padding(22)
        .frame(width: 380)
        .foregroundStyle(.white)
        .background(Color(white: 0.05))
        .environment(\.colorScheme, .dark)
        .environment(\.setHint) { hovered = $0 }
        .disabled(!ready)
        .onChange(of: ac.s["SetTem"]) { _, v in
            if !dragging, sendTask == nil, let v { draft = Double(v) }
        }
        // Send the target a moment after the last change (slider drag, +/- taps).
        .onChange(of: draft) { _, v in
            guard Int(v) != ac.setTemp else { return }
            sendTask?.cancel()
            sendTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                ac.set([("SetTem", Int(v))])
                sendTask = nil
            }
        }
        .onAppear { ac.refresh(); draft = Double(ac.setTemp) }
    }

    // MARK: sections

    private var header: some View {
        HStack {
            Image(systemName: "thermometer.medium").foregroundStyle(dim)
            Text("Room").foregroundStyle(dim)
            Text(ac.roomTemp.map { "\($0)°C" } ?? "–").fontWeight(.semibold)
            Spacer()
            Button { ac.toggle("Pow") } label: {
                Image(systemName: "power")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(ac.on ? accent : .white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(card))
                    .overlay(Circle().stroke(ac.on ? accent.opacity(0.7) : hairline, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .hint(ac.on ? "Turn the AC off" : "Turn the AC on")
        }
        .font(.title2)
        .hint("Room temperature, measured by the AC's own sensor")
    }

    private var temperature: some View {
        HStack(alignment: .center) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(draft))").font(.system(size: 84, weight: .light))
                Text("°C").font(.title).foregroundStyle(dim)
            }
            .hint("Target temperature")
            Spacer()
            ecoPanel
        }
    }

    private var ecoPanel: some View {
        let on = ac.s["SvSt"] == 1
        return Button { ac.toggle("SvSt") } label: {
            HStack(spacing: 10) {
                Image(systemName: "leaf").foregroundStyle(on ? accent : dim)
                Text("Eco Mode").fontWeight(.semibold).lineLimit(1).fixedSize()
                ZStack(alignment: on ? .trailing : .leading) {
                    Capsule().fill(on ? accent : Color(white: 0.22)).frame(width: 50, height: 30)
                    Circle().fill(.white).frame(width: 24, height: 24).padding(3)
                }
                .animation(.easeOut(duration: 0.15), value: on)
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 18).fill(card))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(hairline))
        }
        .buttonStyle(.plain)
        .hint("Eco mode: saves energy by limiting the AC's power (works best in Cool mode)")
    }

    private var slider: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                stepButton("minus", -1, help: "Lower the target by 1°")
                PillSlider(value: $draft, range: 16...30) { dragging = $0 }
                    .hint("Drag to set the target temperature (16–30°C)")
                stepButton("plus", 1, help: "Raise the target by 1°")
            }
            HStack {
                Text("16°"); Spacer(); Text("30°")
            }
            .font(.callout).foregroundStyle(dim).padding(.horizontal, 62)
        }
    }

    private func stepButton(_ icon: String, _ delta: Double, help: String) -> some View {
        Button {
            draft = min(30, max(16, draft + delta))
        } label: {
            Image(systemName: icon).font(.title2.weight(.medium))
                .frame(width: 52, height: 52)
                .background(Circle().fill(card))
        }
        .buttonStyle(.plain)
        .hint(help)
    }

    private var tiles: some View {
        let mode = modes.first { $0.0 == ac.s["Mod"] } ?? modes[0]
        let fan = fans.first { $0.0 == ac.s["WdSpd"] }?.1 ?? "Auto"
        let air = airflow.first { $0.0 == ac.s["SwUpDn"] }?.1 ?? "Off"
        let sleep = ac.s["SwhSlp"] == 1
        return HStack(spacing: 8) {
            menuTile("Mode", mode.1, mode.2, help: "Operating mode: Auto, Cool, Dry (dehumidify), Fan only, Heat") {
                ForEach(modes, id: \.0) { m in Button(m.1) { ac.set([("Mod", m.0)]) } }
            }
            menuTile("Fan speed", fan, "fan", help: "Fan speed. Auto lets the AC decide") {
                ForEach(fans, id: \.0) { f in Button(f.1) { ac.set([("WdSpd", f.0)]) } }
            }
            Button { ac.toggle("SwhSlp") } label: {
                tileBody("Sleep", sleep ? "On" : "Off", "moon", trailing: "circle.fill", lit: sleep)
            }
            .buttonStyle(.plain)
            .hint("Sleep mode: slowly adjusts the temperature overnight and runs quieter")
            menuTile("Airflow", air, "wind", help: "Vertical flap: Swing moves it continuously, or fix it at a position") {
                ForEach(airflow, id: \.0) { a in Button(a.1) { ac.set([("SwUpDn", a.0)]) } }
            }
        }
    }

    private var footer: some View {
        HStack {
            Image(systemName: ac.error == nil ? "checkmark.shield" : "exclamationmark.triangle").foregroundStyle(dim)
            Text(hovered ?? ac.error ?? (ready ? "Connected" : "Searching…"))
                .foregroundStyle(hovered == nil ? dim : .white)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button { withAnimation { showMore.toggle() } } label: {
                Image(systemName: "slider.horizontal.3").font(.title3).foregroundStyle(showMore ? accent : dim)
            }
            .buttonStyle(.plain)
            .hint("More controls")
        }
        .font(.callout)
    }

    private var more: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                chip("Turbo", "bolt", on: ac.s["Tur"] == 1, help: "Turbo: maximum power for fast cooling or heating") { ac.toggle("Tur") }
                chip("Quiet", "speaker.slash", on: (ac.s["Quiet"] ?? 0) > 0, help: "Quiet: lowest fan noise") { ac.toggle("Quiet") }
                chip("Light", "lightbulb", on: ac.s["Lig"] == 1, help: "Display light on the AC unit") { ac.toggle("Lig") }
                chip("Health", "heart", on: ac.s["Health"] == 1, help: "Health: air-cleaning function (ionizer)") { ac.toggle("Health") }
                chip("X-Fan", "wind.snow", on: ac.s["Blo"] == 1, help: "X-Fan: keeps the fan running after switch-off to dry the unit") { ac.toggle("Blo") }
                chip("Swing ↔", "arrow.left.and.right", on: ac.s["SwingLfRig"] == 1, help: "Left/right swing (only on units with a horizontal louver)") { ac.toggle("SwingLfRig") }
            }
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain).foregroundStyle(dim).font(.callout).hint("Quit the AC app")
        }
    }

    // MARK: components

    private func tileBody(_ title: String, _ value: String, _ icon: String, trailing: String, lit: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Image(systemName: icon).font(.title).foregroundStyle(lit ? accent : dim)
                Spacer()
                Image(systemName: trailing).font(trailing == "circle.fill" ? .system(size: 7) : .callout)
                    .foregroundStyle(lit && trailing == "circle.fill" ? accent : dim)
                    .padding(.top, 6)
            }
            Spacer(minLength: 8)
            Text(title).font(.callout).foregroundStyle(dim).lineLimit(1).minimumScaleFactor(0.75)
            Text(value).font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18).fill(card))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(hairline))
        .contentShape(Rectangle())
    }

    private func menuTile<Items: View>(_ title: String, _ value: String, _ icon: String, help: String,
                                       @ViewBuilder items: () -> Items) -> some View {
        Menu { items() } label: { tileBody(title, value, icon, trailing: "chevron.down") }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).hint(help)
    }

    private func chip(_ title: String, _ icon: String, on: Bool, help: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.callout)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .foregroundStyle(on ? Color.black : Color.white)
                .background(Capsule().fill(on ? accent : card))
        }
        .buttonStyle(.plain)
        .hint(help)
    }
}

/// Thick pill track with a warm gradient fill and a white thumb.
private struct PillSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onEditing: (Bool) -> Void

    var body: some View {
        GeometryReader { g in
            let thumbW: CGFloat = 38, h = g.size.height
            let frac = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let x = frac * (g.size.width - thumbW)
            ZStack(alignment: .leading) {
                Capsule().fill(Color(white: 0.08))
                Capsule()
                    .fill(LinearGradient(colors: [accent.opacity(0.10), accent.opacity(0.75)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: x + thumbW)
                RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.95))
                    .frame(width: thumbW - 6, height: h - 14)
                    .offset(x: x + 3)
                    .shadow(color: .black.opacity(0.4), radius: 4)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { f in
                    onEditing(true)
                    let p = min(1, max(0, (f.location.x - thumbW / 2) / (g.size.width - thumbW)))
                    value = (range.lowerBound + p * (range.upperBound - range.lowerBound)).rounded()
                }
                .onEnded { _ in onEditing(false) })
        }
        .frame(height: 54)
    }
}

/// Wall unit drawn in SwiftUI, with animated airflow while the AC is on.
private struct ACHero: View {
    let on: Bool
    let temp: Int

    var body: some View {
        ZStack(alignment: .top) {
            if on {
                TimelineView(.animation) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    Canvas { ctx, size in
                        let n = 16
                        for i in 0..<n {
                            let f = CGFloat(i) / CGFloat(n - 1)
                            let x0 = size.width / 2 + (f - 0.5) * 170
                            var p = Path()
                            p.move(to: CGPoint(x: x0, y: 62))
                            p.addLine(to: CGPoint(x: x0 + (f - 0.5) * 70, y: size.height))
                            ctx.stroke(p, with: .linearGradient(Gradient(colors: [.white.opacity(0.55), .white.opacity(0)]),
                                                                startPoint: CGPoint(x: x0, y: 62), endPoint: CGPoint(x: x0, y: size.height)),
                                       style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [7, 9], dashPhase: -t * 40))
                        }
                    }
                }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(LinearGradient(colors: [.white, Color(white: 0.80)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.5), radius: 10, y: 6)
                Capsule().fill(Color(white: 0.16)).frame(width: 190, height: 7).offset(y: 20)
                Text(on ? "\(temp)" : "--").font(.system(size: 9, weight: .medium)).foregroundStyle(.gray)
                    .offset(x: 80, y: -10)
            }
            .frame(width: 230, height: 62)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: hover hints (native .help tooltips don't show in a menu bar window)

private struct SetHintKey: EnvironmentKey { static let defaultValue: (String?) -> Void = { _ in } }
private extension EnvironmentValues {
    var setHint: (String?) -> Void {
        get { self[SetHintKey.self] }
        set { self[SetHintKey.self] = newValue }
    }
}

private struct HintModifier: ViewModifier {
    let text: String
    @Environment(\.setHint) private var setHint
    func body(content: Content) -> some View {
        content.onHover { setHint($0 ? text : nil) }
    }
}

private extension View {
    func hint(_ text: String) -> some View { modifier(HintModifier(text: text)) }
}
