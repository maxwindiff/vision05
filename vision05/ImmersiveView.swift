import Accelerate
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
    placard.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
    placard.position.y = -0.04
    addChild(model)
    addChild(placard)
  }

  func displayPosition() {
    // TODO: use TextComponent?
    placard.model?.materials = [renderToMaterial(text: position.shortDesc)]
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

class GestureDetector {
  private let palmJoints: [HandSkeleton.JointName] = [
    .wrist,
    .thumbKnuckle, .thumbIntermediateBase,
    .indexFingerMetacarpal, .indexFingerKnuckle, .indexFingerIntermediateBase,
    .middleFingerMetacarpal, .middleFingerKnuckle, .middleFingerIntermediateBase,
    .ringFingerMetacarpal, .ringFingerKnuckle, .ringFingerIntermediateBase,
    .littleFingerMetacarpal, .littleFingerKnuckle, .littleFingerIntermediateBase,
  ]
  private let fingers: [[(HandSkeleton.JointName, HandSkeleton.JointName)]] = [
    [
      (.wrist, .thumbKnuckle),
      (.thumbKnuckle, .thumbIntermediateBase),
      (.thumbIntermediateBase, .thumbIntermediateTip),
      (.thumbIntermediateTip, .thumbTip),
    ], [
      (.wrist, .indexFingerMetacarpal),
      (.indexFingerMetacarpal, .indexFingerKnuckle),
      (.indexFingerKnuckle, .indexFingerIntermediateBase),
      (.indexFingerIntermediateBase, .indexFingerIntermediateTip),
      (.indexFingerIntermediateTip, .indexFingerTip),
    ], [
      (.wrist, .middleFingerMetacarpal),
      (.middleFingerMetacarpal, .middleFingerKnuckle),
      (.middleFingerKnuckle, .middleFingerIntermediateBase),
      (.middleFingerIntermediateBase, .middleFingerIntermediateTip),
      (.middleFingerIntermediateTip, .middleFingerTip),
    ], [
      (.wrist, .ringFingerMetacarpal),
      (.ringFingerMetacarpal, .ringFingerKnuckle),
      (.ringFingerKnuckle, .ringFingerIntermediateBase),
      (.ringFingerIntermediateBase, .ringFingerIntermediateTip),
      (.ringFingerIntermediateTip, .ringFingerTip),
    ], [
      (.wrist, .littleFingerMetacarpal),
      (.littleFingerMetacarpal, .littleFingerKnuckle),
      (.littleFingerKnuckle, .littleFingerIntermediateBase),
      (.littleFingerIntermediateBase, .littleFingerIntermediateTip),
      (.littleFingerIntermediateTip, .littleFingerTip),
    ]
  ]

  func isSelecting(_ device: DeviceAnchor, _ hand: HandAnchor) -> (
    centroid: SIMD3<Float>,
    normal: SIMD3<Float>,
    angle: Float,
    straightness: Float,
    debug: String
  ) {
    let deviceTransform = Transform(matrix: device.originFromAnchorTransform)
    let devicePosition = deviceTransform.translation

    // Detect the palm plane, and try to orient the normal to face "outwards".
    var (centroid, normal) = palmPlane(hand)
    let upperDiag = hand.jointPosition(.littleFingerKnuckle) - hand.jointPosition(.indexFingerMetacarpal)
    let lowerDiag = hand.jointPosition(.littleFingerMetacarpal) - hand.jointPosition(.indexFingerKnuckle)
    let palmOrientation = normalize(cross(upperDiag, lowerDiag))
    if dot(palmOrientation, normal) < 0 {
      normal = -normal
    }
    // TODO: maybe bias the normal towards where the device is facing

    // Detect palm angle
    let fingerTips: [HandSkeleton.JointName] = [.thumbTip, .indexFingerTip, .middleFingerTip,
                                                .ringFingerTip, .littleFingerTip];
    let fingerVectors = fingerTips.map { normalize(hand.jointPosition($0) - devicePosition) }
    var maxAngle: Float = 0
    for i in 0..<fingerTips.count {
      for j in i+1..<fingerTips.count {
        maxAngle = max(maxAngle, acos(dot(fingerVectors[i], fingerVectors[j])))
      }
    }

    // Detect finger openness/curl
    var avgStraightness: Float = 0
    for finger in fingers {
      let connections = finger.map { normalize(hand.jointPosition($0.1) - hand.jointPosition($0.0)) }
      var straightness: Float = 1;
      for i in 0..<connections.count - 1 {
        straightness *= dot(connections[i], connections[i+1])
      }
      avgStraightness += straightness
    }
    avgStraightness /= 5

    return (centroid, normal, maxAngle, avgStraightness, "")
  }

  private func palmPlane(_ hand: HandAnchor) -> (centroid: SIMD3<Float>, normal: SIMD3<Float>) {
    var points: [SIMD3<Float>] = []
    for joint in palmJoints {
      points.append(hand.jointPosition(joint))
    }
    let centroid = points.reduce([0, 0, 0]) { $0 + $1 } / Float(points.count)
    let centeredPoints = points.map { $0 - centroid }

    var covMatrix = simd_float3x3(0.0)
    for point in centeredPoints {
      covMatrix.columns.0 += point * point.x
      covMatrix.columns.1 += point * point.y
      covMatrix.columns.2 += point * point.z
    }
    covMatrix.columns.0 /= Float(points.count)
    covMatrix.columns.1 /= Float(points.count)
    covMatrix.columns.2 /= Float(points.count)

    let (_, vectors) = eigen(covMatrix)
    return (centroid, vectors[0])
  }

  func eigen(_ matrix: simd_float3x3) -> (eigenvalues: SIMD3<Float>, eigenvectors: simd_float3x3) {
    var JOBZ = Int8("V".utf8.first!)
    var UPLO = Int8("U".utf8.first!)

    var n = __LAPACK_int(3)
    let a = UnsafeMutablePointer<Float>.allocate(capacity: 3*3)
    for i in 0..<3 {
      for j in 0..<3 {
        a[i*3+j] = matrix[i][j]
      }
    }
    var lda = __LAPACK_int(3)
    let w = UnsafeMutablePointer<Float>.allocate(capacity: 3)
    defer {
      a.deallocate()
      w.deallocate()
    }

    var workspaceDimension = Float()
    var workspaceQuery = __LAPACK_int(-1)
    var info = __LAPACK_int(0)
    ssyev_(&JOBZ, &UPLO, &n, a, &lda, w, &workspaceDimension, &workspaceQuery, &info);
    var lwork = __LAPACK_int(workspaceDimension)

    let work = UnsafeMutablePointer<Float>.allocate(capacity: Int(lwork))
    defer {
      work.deallocate()
    }
    ssyev_(&JOBZ, &UPLO, &n, a, &lda, w, work, &lwork, &info);

    return (
      simd_float3(w[0], w[1], w[2]),
      simd_float3x3(
        simd_float3(a[0], a[1], a[2]),
        simd_float3(a[3], a[4], a[5]),
        simd_float3(a[6], a[7], a[8])
      )
    )
  }
}

struct ImmersiveView: View {
  @Environment(AppModel.self) private var appModel

  let session = ARKitSession()
  let worldTracking = WorldTrackingProvider()
  let handTracking = HandTrackingProvider()
  let headAnchor = AnchorEntity(.head)

  let gestureDetector = GestureDetector()

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

    let deviceTransform = Transform(matrix: device.originFromAnchorTransform)
    var devicePosition = deviceTransform.translation
    devicePosition.y -= 0.1 // TODO: why is the device position so high?

    let (palmCenter, palmDirection, palmAngle, straightness, desc) = gestureDetector.isSelecting(device, hand)
    var hits = 0
    if straightness > 0.6 {
      for unit in units {
        let unitDirection = normalize(unit.position - palmCenter)
        let angle = acos(dot(palmDirection, unitDirection))
        let hit = angle < palmAngle
        if hit {
          hits += 1
          unit.highlight()
        } else {
          unit.unhighlight()
        }
      }

      let coneHeight: Float = 2.0
      let coneRadius = tan(palmAngle) * coneHeight
      debugCone?.look(at: palmCenter + palmDirection, from: palmCenter, relativeTo: nil)
      debugCone?.scale = [coneRadius, coneRadius, coneHeight]
    } else {
      for unit in units {
        unit.unhighlight()
      }

      debugCone?.scale = [0, 0, 0]
    }

    // Debug info
    appModel.log1 = String(format: """
                           Device position: %@
                           Palm center: %@
                           Palm direction: %@
                           Palm angle: %.2f
                           Hits: %d
                           """,
                           devicePosition.shortDesc,
                           palmCenter.shortDesc, palmDirection.shortDesc,
                           palmAngle * 180.0 / .pi, hits)
    if let skeleton = hand.handSkeleton {
      var pos: [String] = []
      for joint in skeleton.allJoints {
        pos.append(hand.jointPosition(joint.name).shortDesc)
      }
      appModel.log2 = desc + "\n" + pos.joined(separator: ",\n")
    }
  }
}

extension SIMD4 {
  var xyz: SIMD3<Scalar> {
    return self[SIMD3(0, 1, 2)]
  }
}

extension SIMD3<Float> {
  var shortDesc: String {
    return String(format: "(% .2f, % .2f, % .2f)", self[0], self[1], self[2])
  }
}

extension simd_float4x4 {
  var translation: SIMD3<Float> {
    return columns.3.xyz
  }
}

extension simd_float3x3 {
  var trace: Float {
    return self[0][0] + self[1][1] + self[2][2]
  }
}

extension HandAnchor {
  func jointPosition(_ joint: HandSkeleton.JointName) -> SIMD3<Float> {
    if let handSkeleton {
      return (originFromAnchorTransform * handSkeleton.joint(joint).anchorFromJointTransform).translation
    } else {
      return [0, 0, 0]
    }
  }
}
#Preview(immersionStyle: .mixed) {
  ImmersiveView()
    .environment(AppModel())
}
