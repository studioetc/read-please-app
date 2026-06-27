import AppKit
import SwiftUI

/// A control region in the Settings window that onboarding can spotlight.
enum SettingsSpotlight: Hashable {
    case voice
    case shortcuts
}

/// Collects the bounds of spotlight targets so the Settings root can cut a hole around the active
/// one. Values are arrays so a multi-row target (e.g. both Shortcut rows) unions into one region.
struct SettingsSpotlightKey: PreferenceKey {
    static let defaultValue: [SettingsSpotlight: [Anchor<CGRect>]] = [:]
    static func reduce(
        value: inout [SettingsSpotlight: [Anchor<CGRect>]],
        nextValue: () -> [SettingsSpotlight: [Anchor<CGRect>]]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $0 + $1 })
    }
}

extension View {
    /// Tag a control as a spotlight target. Pure SwiftUI — stays in the Settings window's own
    /// coordinate space, so no cross-window drawing is needed (Option B). Safe to apply per-row.
    func settingsSpotlightAnchor(_ id: SettingsSpotlight) -> some View {
        anchorPreference(key: SettingsSpotlightKey.self, value: .bounds) { [id: [$0]] }
    }

    /// Apply on the Settings root: when `active` is non-nil, dim the whole form and cut a glowing
    /// hole around that target. Clicks pass through, so the user can still use the controls.
    func settingsSpotlightOverlay(active: SettingsSpotlight?) -> some View {
        overlayPreferenceValue(SettingsSpotlightKey.self) { anchors in
            GeometryReader { proxy in
                if let active, let list = anchors[active], !list.isEmpty {
                    let rects = list.map { proxy[$0] }
                    let union = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
                    SpotlightShade(rect: union)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// Cut a view-shaped hole out of `self` (used to punch the spotlight out of the dim layer).
    fileprivate func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            Rectangle()
                .overlay { mask().blendMode(.destinationOut) }
        }
    }
}

/// The dim-everything + cut-a-hole + glow-ring effect for one target rect.
private struct SpotlightShade: View {
    let rect: CGRect
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Native macOS focus color (dark mode ≈ rgba(26,169,255,0.5)); ~3px ring + soft bloom.
        // Radius/inset tuned to hug the grouped-form row corners rather than balloon past them.
        // Two independent knobs: `inset` controls the margin/size around the control; the
        // RoundedRectangle's `cornerRadius` controls roundness. Tuned to frame the grouped-form
        // card with a small margin while matching its corner radius.
        let focus = Color(nsColor: .keyboardFocusIndicatorColor)
        let hole = rect.insetBy(dx: -8, dy: -6)

        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.42))
                .reverseMask {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .frame(width: hole.width, height: hole.height)
                        .position(x: hole.midX, y: hole.midY)
                }

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(focus, lineWidth: 3)
                .frame(width: hole.width, height: hole.height)
                .position(x: hole.midX, y: hole.midY)
                .shadow(color: focus.opacity(0.55), radius: 9)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: rect)
    }
}
