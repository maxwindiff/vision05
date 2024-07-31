import SwiftUI

struct Arc: Shape {
  var startAngle: Angle
  var arcAngle: Angle

  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                radius: rect.width / 2,
                startAngle: startAngle,
                endAngle: startAngle + arcAngle,
                clockwise: false)
    return path
  }
}

struct SelectionView: View {
  // 0  - t1: fade in
  // t1 - t2: arc to circle
  // t2 - 1: bold, red
  var level: Double
  let threshold1 = 0.2
  let threshold2 = 0.9

  var body: some View {
    GeometryReader { geometry in
      let size = min(geometry.size.width, geometry.size.height)
      ZStack {
        ForEach(0..<4) { index in
          let t1level = min(1, level / threshold1)
          let t2level = max(0, level - threshold2) / (1 - threshold2)

          let arcSize = 35.0 + level * 55.0
          let opacity = t1level
          let stroke = 5 + t2level * 5
          let color = Color.white.mix(with: .red, by: t2level)

          let startAngle = Double(index) * 90 + 45 - arcSize / 2
          Arc(startAngle: .degrees(startAngle), arcAngle: .degrees(arcSize))
            .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            .shadow(color: color, radius: 5)
            .opacity(opacity)
            .frame(width: size, height: size)
        }
      }
    }
  }
}

#Preview {
  @Previewable @State var level = 0.5

  VStack {
    SelectionView(level: level)
    Slider(value: $level, in: 0...1)
  }
  .frame(width: 400, height: 600)
}
