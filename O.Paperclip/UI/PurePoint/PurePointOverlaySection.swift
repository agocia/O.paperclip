import SwiftUI
import MapKit

// Exposed PurePoint overlay UI section. This file contains a public UIState container
// and a reusable section view for a single overlay. The global state management should
// be driven by ContentView currently, but this module provides a stable, testable UI
// component for rendering and interactions.

// PurePointOverlayUIState is defined in a shared module (PurePointOverlaySection) for reuse

struct PurePointOverlaySection: View {
    let overlay: PurePointOverlay
    let isCompactSidebar: Bool
    @Binding var state: PurePointOverlayUIState
    let visiblePoints: [ShuangbeiPurePoint]
    let pointCountByCategory: [String: Int]
    let isImported: Bool

    // Callbacks
    var onToggleEnabled: (Bool) -> Void
    var onToggleFilterExpanded: (Bool) -> Void
    var onToggleCategory: (String) -> Void
    var onSelectAllCategories: () -> Void
    var onClearAllCategories: () -> Void
    var onFocus: () -> Void
    var onRemoveImported: (() -> Void)?

    init(
        overlay: PurePointOverlay,
        isCompactSidebar: Bool,
        state: Binding<PurePointOverlayUIState>,
        visiblePoints: [ShuangbeiPurePoint],
        pointCountByCategory: [String: Int],
        isImported: Bool,
        onToggleEnabled: @escaping (Bool) -> Void,
        onToggleFilterExpanded: @escaping (Bool) -> Void,
        onToggleCategory: @escaping (String) -> Void,
        onSelectAllCategories: @escaping () -> Void,
        onClearAllCategories: @escaping () -> Void,
        onFocus: @escaping () -> Void,
        onRemoveImported: (() -> Void)? = nil
    ) {
        self.overlay = overlay
        self.isCompactSidebar = isCompactSidebar
        self._state = state
        self.visiblePoints = visiblePoints
        self.pointCountByCategory = pointCountByCategory
        self.isImported = isImported
        self.onToggleEnabled = onToggleEnabled
        self.onToggleFilterExpanded = onToggleFilterExpanded
        self.onToggleCategory = onToggleCategory
        self.onSelectAllCategories = onSelectAllCategories
        self.onClearAllCategories = onClearAllCategories
        self.onFocus = onFocus
        self.onRemoveImported = onRemoveImported
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(overlay.title)
                    .font(.headline)
                Spacer()
                if isImported {
                    Menu { Button("Remove", role: .destructive) { onRemoveImported?() } } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                }
            }

            Toggle("Enable \(overlay.title)", isOn: $state.isEnabled)
                .tint(Color(red: 0.85, green: 0.55, blue: 0.35))

            if state.isEnabled {
                HStack {
                    Text("Showing \(visiblePoints.count) / \(overlay.points.count) markers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Focus") { onFocus() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(visiblePoints.isEmpty)
                }

                DisclosureGroup("Category Filters", isExpanded: $state.isFilterExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Button("Select all") { onSelectAllCategories() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            Button("Clear") { onClearAllCategories() }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(state.selectedCategoryIDs.isEmpty)
                        }

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: isCompactSidebar ? 106 : 118), spacing: 8)],
                            spacing: 8
                        ) {
                            ForEach(overlay.categories) { category in
                                let isSelected = state.selectedCategoryIDs.contains(category.id)
                                Button(action: { onToggleCategory(category.id) }) {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(category.color)
                                            .frame(width: 8, height: 8)
                                        Text(category.displayName)
                                            .lineLimit(1)
                                        Spacer(minLength: 4)
                                        Text("\(pointCountByCategory[category.id] ?? 0)")
                                            .foregroundColor(.secondary)
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 7)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(isSelected ? category.color.opacity(0.18) : Color.secondary.opacity(0.08))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(isSelected ? category.color.opacity(0.65) : Color.secondary.opacity(0.12), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(12)
        .background(ModernTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: ModernTheme.shadow, radius: 8, y: 3)
    }
}
