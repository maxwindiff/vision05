import SwiftUI

@main
struct vision05App: App {

  @State private var appModel = AppModel()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .padding()
        .environment(appModel)
    }
    .defaultSize(width: 600, height: 400)

    ImmersiveSpace(id: appModel.immersiveSpaceID) {
      ImmersiveView()
        .environment(appModel)
        .onAppear {
          appModel.immersiveSpaceState = .open
        }
        .onDisappear {
          appModel.immersiveSpaceState = .closed
        }
    }
    .immersionStyle(selection: .constant(.mixed), in: .mixed)
  }
}
