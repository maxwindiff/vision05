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

  func displayPosition() {
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

  @State var leftHand: HandSkeletonView?
  @State var rightHand: HandSkeletonView?
  @State var units: [UnitEntity] = []
  @State var debugCone: Entity?

  var body: some View {
    RealityView { content in
      leftHand = HandSkeletonView(jointColor: .red, connectionColor: .red.withAlphaComponent(0.5))
      rightHand = HandSkeletonView(jointColor: .blue, connectionColor: .blue.withAlphaComponent(0.5))
      content.add(leftHand!)
      content.add(rightHand!)

      units = createUnits()
      for unit in units {
        content.add(unit)
      }

      do {
        debugCone = try await Entity(named: "Debug", in: realityKitContentBundle)
        content.add(debugCone!)
      } catch {
        print("Failed to load debugCone", error)
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
          guard let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else { continue }
          updateHand(device: deviceAnchor, hand: update.anchor)
          updateSelectedUnits(device: deviceAnchor, hand: update.anchor)
        }
      }
    }
  }

  func createUnits() -> [UnitEntity] {
    let height: Float
    if let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {
      height = deviceAnchor.originFromAnchorTransform.transpose.columns.3.y
      print("Device anchor height: \(height)m")
    } else {
      height = 1.3
      print("Failed to get device anchor")
    }

    var units: [UnitEntity] = []
    for x in stride(from: -1.0, to: 1.0, by: 2.0/25) {
      for y in stride(from: -1.0, to: 1.0, by: 2.0/15) {
        let dist = 2.0
        let xAngle = 70.0 * .pi / 180 * x
        let yAngle = 40.0 * .pi / 180 * y
        let unit = UnitEntity()
        unit.look(at: [0, height, 0], from: [Float(dist * sin(xAngle) * cos(yAngle)),
                                             Float(dist * sin(yAngle)) + height,
                                             Float(-dist * cos(xAngle) * cos(yAngle))], relativeTo: nil)
        unit.displayPosition()
        units.append(unit)
      }
    }
    return units
  }

  func updateHand(device: DeviceAnchor, hand: HandAnchor) {
    if hand.chirality == .left {
      leftHand?.updateHandSkeleton(with: hand)
    } else {
      rightHand?.updateHandSkeleton(with: hand)
    }
  }

  func updateSelectedUnits(device: DeviceAnchor, hand: HandAnchor) {
    if hand.chirality == .left { return } // TODO: Ignore left hand for now

    var devicePosition = device.originFromAnchorTransform.columns.3.xyz
    devicePosition.y -= 0.15 // TODO: why is the device position so high?
    let handPosition = hand.originFromAnchorTransform.columns.3.xyz
    let handDirection = normalize(handPosition - devicePosition)

    let selectionAngle: Float = 20.0 * .pi / 180  // TODO: use size of hand
    var hits = 0
    var log2: [String] = []
    for unit in units {
      let unitDirection = normalize(unit.position - devicePosition)

      let angle = acos(dot(handDirection, unitDirection))
      let hit = angle < selectionAngle
      if hit {
        hits += 1
        unit.highlight()
        log2.append(String(format: "(% .2f, % .2f, % .2f)",
                           unitDirection.x, unitDirection.y, unitDirection.z))
      } else {
        unit.unhighlight()
      }
    }

    let coneHeight: Float = 2.0
    let coneRadius = tan(selectionAngle) * coneHeight
    debugCone?.look(at: devicePosition + handDirection, from: handPosition, relativeTo: nil)
    debugCone?.scale = [coneRadius, coneRadius, coneHeight]

    appModel.log1 = String(format: """
Device position: (% .2f, % .2f, % .2f)
Hand position: (% .2f, % .2f, % .2f)
Hand direction: (% .2f, % .2f, % .2f) 
Hits: %d
""",
                           devicePosition.x, devicePosition.y, devicePosition.z,
                           handPosition.x, handPosition.y, handPosition.z,
                           handDirection.x, handDirection.y, handDirection.z,
                           hits)
    appModel.log2 = log2.joined(separator: "\n")
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
