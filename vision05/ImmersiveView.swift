import SwiftUI
import RealityKit
import RealityKitContent

struct ImmersiveView: View {
  var body: some View {
    RealityView { content in
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
    }
    .onAppear {
      OrbitSystem.registerSystem()
    }
  }
}

// Custom system to handle orbiting motion
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
      
      entity.position = SIMD3(x, 1.5, z)
      entity.setOrientation(simd_quatf(angle: -angle, axis: SIMD3<Float>(0, 1, 0)), relativeTo: nil)
    }
  }
}

// Animation component to store orbiting parameters
struct OrbitAnimation: Component {
  var period: Float
  var radius: Float
}

#Preview(immersionStyle: .mixed) {
  ImmersiveView()
    .environment(AppModel())
}
