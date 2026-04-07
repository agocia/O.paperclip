import SwiftUI

struct PurePointControlsSectionView<OverlayContent: View>: View {
    let overlayCount: Int
    let importError: String?
    let renderNotice: String?
    let hasVisiblePoints: Bool
    let onImport: () -> Void
    let onFocusAll: () -> Void
    let overlaysContent: () -> OverlayContent

    init(
        overlayCount: Int,
        importError: String?,
        renderNotice: String?,
        hasVisiblePoints: Bool,
        onImport: @escaping () -> Void,
        onFocusAll: @escaping () -> Void,
        @ViewBuilder overlaysContent: @escaping () -> OverlayContent
    ) {
        self.overlayCount = overlayCount
        self.importError = importError
        self.renderNotice = renderNotice
        self.hasVisiblePoints = hasVisiblePoints
        self.onImport = onImport
        self.onFocusAll = onFocusAll
        self.overlaysContent = overlaysContent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PurePoint Layers").font(.subheadline).fontWeight(.semibold).foregroundColor(ModernTheme.label)
                Spacer()
                Button("Import KML", action: onImport)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            if let importError {
                Text(importError)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Text("\(overlayCount) PurePoint layers loaded")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Focus all", action: onFocusAll)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!hasVisiblePoints)
            }

            if let renderNotice {
                Text(renderNotice)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            overlaysContent()
        }
    }
}
