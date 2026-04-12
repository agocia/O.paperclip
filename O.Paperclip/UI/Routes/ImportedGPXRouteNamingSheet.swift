import SwiftUI

struct ImportedGPXRouteNamingSheet: View {
    let routes: [ImportedGPXRoute]
    @Binding var titles: [String: String]
    let onCancel: () -> Void
    let onImport: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("設定固定路線名稱")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("匯入後右側欄位會顯示這裡設定的名稱。")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(routes) { route in
                            VStack(alignment: .leading, spacing: 6) {
                                TextField(
                                    "路線名稱",
                                    text: Binding(
                                        get: { titles[route.id] ?? route.title },
                                        set: { titles[route.id] = $0 }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)

                                Text(route.sourceName)
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
                        .disabled(routes.isEmpty)
                }
            }
            .padding(20)
            .frame(minWidth: 420)
        }
    }
}
