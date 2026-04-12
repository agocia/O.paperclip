import SwiftUI

struct ImportedGPXRouteSectionView: View {
    @Bindable var vm: AppViewModel
    let importError: String?
    let onImport: () -> Void
    let onDropURLs: ([URL]) -> Bool
    let onUse: (ImportedGPXRoute) -> Void
    let onFocus: (ImportedGPXRoute) -> Void
    let onRemove: (ImportedGPXRoute) -> Void
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("固定路線").font(.subheadline).fontWeight(.semibold).foregroundColor(ModernTheme.label)
                Spacer()
                Button("匯入 GPX", action: onImport)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Text("可直接拖曳 .gpx 檔案到這裡")
                .font(.caption)
                .foregroundColor(.secondary)

            if let importError {
                Text(importError)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if vm.importedGPXRoutes.isEmpty {
                Text("尚未匯入固定路線")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(vm.importedGPXRoutes) { route in
                            routeCard(route)
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 260)
            }
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

    @ViewBuilder
    private func routeCard(_ route: ImportedGPXRoute) -> some View {
        let isSelected = vm.selectedImportedGPXRouteID == route.id

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(route.title)
                        .font(.callout.weight(.semibold))
                    Text(route.sourceName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if isSelected {
                    Text("已選取")
                        .font(.caption2)
                        .foregroundColor(ModernTheme.accent)
                }
            }

            HStack(spacing: 8) {
                Text("\(route.points.count) 點")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(String(format: "%.2f km", route.totalDistance / 1000))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                Button("使用") {
                    onUse(route)
                }
                .buttonStyle(.borderedProminent)
                .tint(ModernTheme.accent)
                .controlSize(.small)

                Button("定位") {
                    onFocus(route)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("移除") {
                    onRemove(route)
                }
                .buttonStyle(.bordered)
                .tint(ModernTheme.danger)
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? ModernTheme.panelRaised.opacity(0.9) : ModernTheme.inset.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? ModernTheme.accent.opacity(0.55) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}
