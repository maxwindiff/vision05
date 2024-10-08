import Accelerate
import ARKit
import SwiftUI
import RealityKit
import RealityKitContent

let DEBUG = 0

class UnitEntity: RealityKit.Entity {
  enum State {
    case undefined
    case unselected
    case highlighted
    case selected
  }

  var model: Entity
  var debugView: ModelEntity?
  var state: State = .undefined

  required init(model: Entity) {
    self.model = model

    super.init()
    addChild(model)
    setState(.unselected)

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

  @MainActor @preconcurrency required init() {
    fatalError("init() has not been implemented")
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

  func setState(_ state: State) {
    if state == self.state {
      return
    }
    self.state = state

    guard
      let highlight = model.findEntity(named: "SelectionHighlight") as? ModelEntity,
      var highlightMaterial = highlight.model?.materials.first as? ShaderGraphMaterial
    else { return }

    switch state {
    case .undefined:
      fatalError("Cannot set state to undefined")
    case .unselected:
      highlight.isEnabled = false
    case .highlighted:
      highlight.isEnabled = true
      try? highlightMaterial.setParameter(name: "Color", value: .color(.yellow))
      highlight.model?.materials = [highlightMaterial]
    case .selected:
      highlight.isEnabled = true
      try? highlightMaterial.setParameter(name: "Color", value: .color(.red))
      highlight.model?.materials = [highlightMaterial]
    }
  }
}

struct ImmersiveView: View {
  @Environment(AppModel.self) private var appModel

  let session = ARKitSession()
  let worldTracking = WorldTrackingProvider()
  let handTracking = HandTrackingProvider()
  let headAnchor = AnchorEntity(.head)

  @State var units: [UnitEntity] = []
  @State var leftHand: HandSkeletonView?
  @State var rightHand: HandSkeletonView?
  @State var debugCone: Entity?

  let gestureDetector = GestureDetector()
  @State var deviceTransform: Transform = .identity
  @State var palmCenter: SIMD3<Float> = [0, 0, 0]
  @State var palmDirection: SIMD3<Float> = [0, 0, 0]
  @State var palmRadius: Float = 0
  @State var palmAngle: Float = 0
  @State var straightness: Float = 0

  let selectionTracker = SelectionTracker()
  @State var selectionState: SelectionTracker.State = .notSelecting
  @State var selectionRingVisibility: Float = 0
  @State var selectionCenter: SIMD3<Float> = [0, 0, 0]
  @State var selectionRadius: Float = 0
  @State var selectionAngle: Float = 0
  @State var selectionDirection: SIMD3<Float> = [0, 0, 0]

  var body: some View {
    RealityView { content, attachments in
      if let units = try? await createUnits() {
        for unit in units {
          content.add(unit)
        }
        self.units = units
      }

      if let selectionView = attachments.entity(for: "SelectionView") {
        content.add(selectionView)
      }

      if DEBUG >= 1 {
        debugCone = try? await Entity(named: "Debug", in: realityKitContentBundle)
        if let debugCone {
          content.add(debugCone)
        }
      }
      if DEBUG >= 2 {
        leftHand = HandSkeletonView(jointColor: .red, connectionColor: .red.withAlphaComponent(0.5))
        rightHand = HandSkeletonView(jointColor: .blue, connectionColor: .blue.withAlphaComponent(0.5))
        content.add(leftHand!)
        content.add(rightHand!)
      }
    } update: { content, attachments in
      if selectionState == .notSelecting {
        for unit in units {
          unit.setState(.unselected)
        }
      } else {
        for unit in units {
          let unitDirection = normalize(unit.position - selectionCenter)
          let angle = acos(dot(selectionDirection, unitDirection))
          if angle < selectionAngle {
            if selectionState == .selected {
              unit.setState(.selected)
            } else if selectionState == .selecting {
              unit.setState(.highlighted)
            }
          } else {
            unit.setState(.unselected)
          }
        }
      }

      if let selectionView = attachments.entity(for: "SelectionView") {
        // TODO: better size and placement
        selectionView.look(at: selectionCenter + selectionDirection, from: selectionCenter, relativeTo: nil)
        let scale = selectionAngle * 0.75 / selectionView.attachment.bounds.extents.x
        selectionView.scale = [scale, scale, scale]
      }
    } attachments: {
      Attachment(id: "SelectionView") {
        SelectionView(level: selectionRingVisibility, selected: selectionState == .selected)
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

  func createUnits() async throws -> [UnitEntity] {
    let height: Float = 1.3  // TODO: use device anchor

    var units: [UnitEntity] = []
    for x in stride(from: -1.0, to: 1.0, by: 2.0/25) {
      for y in stride(from: -1.0, to: 1.0, by: 2.0/15) {
        let dist = 2.0
        let xAngle = 70.0 * .pi / 180 * x
        let yAngle = 40.0 * .pi / 180 * y
        let model = try await Entity(named: "BasicUnit", in: realityKitContentBundle)
        let unit = UnitEntity(model: model)
        unit.position = [Float(dist * sin(xAngle) * cos(yAngle)),
                         Float(dist * sin(yAngle)) + height,
                         Float(-dist * cos(xAngle) * cos(yAngle))]
        unit.scale = [0.2, 0.2, 0.2]
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
      // TODO: instead of using palm center, should use some other kind of center of the hand
      (palmCenter, palmDirection, palmRadius, palmAngle, straightness) = gestureDetector.detect(device, hand)
      (selectionState, selectionCenter, selectionRadius, selectionAngle, selectionDirection) = selectionTracker.update(
        timestamp: CACurrentMediaTime(),
        center: palmCenter,
        radius: palmRadius,
        angle: palmAngle,
        direction: palmDirection,
        straightness: straightness
      )

      if selectionState == .selected {
        selectionRingVisibility = 1.0
      } else if selectionState == .selecting {
        let orthogonality = dot(normalize(palmCenter - deviceTransform.translation), palmDirection)
        selectionRingVisibility = orthogonality.scaleAndClamp(0.5, 0.8)
      }

      appModel.log1 = String(format: """
                             Device position: %@
                             Device direction: %@
                             Palm center: %@
                             Palm direction: %@
                             Palm angle: %.2f
                             """,
                             deviceTransform.translation.shortDesc,
                             deviceTransform.rotation.act([0, 0, -1]).shortDesc,
                             palmCenter.shortDesc,
                             palmDirection.shortDesc,
                             palmAngle * 180.0 / .pi)
      appModel.log2 = String(format: """
                             straightness: %.2f
                             selectionState: %@
                             selectionCenter: %@
                             selectionRadius: %.2f
                             selectionAngle: %.2f
                             selectionRingVisibility: %.2f
                             """,
                             straightness,
                             selectionState.description,
                             selectionCenter.shortDesc,
                             selectionRadius,
                             selectionAngle,
                             selectionRingVisibility)
    }

    if DEBUG >= 1 {
      if hand.chirality == .right {
        let coneHeight: Float = 2.0
        let coneRadius = tan(palmAngle) * coneHeight
        debugCone?.look(at: palmCenter + palmDirection, from: palmCenter, relativeTo: nil)
        debugCone?.scale = [coneRadius, coneRadius, coneHeight]
      }
    }
    if DEBUG >= 2 {
      if hand.chirality == .left {
        leftHand?.updateHandSkeleton(with: hand)
      } else {
        rightHand?.updateHandSkeleton(with: hand)
      }
    }
  }
}

#Preview(immersionStyle: .mixed) {
  ImmersiveView()
    .environment(AppModel())
}
