import SwiftUI

enum BrandColor {
    static let navy = Color(red: 11.0 / 255, green: 28.0 / 255, blue: 51.0 / 255)
    static let coral = Color(red: 240.0 / 255, green: 120.0 / 255, blue: 80.0 / 255)
    static let amber = Color(red: 226.0 / 255, green: 176.0 / 255, blue: 67.0 / 255)
}

struct SurviveLogo: View {
    var drawing = false
    var showsWordmark = true
    var stacked = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if drawing && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let cycle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.6) / 3.6
                    mark(progress: Self.trace(cycle), ink: Self.ink(cycle))
                }
            } else {
                mark(progress: 1, ink: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(showsWordmark ? "Survive Miami. Live the Miami Life." : "Survive Miami")
    }

    private func mark(progress: Double, ink: Double) -> some View {
        let wheel = WheelMark(progress: progress)
        let words = VStack(alignment: stacked ? .center : .leading, spacing: stacked ? 6 : 2) {
            Text("Survive Miami")
                .font(stacked ? .largeTitle.weight(.heavy) : .title3.weight(.heavy))
                .foregroundStyle(.white)
            Text("Live the Miami Life.")
                .font(.caption.weight(.medium))
                .foregroundStyle(BrandColor.coral)
        }
        .opacity(ink)

        return Group {
            if !showsWordmark {
                wheel
            } else if stacked {
                VStack(spacing: 14) {
                    wheel.frame(width: 220, height: 220)
                    words
                }
            } else {
                HStack(alignment: .center, spacing: 10) {
                    wheel.frame(width: 56, height: 56)
                    words
                }
            }
        }
    }

    private static func trace(_ t: Double) -> Double {
        if t < 0.42 { return t / 0.42 }
        if t < 0.76 { return 1 }
        return max(0, 1 - (t - 0.76) / 0.24)
    }

    private static func ink(_ t: Double) -> Double {
        if t < 0.52 { return 0 }
        if t < 0.64 { return (t - 0.52) / 0.12 }
        if t < 0.84 { return 1 }
        return max(0, 1 - (t - 0.84) / 0.16)
    }
}

private struct WheelMark: View {
    var progress: Double

    var body: some View {
        GeometryReader { geo in
            let unit = min(geo.size.width, geo.size.height) / 280
            ZStack {
                stroke(OuterArcs(), width: 18 * unit, from: 0.00, to: 0.24)
                stroke(TopArcs(), width: 12 * unit, from: 0.16, to: 0.36)
                stroke(Spokes(), width: 8 * unit, from: 0.36, to: 0.58)
                stroke(HubAndGondolas(), width: 7 * unit, from: 0.50, to: 0.74)
                stroke(Support(), width: 9 * unit, from: 0.66, to: 0.88)
                stroke(Orbit(), width: 8 * unit, from: 0.80, to: 0.98)
                Orbit()
                    .fill(BrandColor.coral)
                    .opacity(fillAmount)
            }
        }
    }

    private var fillAmount: Double {
        let drawn = slice(progress, 0.80, 0.98)
        if drawn < 0.82 { return 0 }
        return min(1, (drawn - 0.82) / 0.18)
    }

    private func stroke<S: Shape>(_ shape: S, width: CGFloat, from: Double, to: Double) -> some View {
        let amount = slice(progress, from, to)
        return shape
            .trim(from: 0, to: CGFloat(amount))
            .stroke(BrandColor.coral, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            .opacity(amount > 0.001 ? 1 : 0)
    }

    private func slice(_ progress: Double, _ from: Double, _ to: Double) -> Double {
        min(1, max(0, (progress - from) / (to - from)))
    }
}

private struct WheelLayout {
    var hub: CGPoint
    var unit: CGFloat

    init(_ rect: CGRect) {
        unit = min(rect.width, rect.height) / 280
        hub = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.44)
    }

    func point(r: CGFloat, clock: CGFloat) -> CGPoint {
        let rad = clock * .pi / 180
        return CGPoint(x: hub.x + sin(rad) * r * unit, y: hub.y - cos(rad) * r * unit)
    }

    func offset(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
        CGPoint(x: hub.x + dx * unit, y: hub.y + dy * unit)
    }

    func addArc(_ path: inout Path, r: CGFloat, from start: CGFloat, to end: CGFloat) {
        path.addArc(
            center: hub,
            radius: r * unit,
            startAngle: .degrees(start - 90),
            endAngle: .degrees(end - 90),
            clockwise: false
        )
    }

    func addClockArc(_ path: inout Path, r: CGFloat, from start: CGFloat, to end: CGFloat) {
        let spans: [(CGFloat, CGFloat)] = end < start ? [(start, 360), (0, end)] : [(start, end)]
        for span in spans {
            path.move(to: point(r: r, clock: span.0))
            addArc(&path, r: r, from: span.0, to: span.1)
        }
    }
}

private struct OuterArcs: Shape {
    func path(in rect: CGRect) -> Path {
        let layout = WheelLayout(rect)
        var path = Path()
        for span in [(52.0, 250.0), (282.0, 24.0)] {
            layout.addClockArc(&path, r: 118, from: span.0, to: span.1)
        }
        return path
    }
}

private struct TopArcs: Shape {
    func path(in rect: CGRect) -> Path {
        let layout = WheelLayout(rect)
        var path = Path()
        layout.addClockArc(&path, r: 100, from: 300, to: 50)
        layout.addClockArc(&path, r: 84, from: 314, to: 40)
        return path
    }
}

private struct Spokes: Shape {
    func path(in rect: CGRect) -> Path {
        let layout = WheelLayout(rect)
        var path = Path()
        for clock in [0.0, 45, 90, 135, 225, 270, 315] {
            path.move(to: layout.point(r: 20, clock: clock))
            path.addLine(to: layout.point(r: 58, clock: clock))
        }
        return path
    }
}

private struct HubAndGondolas: Shape {
    func path(in rect: CGRect) -> Path {
        let layout = WheelLayout(rect)
        var path = Path()
        addCircle(&path, layout: layout, r: 16, at: 0, clock: 0, centered: true)
        addCircle(&path, layout: layout, r: 6.5, at: 0, clock: 0, centered: true)
        for clock in [0.0, 45, 90, 135, 225, 270, 315] {
            addCircle(&path, layout: layout, r: 9, at: 71, clock: clock, centered: false)
        }
        return path
    }

    private func addCircle(_ path: inout Path, layout: WheelLayout, r: CGFloat, at orbit: CGFloat, clock: CGFloat, centered: Bool) {
        let center = centered ? layout.hub : layout.point(r: orbit, clock: clock)
        let radius = r * layout.unit
        path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}

private struct Support: Shape {
    func path(in rect: CGRect) -> Path {
        let layout = WheelLayout(rect)
        var path = Path()
        path.move(to: layout.offset(-11, 16))
        path.addLine(to: layout.offset(-46, 96))
        path.move(to: layout.offset(11, 16))
        path.addLine(to: layout.offset(46, 96))
        path.move(to: layout.offset(-68, 96))
        path.addLine(to: layout.offset(-26, 96))
        path.move(to: layout.offset(26, 96))
        path.addLine(to: layout.offset(68, 96))
        return path
    }
}

private struct Orbit: Shape {
    func path(in rect: CGRect) -> Path {
        let layout = WheelLayout(rect)
        var path = Path()
        let ball = layout.point(r: 122, clock: 36)
        let ballRadius = 14 * layout.unit
        path.addEllipse(in: CGRect(x: ball.x - ballRadius, y: ball.y - ballRadius, width: ballRadius * 2, height: ballRadius * 2))
        let dot = layout.point(r: 104, clock: 48)
        let dotRadius = 4.5 * layout.unit
        path.addEllipse(in: CGRect(x: dot.x - dotRadius, y: dot.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
        return path
    }
}
