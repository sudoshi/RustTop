import AppKit
import SwiftUI

struct GlassPanel<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme

    var cornerRadius: CGFloat = 22
    var tintColor: NSColor?
    @ViewBuilder var content: Content

    var body: some View {
        NativeGlassPanel(
            cornerRadius: cornerRadius,
            tintColor: tintColor,
            content: content
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: colorSchemeContrast == .increased ? 1.1 : 0.6)
                .blendMode(colorScheme == .dark && colorSchemeContrast != .increased ? .plusLighter : .normal)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: shadowColor, radius: colorSchemeContrast == .increased ? 10 : 20, x: 0, y: colorSchemeContrast == .increased ? 6 : 12)
    }

    private var borderColor: Color {
        if colorSchemeContrast == .increased {
            return Color.primary.opacity(0.42)
        }

        return colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12)
    }

    private var shadowColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.16 : 0.09)
    }
}

private struct NativeGlassPanel<Content: View>: NSViewRepresentable {
    var cornerRadius: CGFloat
    var tintColor: NSColor?
    var content: Content

    func makeNSView(context: Context) -> NSGlassEffectView {
        let glassView = NSGlassEffectView()
        glassView.style = .regular
        glassView.cornerRadius = cornerRadius
        glassView.tintColor = tintColor

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        hostingView.setContentHuggingPriority(.defaultLow, for: .vertical)

        glassView.contentView = hostingView

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: glassView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: glassView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: glassView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: glassView.bottomAnchor)
        ])

        return glassView
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {
        nsView.cornerRadius = cornerRadius
        nsView.tintColor = tintColor

        if let hostingView = nsView.contentView as? NSHostingView<Content> {
            hostingView.rootView = content
        } else {
            let hostingView = NSHostingView(rootView: content)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            nsView.contentView = hostingView
        }
    }
}

struct TahoeBackdrop: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: backdropColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { context, size in
                var path = Path()
                let spacing: CGFloat = 34
                var x: CGFloat = -size.height

                while x < size.width + size.height {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                    x += spacing
                }

                context.stroke(path, with: .color(stripeColor), lineWidth: colorSchemeContrast == .increased ? 1.0 : 0.8)
            }
            .blendMode(colorScheme == .dark ? .plusLighter : .normal)
        }
        .ignoresSafeArea()
    }

    private var backdropColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(nsColor: .windowBackgroundColor),
                Color(red: 0.08, green: 0.10, blue: 0.13),
                Color(red: 0.12, green: 0.10, blue: 0.16)
            ]
        }

        return [
            Color(nsColor: .windowBackgroundColor),
            Color(red: 0.91, green: 0.95, blue: 1.00),
            Color(red: 0.96, green: 0.93, blue: 1.00)
        ]
    }

    private var stripeColor: Color {
        let base: Color = colorScheme == .dark ? .white : .black
        return base.opacity(colorSchemeContrast == .increased ? 0.10 : 0.045)
    }
}

extension Color {
    static let tahoeBlue = Color(red: 0.30, green: 0.62, blue: 1.00)
    static let tahoeMint = Color(red: 0.21, green: 0.86, blue: 0.62)
    static let tahoeRose = Color(red: 1.00, green: 0.36, blue: 0.47)
    static let tahoeAmber = Color(red: 1.00, green: 0.72, blue: 0.27)
    static let tahoeViolet = Color(red: 0.62, green: 0.48, blue: 1.00)
}
