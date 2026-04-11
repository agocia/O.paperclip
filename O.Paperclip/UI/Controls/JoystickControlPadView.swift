import SwiftUI

struct JoystickControlPadView: View {
    let activeDirections: Set<JoystickDirection>
    let onDirectionPress: (JoystickDirection, Bool) -> Void

    var body: some View {
        VStack(spacing: 8) {
            JoystickPadButton(
                direction: .up,
                symbolName: "arrow.up",
                isActive: activeDirections.contains(.up),
                onDirectionPress: onDirectionPress
            )

            HStack(spacing: 8) {
                JoystickPadButton(
                    direction: .left,
                    symbolName: "arrow.left",
                    isActive: activeDirections.contains(.left),
                    onDirectionPress: onDirectionPress
                )
                JoystickPadButton(
                    direction: .down,
                    symbolName: "arrow.down",
                    isActive: activeDirections.contains(.down),
                    onDirectionPress: onDirectionPress
                )
                JoystickPadButton(
                    direction: .right,
                    symbolName: "arrow.right",
                    isActive: activeDirections.contains(.right),
                    onDirectionPress: onDirectionPress
                )
            }

            Text("WASD / 方向鍵")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)
    }
}

private struct JoystickPadButton: View {
    let direction: JoystickDirection
    let symbolName: String
    let isActive: Bool
    let onDirectionPress: (JoystickDirection, Bool) -> Void

    @State private var isPressed = false

    var body: some View {
        Image(systemName: symbolName)
            .font(.headline.weight(.bold))
            .foregroundColor(isActive ? .white : ModernTheme.label)
            .frame(width: 42, height: 42)
            .background(isActive ? ModernTheme.accent : ModernTheme.panelRaised)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(isActive ? 0.08 : 0.12), lineWidth: 1)
            )
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed else { return }
                        isPressed = true
                        onDirectionPress(direction, true)
                    }
                    .onEnded { _ in
                        releaseIfNeeded()
                    }
            )
            .onDisappear {
                releaseIfNeeded()
            }
    }

    private func releaseIfNeeded() {
        guard isPressed else { return }
        isPressed = false
        onDirectionPress(direction, false)
    }
}
