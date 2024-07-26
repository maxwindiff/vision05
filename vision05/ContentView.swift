import SwiftUI
import RealityKit
import RealityKitContent

struct ContentView: View {
  @Environment(AppModel.self) private var appModel

  var body: some View {
    VStack {
      ToggleImmersiveSpaceButton()
      TextEditor(text: .constant(appModel.log1))
      TextEditor(text: .constant(appModel.log2))
    }
  }
}

#Preview(windowStyle: .automatic) {
  ContentView()
    .environment(AppModel())
}
