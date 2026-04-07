import SwiftUI

struct ImportedOverlayNamingSheet: View {
    let overlays: [PurePointOverlay]
    @Binding var titles: [String: String]
    let onCancel: () -> Void
    let onImport: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Set PurePoint layer names")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("After import, the sidebar will only show the names you set here.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(overlays) { overlay in
                            VStack(alignment: .leading, spacing: 6) {
                                TextField(
                                    "Layer name",
                                    text: Binding(
                                        get: { titles[overlay.id] ?? overlay.title },
                                        set: { titles[overlay.id] = $0 }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)

                                Text(overlay.sourceName)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                .frame(minHeight: 140, maxHeight: 260)

                HStack {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                    Button("Import", action: onImport)
                        .buttonStyle(.borderedProminent)
                        .disabled(overlays.isEmpty)
                }
            }
            .padding(20)
            .frame(minWidth: 420)
        }
    }
}
