import ARKit

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

extension FloatingPoint {
  func scaleAndClamp(_ lower: Self, _ upper: Self) -> Self {
    return min(max((self - lower) / (upper - lower), 0), 1)
  }
}
