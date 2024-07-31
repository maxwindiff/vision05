import Accelerate
import ARKit
import SwiftUI
import RealityKit
import RealityKitContent

let DEBUG = 1

class UnitEntity: RealityKit.Entity {
  var model: ModelEntity!
  var debugView: ModelEntity?

  required init() {
    super.init()

    model = ModelEntity(
      mesh: .generateBox(size: 0.02),
      materials: [SimpleMaterial(color: .white, isMetallic: false)]
    )
    addChild(model)

    if DEBUG >= 2 {
      debugView = ModelEntity(
        mesh: .generatePlane(width: 0.15, height: 0.02),
        materials: [SimpleMaterial(color: .white, isMetallic: false)]
      )
      debugView!.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
      debugView!.position.y = -0.04
      addChild(debugView!)
    }
  }

  func updateInfo() {
    if DEBUG >= 2 {
      debugView?.model?.materials = [renderToMaterial(text: position.shortDesc)]
    }
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

  let gestureDetector = GestureDetector()

  @State var units: [UnitEntity] = []
  @State var leftHand: HandSkeletonView?
  @State var rightHand: HandSkeletonView?
  @State var debugCone: Entity?

  @State var deviceTransform: Transform = .identity
  @State var palmCenter: SIMD3<Float> = [0, 0, 0]
  @State var palmDirection: SIMD3<Float> = [0, 0, 0]
  @State var palmAngle: Float = 0
  @State var straightness: Float = 0

  @State var selectionLevel = 0.5

  var body: some View {
    RealityView { content, attachments in
      units = createUnits()
      for unit in units {
        content.add(unit)
      }

      if let selectionView = attachments.entity(for: "SelectionView") {
        content.add(selectionView)
      }

      if DEBUG >= 1 {
        leftHand = HandSkeletonView(jointColor: .red, connectionColor: .red.withAlphaComponent(0.5))
        rightHand = HandSkeletonView(jointColor: .blue, connectionColor: .blue.withAlphaComponent(0.5))
        content.add(leftHand!)
        content.add(rightHand!)

        debugCone = try? await Entity(named: "Debug", in: realityKitContentBundle)
        if let debugCone {
          content.add(debugCone)
        }
      }
    } update: { content, attachments in
      if straightness > 0.6 {
        for unit in units {
          let unitDirection = normalize(unit.position - palmCenter)
          let angle = acos(dot(palmDirection, unitDirection))
          let hit = angle < palmAngle
          if hit {
            unit.highlight()
          } else {
            unit.unhighlight()
          }
        }
      } else {
        for unit in units {
          unit.unhighlight()
        }
      }

      if let selectionView = attachments.entity(for: "SelectionView") {
        selectionView.look(at: deviceTransform.translation, from: palmCenter, relativeTo: nil)
        let scale = 0.3 / selectionView.attachment.bounds.extents.x
        selectionView.scale = [scale, scale, scale]
      }
    } attachments: {
      Attachment(id: "SelectionView") {
        SelectionView(level: selectionLevel)
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
        }
      }
    }
  }

  func createUnits() -> [UnitEntity] {
    let height: Float = 1.3  // TODO: use device anchor

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
        unit.updateInfo()
        units.append(unit)
      }
    }
    return units
  }

  func updateHand(device: DeviceAnchor, hand: HandAnchor) {
    deviceTransform = Transform(matrix: device.originFromAnchorTransform)

    // TODO: Support both hands for selection
    if hand.chirality == .right {
      (palmCenter, palmDirection, palmAngle, straightness) = gestureDetector.isSelecting(device, hand)
      if straightness > 0.6 {
        selectionLevel = Double((1 - straightness) / 0.4)
      } else {
        selectionLevel = 0
      }
    }

    if DEBUG >= 1 {
      if hand.chirality == .left {
        leftHand?.updateHandSkeleton(with: hand)
      } else {
        rightHand?.updateHandSkeleton(with: hand)

        let coneHeight: Float = 2.0
        let coneRadius = tan(palmAngle) * coneHeight
        debugCone?.look(at: palmCenter + palmDirection, from: palmCenter, relativeTo: nil)
        debugCone?.scale = [coneRadius, coneRadius, coneHeight]

        appModel.log1 = String(format: """
                               Device position: %@
                               Device direction: %@
                               Palm center: %@
                               Palm direction: %@
                               Palm angle: %.2f
                               """,
                               deviceTransform.translation.shortDesc,
                               deviceTransform.rotation.act([0, 0, -1]).shortDesc,
                               palmCenter.shortDesc, palmDirection.shortDesc,
                               palmAngle * 180.0 / .pi)
      }
    }
  }
}

#Preview(immersionStyle: .mixed) {
  ImmersiveView()
    .environment(AppModel())
}
