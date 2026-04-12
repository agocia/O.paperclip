import SwiftUI

struct PurePointControlsSectionView<OverlayContent: View>: View {
    let overlayCount: Int
    let importError: String?
    let renderNotice: String?
    let hasVisiblePoints: Bool
    let onImport: () -> Void
    let onDropURLs: ([URL]) -> Bool
    let onFocusAll: () -> Void
    let overlaysContent: () -> OverlayContent
    @State private var isDropTargeted = false

    init(
        overlayCount: Int,
        importError: String?,
        renderNotice: String?,
        hasVisiblePoints: Bool,
        onImport: @escaping () -> Void,
        onDropURLs: @escaping ([URL]) -> Bool,
        onFocusAll: @escaping () -> Void,
        @ViewBuilder overlaysContent: @escaping () -> OverlayContent
    ) {
        self.overlayCount = overlayCount
        self.importError = importError
        self.renderNotice = renderNotice
        self.hasVisiblePoints = hasVisiblePoints
        self.onImport = onImport
        self.onDropURLs = onDropURLs
        self.onFocusAll = onFocusAll
        self.overlaysContent = overlaysContent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("KML 匯入").font(.subheadline).fontWeight(.semibold).foregroundColor(ModernTheme.label)
                Spacer()
                Button("匯入 KML", action: onImport)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Text("可直接拖曳 .kml 檔案到這裡")
                .font(.caption)
                .foregroundColor(.secondary)

            if let importError {
                Text(importError)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Text("目前載入 \(overlayCount) 個 KML 圖層")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("定位全部", action: onFocusAll)
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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isDropTargeted ? ModernTheme.accent.opacity(0.10) : ModernTheme.inset.opacity(0.32))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isDropTargeted ? ModernTheme.accent.opacity(0.9) : Color.black.opacity(0.08),
                    lineWidth: isDropTargeted ? 1.6 : 1
                )
        )
        .dropDestination(for: URL.self, action: { urls, _ in
            onDropURLs(urls)
        }, isTargeted: { isDropTargeted = $0 })
    }
}
