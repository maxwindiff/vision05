import ARKit
import RealityKit
import UIKit

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

  required init(jointColor: UIColor, connectionColor: UIColor) {
    super.init()

    for joint in HandSkeleton.JointName.allCases {
      let jointEntity = ModelEntity(
        mesh: MeshResource.generateBox(size: 0.01),
        materials: [SimpleMaterial(color: jointColor, isMetallic: false)]
      )
      jointEntities[joint] = jointEntity
      addChild(jointEntity)
    }
    for _ in connectionPairs {
      let connection = ModelEntity(
        mesh: MeshResource.generateCylinder(height: 1, radius: 0.002),
        materials: [SimpleMaterial(color: connectionColor, isMetallic: false)]
      )
      connectionEntities.append(connection)
      addChild(connection)
    }
  }

  @MainActor @preconcurrency required init() {
    fatalError("init() has not been implemented")
  }

  func updateHandSkeleton(with handAnchor: HandAnchor) {
    for (jointName, entity) in jointEntities {
      if let joint = handAnchor.handSkeleton?.joint(jointName), joint.isTracked {
        entity.transform = Transform(matrix: handAnchor.originFromAnchorTransform *
                                     joint.anchorFromJointTransform)
      }
    }

    for (index, (start, end)) in connectionPairs.enumerated() {
      guard let startJoint = handAnchor.handSkeleton?.joint(start),
            let endJoint = handAnchor.handSkeleton?.joint(end) else {
        continue
      }

      let connectionEntity = connectionEntities[index]
      let startPosition = Transform(matrix: handAnchor.originFromAnchorTransform *
                                    startJoint.anchorFromJointTransform).translation
      let endPosition = Transform(matrix: handAnchor.originFromAnchorTransform *
                                  endJoint.anchorFromJointTransform).translation
      connectionEntity.position = (startPosition + endPosition) / 2

      // Rotate cylinder to match the skeleton orientation and length
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
