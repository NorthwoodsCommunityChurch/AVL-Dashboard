import SwiftUI
import Shared

/// Popover for selecting an app to assign to a widget slot.
struct AppPickerPopover: View {
    @Binding var slot: WidgetSlot
    let onDismiss: () -> Void

    @StateObject private var appLoader = AppCollectionLoader()
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    private var filteredApps: [DiscoveredApp] {
        if searchText.isEmpty {
            return appLoader.apps
        }
        return appLoader.apps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search apps...", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.primary.opacity(0.05))

            Divider()

            // App grid
            if appLoader.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredApps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(searchText.isEmpty ? "No apps found" : "No matching apps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 56))], spacing: 8) {
                        ForEach(filteredApps) { app in
                            AppGridItem(app: app) {
                                slot.appIdentifier = AppIdentifier(
                                    bundleIdentifier: app.bundleIdentifier,
                                    name: app.name,
                                    iconData: app.iconData
                                )
                                onDismiss()
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(width: 280, height: 320)
        .onAppear {
            appLoader.loadApps()
            // Delay focus to ensure popover is fully presented
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
    }
}

/// A single app item in the picker grid.
private struct AppGridItem: View {
    let app: DiscoveredApp
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 2) {
                if let nsImage = NSImage(data: app.iconData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 28))
                        .frame(width: 40, height: 40)
                }
                Text(app.name)
                    .font(.system(size: 9))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 24)
            }
            .frame(width: 56)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.001)) // Hit area
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
