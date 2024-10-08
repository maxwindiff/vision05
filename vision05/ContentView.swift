import SwiftUI
import RealityKit
import RealityKitContent

struct ContentView: View {
  @Environment(AppModel.self) private var appModel

  var body: some View {
    VStack {
      ToggleImmersiveSpaceButton()
      Text(appModel.log1)
        .frame(maxWidth: .infinity, maxHeight: 150)
      HStack {
        Button(action: {
          UIPasteboard.general.string = appModel.log1
        }) {
          Text("Copy Above")
        }
        Button(action: {
          UIPasteboard.general.string = appModel.log2
        }) {
          Text("Copy Below")
        }
      }
      Text(appModel.log2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

#Preview(windowStyle: .automatic) {
  ContentView()
    .environment(AppModel())
}
