import SwiftUI

struct UnexpectedTerminationSectionView: View {
    let diagnostics: AppDiagnostics
    let unexpectedTermination: UnexpectedTerminationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Previous launch may not have ended normally")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(unexpectedTermination.reason)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(diagnostics.logsDirectoryURL.path)
                .font(.caption2)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
            Button("Open diagnostics folder") {
                diagnostics.openLogsDirectory()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(ModernTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(ModernTheme.accent)
                .frame(width: 3)
                .frame(maxHeight: .infinity)
        }
    }
}
