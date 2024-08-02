import SwiftUI

@main
struct vision05App: App {
  @Environment(\.openImmersiveSpace) private var openImmersiveSpace

  @State private var appModel = AppModel()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .padding()
        .environment(appModel)
        .task {
          await openImmersiveSpace(id: appModel.immersiveSpaceID)
        }
    }
    .defaultSize(width: 400, height: 800)

    ImmersiveSpace(id: appModel.immersiveSpaceID) {
      ImmersiveView()
        .environment(appModel)
        .onAppear {
          appModel.immersiveSpaceState = .open
        }
        .onDisappear {
          appModel.immersiveSpaceState = .closed
        }
        .persistentSystemOverlays(.hidden)
    }
    .immersionStyle(selection: .constant(.progressive), in: .progressive)
  }
}
