import ARKit
import SwiftUI
import RealityKit
import RealityKitContent

class UnitEntity: RealityKit.Entity {
  var model: ModelEntity!, placard: ModelEntity!

  required init() {
    super.init()

    model = ModelEntity(
      mesh: .generateBox(size: 0.02),
      materials: [SimpleMaterial(color: .white, isMetallic: false)]
    )
    placard = ModelEntity(
      mesh: .generatePlane(width: 0.15, height: 0.02),
      materials: [SimpleMaterial(color: .white, isMetallic: false)]
    )
    placard.position.y = -0.04
    addChild(model)
    addChild(placard)
  }

  func setPosition(_ position: SIMD3<Float>) {
    setPosition(position, relativeTo: nil)
    placard.model?.materials = [renderToMaterial(text: String(format: "(%.2f, %.2f, %.2f)",
                                                              position.x, position.y, position.z))]
  }

  func renderToMaterial(text: String) -> SimpleMaterial {
    let view = Text(text)
      .font(.system(size: 18))
      .foregroundColor(.black)
      .frame(width: 150, height: 20)
      .background(Color.white)

    let renderer = ImageRenderer(content: view)
    let texture = try! TextureResource(image: renderer.cgImage!, options: .init(semantic: .color))
    var material = SimpleMaterial()
    material.color = .init(texture: .init(texture))
    return material
  }

  func highlight() {
    model.model?.materials = [SimpleMaterial(color: .yellow, isMetallic: false)]
  }

  func unhighlight() {
    model.model?.materials = [SimpleMaterial(color: .white, isMetallic: false)]
  }
}

struct ImmersiveView: View {
  @Environment(AppModel.self) private var appModel

  let session = ARKitSession()
  let worldTracking = WorldTrackingProvider()
  let handTracking = HandTrackingProvider()
  let headAnchor = AnchorEntity(.head)

  @State var leftHand: HandSkeletonView!
  @State var rightHand: HandSkeletonView!
  @State var units: [UnitEntity] = []

  var body: some View {
    RealityView { content in
      leftHand = HandSkeletonView(jointColor: .red, connectionColor: .red.withAlphaComponent(0.5))
      rightHand = HandSkeletonView(jointColor: .blue, connectionColor: .blue.withAlphaComponent(0.5))
      content.add(leftHand)
      content.add(rightHand)

      units = createUnits()
      for unit in units {
        content.add(unit)
      }
    }
    .task {
      do {
        try await session.run([worldTracking, handTracking])
      } catch {
        print("ARKitSession error:", error)
      }
    }
    .task {
      for await update in handTracking.anchorUpdates {
        if update.event == .updated {
          updateHandSkeleton(with: update.anchor)

          guard let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else { continue }
          updateSelectedSpheres(device: deviceAnchor, hand: update.anchor)
        }
      }
    }
  }

  func updateHandSkeleton(with anchor: HandAnchor) {
    if anchor.chirality == .left {
      leftHand?.updateHandSkeleton(with: anchor)
    } else {
      rightHand?.updateHandSkeleton(with: anchor)
    }
  }

  func createUnits() -> [UnitEntity] {
    let height: Float
    if let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {
      height = deviceAnchor.originFromAnchorTransform.transpose.columns.3.y
      print("Device anchor height: \(height)m")
    } else {
      height = 1.2
      print("Failed to get device anchor, default to 1.2m")
    }

    var units: [UnitEntity] = []
    for x in stride(from: -1.0, to: 1.0, by: 2.0/30) {
      for y in stride(from: -1.0, to: 1.0, by: 2.0/20) {
        let dist = 2.0
        let xAngle = 90.0 * .pi / 180 * x
        let yAngle = 50.0 * .pi / 180 * y
        let unit = UnitEntity()
        unit.setPosition(SIMD3<Float>(
          Float(dist * sin(xAngle) * cos(yAngle)),
          Float(dist * sin(yAngle)) + height,
          Float(-dist * cos(xAngle) * cos(yAngle))
        ))
        units.append(unit)
      }
    }
    return units
  }

  func updateSelectedSpheres(device: DeviceAnchor, hand: HandAnchor) {
    if hand.chirality == .left { return } // TODO: Ignore left hand for now

    let devicePosition = device.originFromAnchorTransform.columns.3.xyz
    let handPosition = hand.originFromAnchorTransform.columns.3.xyz
    let handDirection = normalize(handPosition - devicePosition)

    var hits = 0
    for unit in units {
      let unitDirection = normalize(unit.position - devicePosition)

      let angle = acos(dot(handDirection, unitDirection))
      if angle < 25.0 * .pi / 180 {  // TODO: use size of hand
        hits += 1
        unit.highlight()
      } else {
        unit.unhighlight()
      }
    }

    appModel.log2 = String(format: """
Device position: (% .3f, % .3f, % .3f)
Hand position: (% .3f, % .3f, % .3f)
Hits: %d
""",
                           devicePosition.x, devicePosition.y, devicePosition.z,
                           handPosition.x, handPosition.y, handPosition.z, hits)
  }
}

extension SIMD4 {
  var xyz: SIMD3<Scalar> {
    return self[SIMD3(0, 1, 2)]
  }
}

#Preview(immersionStyle: .mixed) {
  ImmersiveView()
    .environment(AppModel())
}
