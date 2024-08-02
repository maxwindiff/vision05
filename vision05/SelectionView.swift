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
  var level: Float
  var selected: Bool
  @State var effectiveSelected: Bool = false

  var body: some View {
    GeometryReader { (geometry: GeometryProxy) in
      let size = min(geometry.size.width, geometry.size.height)
      ZStack {
        ForEach(0..<4) { (index:Int) in
          let selected = effectiveSelected
          let arcSize: Double = selected ? 90.0 : Double(35.0 + level * 35.0)
          let opacity: Float = selected ? Float(1) : level
          let stroke: CGFloat = selected ? 15.0 : 10.0
          let color: Color = selected ? .red : .white
          let size: CGFloat = selected ? size * 0.95 : size

          let startAngle = Double(index) * 90 + 45 - arcSize / 2
          Arc(startAngle: .degrees(startAngle), arcAngle: .degrees(arcSize))
            .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            .shadow(color: color, radius: 5)
            .opacity(Double(opacity))
            .frame(width: size, height: size)
        }
      }
      .position(x: geometry.frame(in: .local).midX,
                y: geometry.frame(in: .local).midY)
    }
    .padding(20)
    .onChange(of: selected) { old, new in
      withAnimation {
        effectiveSelected = new
      }
    }
  }
}

#Preview {
  @Previewable @State var level: Float = 0.5
  @Previewable @State var selected = false

  VStack {
    SelectionView(level: level, selected: selected)
      .border(Color.white, width: 1)
    HStack {
      Text("Level")
      Slider(value: $level, in: 0...1)
    }
    Toggle(isOn: $selected) {
      Text("Selected")
    }
  }
  .frame(width: 400, height: 600)
}
