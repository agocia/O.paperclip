import SwiftUI

struct ImportedOverlayNamingSheet: View {
    let overlays: [PurePointOverlay]
    @Binding var titles: [String: String]
    let onCancel: () -> Void
    let onImport: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("設定 KML 圖層名稱")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("匯入後右側欄位會顯示這裡設定的名稱。")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(overlays) { overlay in
                            VStack(alignment: .leading, spacing: 6) {
                                TextField(
                                    "圖層名稱",
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
                    Button("取消", action: onCancel)
                        .buttonStyle(.bordered)
                    Button("匯入", action: onImport)
                        .buttonStyle(.borderedProminent)
                        .disabled(overlays.isEmpty)
                }
            }
            .padding(20)
            .frame(minWidth: 420)
        }
    }
}
