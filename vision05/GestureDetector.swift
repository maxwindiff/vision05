import Accelerate
import ARKit
import RealityFoundation

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
    straightness: Float
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

    // Bias the normal towards where the user is facing
    normal = 0.6 * normal + 0.4 * deviceTransform.rotation.act([0, 0, -1])

    // Detect finger angle
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

    return (centroid, normal, maxAngle, avgStraightness)
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

