import SwiftUI

@main
struct DashboardApp: App {
    @State private var viewModel = DashboardViewModel()

    var body: some Scene {
        WindowGroup {
            DashboardGridView(viewModel: viewModel)
                .frame(minWidth: 400, minHeight: 300)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 800, height: 600)
    }
}
