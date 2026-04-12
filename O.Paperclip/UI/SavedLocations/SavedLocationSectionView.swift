import SwiftUI

struct SavedLocationSectionView: View {
    let preview: CurrentSavableItemPreview
    let items: [SavedLocationItem]
    let sortMode: SavedLocationSortMode
    let onSavePreview: () -> Void
    let onApply: (SavedLocationItem) -> Void
    let onFocus: (SavedLocationItem) -> Void
    let onRename: (SavedLocationItem) -> Void
    let onDelete: (SavedLocationItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            previewCard

            Text("已儲存項目")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(ModernTheme.label)

            if items.isEmpty {
                Text("尚未儲存任何點位或路線")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(sectionModels) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                if let title = section.title {
                                    Text(title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.secondary)
                                }

                                ForEach(section.items) { item in
                                    itemCard(item)
                                }
                            }
                        }
                    }
                }
                .frame(minHeight: 180, maxHeight: 360)
            }
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("目前可儲存內容")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(ModernTheme.label)

            if preview.isAvailable {
                Text(preview.sourceSummaryText)
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(preview.suggestedTitle)
                        .font(.callout.weight(.semibold))
                    Text(preview.summaryText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("會先開啟命名視窗，你可以再修改名稱。")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Button(preview.actionTitle, action: onSavePreview)
                    .buttonStyle(.borderedProminent)
                    .tint(ModernTheme.accent)
                    .controlSize(.small)
            } else {
                Text(preview.summaryText)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(preview.actionTitle, action: onSavePreview)
                    .buttonStyle(.borderedProminent)
                    .tint(ModernTheme.accent)
                    .controlSize(.small)
                    .disabled(true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(ModernTheme.panel.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(ModernTheme.accent.opacity(preview.isAvailable ? 0.35 : 0.14), lineWidth: 1)
        )
    }

    private var sectionModels: [SavedLocationSectionModel] {
        switch sortMode {
        case .createdAt:
            return [SavedLocationSectionModel(title: nil, items: items.sorted { $0.createdAt > $1.createdAt })]
        case .region:
            let groups = Dictionary(grouping: items) { $0.regionGroup }
            return SavedLocationRegionGroup.allCases.compactMap { region in
                guard let grouped = groups[region], !grouped.isEmpty else { return nil }
                return SavedLocationSectionModel(
                    title: region.displayName,
                    items: grouped.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                )
            }
        case .kind:
            let groups = Dictionary(grouping: items) { $0.kind }
            return SavedLocationKind.allCases.compactMap { kind in
                guard let grouped = groups[kind], !grouped.isEmpty else { return nil }
                return SavedLocationSectionModel(
                    title: kind.displayName,
                    items: grouped.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                )
            }
        }
    }

    @ViewBuilder
    private func itemCard(_ item: SavedLocationItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.callout.weight(.semibold))
                    Text("\(item.kind.displayName) · \(item.regionGroup.displayName)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 8)

                Menu {
                    Button("改名") { onRename(item) }
                    Button("刪除", role: .destructive) { onDelete(item) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }

            Text(item.summaryText)
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Button("套用") { onApply(item) }
                    .buttonStyle(.borderedProminent)
                    .tint(ModernTheme.accent)
                    .controlSize(.small)

                Button("定位") { onFocus(item) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button("改名") { onRename(item) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button("刪除") { onDelete(item) }
                    .buttonStyle(.bordered)
                    .tint(ModernTheme.danger)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ModernTheme.inset.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct SavedLocationSectionModel: Identifiable {
    let title: String?
    let items: [SavedLocationItem]

    var id: String {
        title ?? "default"
    }
}
