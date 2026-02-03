import SwiftUI
import Shared

struct DashboardGridView: View {
    @Bindable var viewModel: DashboardViewModel
    @State private var showingAddSheet = false
    @State private var showingSettings = false

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 8)
    ]

    var body: some View {
        ScrollView(.vertical) {
            VStack {
                if viewModel.sortedMachines.isEmpty {
                    ContentUnavailableView(
                        "No Machines Found",
                        systemImage: "desktopcomputer.trianglebadge.exclamationmark",
                        description: Text("Machines running the Dashboard Agent will appear here automatically, or add one manually with the + button.")
                    )
                    .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(viewModel.sortedMachines) { machine in
                            FlipCardView(
                                machine: machine,
                                settings: viewModel.settings,
                                needsUpdate: viewModel.machineNeedsUpdate(machine),
                                onUpdate: {
                                    Task { await viewModel.pushUpdate(to: machine) }
                                },
                                onDelete: { viewModel.deleteMachine(id: machine.hardwareUUID) },
                                onSave: { viewModel.saveMachine(machine) }
                            )
                        }
                    }
                    .padding(8)
                }

                Spacer()
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if viewModel.dashboardUpdateAvailable {
                    Button {
                        Task { await viewModel.updateDashboard() }
                    } label: {
                        if viewModel.isDownloadingDashboardUpdate {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Install v\(viewModel.latestVersionString ?? "new")", systemImage: "arrow.down.circle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    .disabled(viewModel.isDownloadingDashboardUpdate)
                    .help("Download and install the latest version")
                } else {
                    Button {
                        Task { await viewModel.forceCheckForUpdates() }
                    } label: {
                        if viewModel.isCheckingForUpdates {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(viewModel.isCheckingForUpdates)
                    .help("Check GitHub for a newer version")
                }
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Machine", systemImage: "plus")
                }
                .help("Add machine by IP address")
            }

            ToolbarItem(placement: .automatic) {
                Picker("Sort", selection: $viewModel.sortOrder) {
                    Label("Name", systemImage: "textformat")
                        .tag(MachineSortOrder.name)
                    Label("Temperature", systemImage: "thermometer.medium")
                        .tag(MachineSortOrder.temperature)
                    Label("Uptime", systemImage: "clock")
                        .tag(MachineSortOrder.uptime)
                }
                .pickerStyle(.segmented)
                .help("Sort machines")
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    showingSettings.toggle()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Dashboard settings")
                .popover(isPresented: $showingSettings) {
                    SettingsPopoverView(settings: $viewModel.settings)
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddMachineSheet { host, port in
                viewModel.addManualEndpoint(host: host, port: port)
            }
        }
    }
}
