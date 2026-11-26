import SwiftUI

enum AccentTone {
    case rose, sage, amber, blue

    var ink: Color {
        switch self {
        case .rose: Theme.link
        case .sage: Theme.mean
        case .amber: Theme.amberInk
        case .blue: Theme.blueInk
        }
    }

    var wash: Color {
        switch self {
        case .rose: Theme.blush
        case .sage: Theme.sageWash
        case .amber: Theme.amberWash
        case .blue: Theme.blueWash
        }
    }
}

extension View {
    func card(_ inset: CGFloat = 15, fill: Color = Theme.surface) -> some View {
        cardSurface(fill, inset: inset)
    }

    fileprivate func cardSurface<Fill: ShapeStyle>(_ fill: Fill, inset: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius)
        return padding(inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape.fill(fill).shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 4)
            }
            .overlay { shape.strokeBorder(Theme.boundary.opacity(0.65)).allowsHitTesting(false) }
            .contentShape(shape)
    }
}

struct SectionHeading: View {
    let title: String

    var body: some View {
        Text(title).font(.headline).foregroundStyle(Theme.muted).accessibilityAddTraits(.isHeader)
    }
}

struct HeroCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content.cardSurface(
            LinearGradient(colors: [Theme.heroRose, Theme.heroIvory],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            inset: 16
        )
    }
}

struct IconBadge: View {
    let icon: String
    let tone: AccentTone
    var size: CGFloat = 38
    var circular = false

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.43, weight: .semibold))
            .foregroundStyle(tone.ink)
            .frame(width: size, height: size)
            .background(tone.wash, in: RoundedRectangle(cornerRadius: circular ? size / 2 : 11))
    }
}

struct IconTile: View {
    let title: String
    let id: String
    let icon: String
    let tone: AccentTone
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                IconBadge(icon: icon, tone: tone, size: 32, circular: true)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 38)
            .card(9)
        }
        .buttonStyle(DesignButtonStyle())
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }
}

struct IconRow<Content: View>: View {
    let icon: String
    let tone: AccentTone
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 11) {
            IconBadge(icon: icon, tone: tone).accessibilityHidden(true)
            content
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}

struct IconRowButton: View {
    let title: String
    let id: String
    let icon: String
    let tone: AccentTone
    var accessory: String? = "chevron.right"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconRow(icon: icon, tone: tone) {
                Text(L.t(title)).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                if let accessory {
                    Image(systemName: accessory)
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted).accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(DesignButtonStyle())
        .accessibilityLabel(L.t(title))
        .accessibilityIdentifier(id)
    }
}

struct StatusPill: View {
    let title: String
    let tone: AccentTone

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tone.ink)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(tone.wash, in: Capsule())
    }
}

struct EmptyIllustration: View {
    let icon: String
    var tone: AccentTone = .rose
    var size: CGFloat = 86

    var body: some View {
        ZStack {
            Circle().fill(tone.wash).frame(width: size * 0.74, height: size * 0.74)
            Image(systemName: "calendar")
                .font(.system(size: size * 0.29, weight: .medium))
                .foregroundStyle(Theme.mean)
                .rotationEffect(.degrees(-14))
                .offset(x: -size * 0.29, y: -size * 0.12)
            Image(systemName: icon)
                .font(.system(size: size * 0.40, weight: .semibold))
                .foregroundStyle(tone.ink)
                .rotationEffect(.degrees(8))
                .offset(x: size * 0.04, y: size * 0.04)
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.19, weight: .semibold))
                .foregroundStyle(Theme.amberInk)
                .offset(x: size * 0.34, y: -size * 0.16)
        }
        .frame(width: size, height: size * 0.79)
        .accessibilityHidden(true)
    }
}

struct CycleProgress: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(Theme.rose.opacity(0.20))
                .overlay(alignment: .leading) {
                    Capsule().fill(Theme.rose).frame(width: proxy.size.width * CGFloat(fraction))
                }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

struct PrimaryButton: View {
    let title: String
    let id: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(.white)
                .background(Theme.primary, in: RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
        }
        .buttonStyle(DesignButtonStyle())
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }
}

struct ActionButton: View {
    let title: String
    let id: String
    let kind: Kind
    let icon: String?
    let action: () -> Void

    enum Kind { case normal, primary, period }

    init(_ title: String, id: String, kind: Kind = .normal, icon: String? = nil, action: @escaping () -> Void) {
        self.title = L.t(title)
        self.id = id
        self.kind = kind
        self.icon = icon
        self.action = action
    }

    var body: some View {
        if kind == .primary {
            PrimaryButton(title: title, id: id, icon: icon ?? "checkmark", action: action)
        } else {
            Button(action: action) {
                Group {
                    if let icon { Label(title, systemImage: icon) } else { Text(title) }
                }
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(Theme.link)
                .background(kind == .period ? Theme.heroRose : Theme.blush,
                            in: RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
            }
            .buttonStyle(DesignButtonStyle())
            .accessibilityLabel(title)
            .accessibilityIdentifier(id)
        }
    }
}

struct DesignButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(isEnabled ? (configuration.isPressed ? 0.76 : 1) : 0.55)
    }
}
