import SwiftUI

struct SavedLocationNamingSheet: View {
    let title: String
    let subtitle: String
    let confirmTitle: String
    let errorText: String?
    @Binding var name: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("名稱", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(onConfirm)

                if let errorText, !errorText.isEmpty {
                    Text(errorText)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                HStack {
                    Spacer()
                    Button("取消", action: onCancel)
                        .buttonStyle(.bordered)
                    Button(confirmTitle, action: onConfirm)
                        .buttonStyle(.borderedProminent)
                        .tint(ModernTheme.accent)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .frame(minWidth: 420)
        }
    }
}
