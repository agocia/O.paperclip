import SwiftUI

struct RightSidebarView<ImportContent: View>: View {
    @Binding var sortMode: SavedLocationSortMode
    let canCreateSavedItem: Bool
    let onToggleVisibility: () -> Void
    let onCreateSavedItem: () -> Void
    let importContent: () -> ImportContent
    let savedContent: () -> SavedLocationSectionView
    let noticeText: String?
    let errorText: String?

    init(
        sortMode: Binding<SavedLocationSortMode>,
        canCreateSavedItem: Bool,
        onToggleVisibility: @escaping () -> Void,
        onCreateSavedItem: @escaping () -> Void,
        noticeText: String?,
        errorText: String?,
        @ViewBuilder importContent: @escaping () -> ImportContent,
        @ViewBuilder savedContent: @escaping () -> SavedLocationSectionView
    ) {
        self._sortMode = sortMode
        self.canCreateSavedItem = canCreateSavedItem
        self.onToggleVisibility = onToggleVisibility
        self.onCreateSavedItem = onCreateSavedItem
        self.noticeText = noticeText
        self.errorText = errorText
        self.importContent = importContent
        self.savedContent = savedContent
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    importSection
                    savedContent()
                    statusSection
                }
                .padding(12)
            }
        }
        .background(ModernTheme.panelRaised)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("匯入與收藏")
                    .font(.headline)
            }

            Spacer()

            Picker("排序", selection: $sortMode) {
                ForEach(SavedLocationSortMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)

            Button(action: onCreateSavedItem) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(ModernTheme.accent)
            .help("儲存目前點位或路線")
            .disabled(!canCreateSavedItem)

            Button(action: onToggleVisibility) {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.bordered)
            .help("隱藏右側欄")
        }
        .padding(12)
        .background(ModernTheme.panel)
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("匯入內容")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(ModernTheme.label)

            importContent()
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if let errorText, !errorText.isEmpty {
            Text(errorText)
                .font(.caption)
                .foregroundColor(.red)
        }

        if let noticeText, !noticeText.isEmpty {
            Text(noticeText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
