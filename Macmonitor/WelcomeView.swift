import SwiftUI

// MARK: - Welcome window (shown on first launch)

struct WelcomeView: View {
    @State private var step = 0
    @AppStorage("enableMenuBar") var enableMenuBar = true
    @AppStorage("enableWidget")  var enableWidget  = false
    @AppStorage("hasLaunched")   var hasLaunched   = false
    @AppStorage("appTheme") private var appTheme = AppTheme.automatic.rawValue

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()

            VStack(spacing: 0) {
                // Step indicator
                HStack(spacing: 6) {
                    ForEach(0..<3) { i in
                        Capsule()
                            .fill(i == step ? Palette.blue : Color.primary.opacity(0.12))
                            .frame(width: i == step ? 20 : 6, height: 6)
                            .animation(.easeInOut(duration: 0.3), value: step)
                    }
                }
                .padding(.top, 28)

                Spacer()

                // Content
                Group {
                    if step == 0 { StepWelcome() }
                    if step == 1 { StepMode(menuBar: $enableMenuBar, widget: $enableWidget) }
                    if step == 2 { StepPermission() }
                }
                .transition(.asymmetric(
                    insertion:  .move(edge: .trailing).combined(with: .opacity),
                    removal:    .move(edge: .leading).combined(with: .opacity)
                ))

                Spacer()

                // Navigation
                HStack(spacing: 12) {
                    if step > 0 {
                        Button("Back") { withAnimation { step -= 1 } }
                            .buttonStyle(.bordered)
                    }
                    Spacer()
                    Button(step < 2 ? "Continue" : "Get Started") {
                        if step < 2 {
                            withAnimation { step += 1 }
                        } else {
                            hasLaunched = true
                            NSApp.keyWindow?.close()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.blue)
                    .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 28)
            }
        }
        .frame(width: 480, height: 420)
        .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)
    }
}

// MARK: - Step 1: Welcome

private struct StepWelcome: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(
                    LinearGradient(colors: [Palette.blue, Palette.purple],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            VStack(spacing: 8) {
                Text("Welcome to MacMonitor")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
                Text("Real-time CPU, GPU, memory, battery and power\nmonitoring built for Apple Silicon.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            HStack(spacing: 24) {
                Feature(icon: "cpu",              label: "Per-core CPU")
                Feature(icon: "rectangle.3.group",label: "GPU + temps")
                Feature(icon: "battery.75percent",label: "Full battery")
                Feature(icon: "bolt.fill",        label: "Power rails")
            }
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Step 2: Mode

private struct StepMode: View {
    @Binding var menuBar: Bool
    @Binding var widget:  Bool

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text("Choose your setup")
                    .font(.system(size: 20, weight: .bold)).foregroundColor(.primary)
                Text("You can change this anytime in Settings.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }

            VStack(spacing: 12) {
                ModeCard(
                    icon: "menubar.rectangle",
                    title: "Menu Bar",
                    desc: "Live indicator in your menu bar. Click to open the full dashboard.",
                    selected: $menuBar
                )
                ModeCard(
                    icon: "square.grid.2x2",
                    title: "Desktop Widget",
                    desc: "Small or medium widget on your desktop or Notification Centre.",
                    selected: $widget
                )
            }
            .padding(.horizontal, 32)
        }
    }
}

// MARK: - Step 3: Permissions

private struct StepPermission: View {
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text("One-time permission")
                    .font(.system(size: 20, weight: .bold)).foregroundColor(.primary)
                Text("MacMonitor needs sudo once to read GPU, temperature, and power data.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 10) {
                PermRow(icon: "cpu",              color: Palette.blue,
                        title: "CPU & Memory",    desc: "Read directly from macOS — no password needed.")
                PermRow(icon: "rectangle.3.group",color: Palette.purple,
                        title: "GPU & Temps",     desc: "Native SMC + IOReport sensors — no third-party dependencies.")
                PermRow(icon: "bolt.fill",        color: Palette.yellow,
                        title: "Power rails",     desc: "ANE, DRAM, GPU SRAM, total system power.")
                PermRow(icon: "battery.75percent",color: Palette.green,
                        title: "Battery",         desc: "Cycle count, health, charge rate, adapter watts.")
            }
            .padding(.horizontal, 36)

            Text("Your sudo password is cached by macOS — MacMonitor never stores it.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Sub-components

private struct Feature: View {
    let icon: String; let label: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(Palette.blue)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 72)
    }
}

private struct ModeCard: View {
    let icon: String; let title: String; let desc: String
    @Binding var selected: Bool

    var body: some View {
        Button { selected.toggle() } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(selected ? Palette.blue : .secondary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(selected ? .primary : .secondary)
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selected ? Palette.blue : .secondary)
                    .font(.system(size: 18))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? Palette.blue.opacity(0.08) : Color.primary.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(selected ? Palette.blue.opacity(0.4) : Color.primary.opacity(0.08))
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: selected)
    }
}

private struct PermRow: View {
    let icon: String; let color: Color
    let title: String; let desc: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
                .frame(width: 20)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
}
