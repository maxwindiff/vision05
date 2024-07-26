import ARKit
import SwiftUI
import RealityKit
import RealityKitContent

struct ImmersiveView: View {
  @Environment(AppModel.self) private var appModel

  let session = ARKitSession()
  let worldTracking = WorldTrackingProvider()
  let handTracking = HandTrackingProvider()
  let headAnchor = AnchorEntity(.head)

  @State var leftHand: HandSkeletonView!
  @State var rightHand: HandSkeletonView!
  @State var spheres: [ModelEntity] = []

  var body: some View {
    RealityView { content in
      leftHand = HandSkeletonView(jointColor: .red, connectionColor: .red.withAlphaComponent(0.5))
      rightHand = HandSkeletonView(jointColor: .blue, connectionColor: .blue.withAlphaComponent(0.5))
      content.add(leftHand)
      content.add(rightHand)

      spheres = createSpheres()
      for sphere in spheres {
        content.add(sphere)
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
          updateSelectedSpheres(with: update.anchor)
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

  func createSpheres() -> [ModelEntity] {
    var spheres: [ModelEntity] = []
    for x in stride(from: -1.0, to: 1.0, by: 2.0/20) {
      for y in stride(from: -1.0, to: 1.0, by: 2.0/10) {
        let sphere = ModelEntity(
          mesh: .generateSphere(radius: 0.02),
          materials: [SimpleMaterial(color: .white, isMetallic: false)]
        )

        // TODO: why need to negate x/z?
        let dist = 2.0
        let xAngle = 60.0 * .pi / 180 * x
        let yAngle = 30.0 * .pi / 180 * y
        sphere.position = SIMD3<Float>(
          Float(-dist * sin(xAngle) * cos(yAngle)),
          Float(dist * sin(yAngle) + 1.0),
          Float(-dist * cos(xAngle) * cos(yAngle))
        )
        spheres.append(sphere)
      }
    }

    var log: [String] = []
    for sphere in spheres {
      log.append(String(format: "(% .3f, % .3f, % .3f)", sphere.position.x, sphere.position.y, sphere.position.z))
    }
    appModel.log1 = log.joined(separator: " ")
    return spheres
  }

  func updateSelectedSpheres(with anchor: HandAnchor) {
    if anchor.chirality == .left { return } // TODO: Ignore left hand for now

    let handPosition = Transform(matrix: anchor.originFromAnchorTransform).translation
    let handDirection = normalize(handPosition - SIMD3<Float>(0, 1, 0))  // TODO: use device position

    var hits = 0
    for sphere in spheres {
      let sphereOffset = sphere.position - SIMD3<Float>(0, 1, 0)  // TODO: use device position
      let sphereDirection = normalize(sphereOffset)

      let angle = acos(dot(handDirection, sphereDirection))
      if angle < 25.0 * .pi / 180 {  // TODO: use size of hand
        hits += 1
        highlightSphere(sphere)
      } else {
        unhighlightSphere(sphere)
      }
    }

    appModel.log2 = String(format: "Hand position: (% .3f, % .3f, % .3f), hits: %d",
                           handPosition.x, handPosition.y, handPosition.z, hits)
  }

  func highlightSphere(_ sphere: ModelEntity) {
    sphere.model?.materials = [SimpleMaterial(color: .yellow, isMetallic: true)]
  }

  func unhighlightSphere(_ sphere: ModelEntity) {
    sphere.model?.materials = [SimpleMaterial(color: .white, isMetallic: false)]
  }
}

#Preview(immersionStyle: .mixed) {
  ImmersiveView()
    .environment(AppModel())
}
