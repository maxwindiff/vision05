import ARKit
import SwiftUI
import RealityKit
import RealityKitContent

class HandSkeletonView: RealityKit.Entity {
  private let connectionPairs: [(HandSkeleton.JointName, HandSkeleton.JointName)] = [
    (.wrist, .thumbKnuckle),
    (.thumbKnuckle, .thumbIntermediateBase),
    (.thumbIntermediateBase, .thumbIntermediateTip),
    (.thumbIntermediateTip, .thumbTip),

    (.wrist, .indexFingerMetacarpal),
    (.indexFingerMetacarpal, .indexFingerKnuckle),
    (.indexFingerKnuckle, .indexFingerIntermediateBase),
    (.indexFingerIntermediateBase, .indexFingerIntermediateTip),
    (.indexFingerIntermediateTip, .indexFingerTip),

    (.wrist, .middleFingerMetacarpal),
    (.middleFingerMetacarpal, .middleFingerKnuckle),
    (.middleFingerKnuckle, .middleFingerIntermediateBase),
    (.middleFingerIntermediateBase, .middleFingerIntermediateTip),
    (.middleFingerIntermediateTip, .middleFingerTip),

    (.wrist, .ringFingerMetacarpal),
    (.ringFingerMetacarpal, .ringFingerKnuckle),
    (.ringFingerKnuckle, .ringFingerIntermediateBase),
    (.ringFingerIntermediateBase, .ringFingerIntermediateTip),
    (.ringFingerIntermediateTip, .ringFingerTip),

    (.wrist, .littleFingerMetacarpal),
    (.littleFingerMetacarpal, .littleFingerKnuckle),
    (.littleFingerKnuckle, .littleFingerIntermediateBase),
    (.littleFingerIntermediateBase, .littleFingerIntermediateTip),
    (.littleFingerIntermediateTip, .littleFingerTip),
  ]

  private var jointEntities: [HandSkeleton.JointName: Entity] = [:]
  private var connectionEntities: [Entity] = []

  required init() {
    super.init()

    for joint in HandSkeleton.JointName.allCases {
      let jointEntity = createJointEntity()
      jointEntities[joint] = jointEntity
      addChild(jointEntity)
    }
    createConnections();
  }

  private func createConnections() {
    for _ in connectionPairs {
      let connection = createConnectionEntity()
      connectionEntities.append(connection)
      addChild(connection)
    }
  }

  private func createJointEntity() -> Entity {
    return ModelEntity(
      mesh: MeshResource.generateBox(size: 0.01),
      materials: [SimpleMaterial(color: .red, isMetallic: false)]
    )
  }

  private func createConnectionEntity() -> Entity {
    return ModelEntity(
      mesh: MeshResource.generateCylinder(height: 1, radius: 0.002),
      materials: [SimpleMaterial(color: .blue, isMetallic: false)]
    )
  }

  func updateHandSkeleton(with handAnchor: HandAnchor) {
    // Ignore left hand for now
    if handAnchor.chirality == .left { return }

    for (jointName, entity) in jointEntities {
      if let joint = handAnchor.handSkeleton?.joint(jointName), joint.isTracked {
        entity.transform = Transform(matrix: handAnchor.originFromAnchorTransform *
                                     joint.anchorFromJointTransform)
      }
    }

    updateConnections(with: handAnchor)
  }

  private func updateConnections(with handAnchor: HandAnchor) {
    for (index, (start, end)) in connectionPairs.enumerated() {
      guard let startJoint = handAnchor.handSkeleton?.joint(start),
            let endJoint = handAnchor.handSkeleton?.joint(end) else {
        continue
      }

      let startPosition = Transform(matrix: handAnchor.originFromAnchorTransform *
                                    startJoint.anchorFromJointTransform).translation
      let endPosition = Transform(matrix: handAnchor.originFromAnchorTransform *
                                  endJoint.anchorFromJointTransform).translation
      let connectionEntity = connectionEntities[index]
      connectionEntity.position = (startPosition + endPosition) / 2

      let dir = endPosition - startPosition
      let len = length(dir)
      let normalizedDir = dir / len
      let rotationAxis = cross([0, 1, 0], normalizedDir)
      let dotProduct = dot(normalizedDir, [0, 1, 0])
      if length(rotationAxis) < 1e-6 {
        connectionEntity.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        if dotProduct > 0 {
          connectionEntity.scale = [1, len, 1]
        } else {
          connectionEntity.scale = [1, -len, 1]
        }
      } else {
        let angle = acos(max(-1, min(1, dotProduct)))
        connectionEntity.orientation = simd_quatf(angle: angle, axis: normalize(rotationAxis))
        connectionEntity.scale = [1, len, 1]
      }
    }
  }
}

struct ImmersiveView: View {
  @Environment(AppModel.self) private var appModel

  let session = ARKitSession()
  let worldTracking = WorldTrackingProvider()
  let handTracking = HandTrackingProvider()
  let headAnchor = AnchorEntity(.head)

  @State var handSkeleton: HandSkeletonView?

  var body: some View {
    RealityView { content in
      OrbitSystem.registerSystem()

      var model: Entity
      do {
        model = try await Entity(named: "Immersive", in: realityKitContentBundle)
      } catch {
        print("Error loading model \(error)")
        return
      }
      model.scale = SIMD3(repeating: 0.1)
      model.components[OrbitAnimation.self] = OrbitAnimation(period: 5, radius: 2)
      content.add(model)

      handSkeleton = HandSkeletonView()
      content.add(handSkeleton!)
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
          handSkeleton?.updateHandSkeleton(with: update.anchor)
          appModel.logs = update.description
        }
      }
    }
  }
}

struct OrbitAnimation: Component {
  var period: Float
  var radius: Float
}

class OrbitSystem: System {
  static let query = EntityQuery(where: .has(OrbitAnimation.self))

  private var startTime: TimeInterval?

  required init(scene: RealityKit.Scene) {
    startTime = CACurrentMediaTime()
  }

  func update(context: SceneUpdateContext) {
    for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
      guard let orbitAnimation = entity.components[OrbitAnimation.self] else { continue }

      guard let startTime = startTime else { return }
      let time = Float(CACurrentMediaTime() - startTime)
      let angle = 2 * Float.pi * time / orbitAnimation.period

      let x = orbitAnimation.radius * cos(angle)
      let z = orbitAnimation.radius * sin(angle)

      entity.position = SIMD3(x, 1, z)
      entity.setOrientation(simd_quatf(angle: -angle, axis: SIMD3<Float>(0, 1, 0)), relativeTo: nil)
    }
  }
}

#Preview(immersionStyle: .mixed) {
  ImmersiveView()
    .environment(AppModel())
}
