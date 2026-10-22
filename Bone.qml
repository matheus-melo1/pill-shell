import QtQuick
import "Singletons"

/**
 * One skeleton placeholder block: a faint rounded bar with a highlight band
 * sweeping across it. `phase` (0..1) positions the band; skeletons drive every
 * bone from one shared animated phase so the shine moves in step. `w` sizes
 * the bone as a fraction of its parent's width when no width is set.
 */
Rectangle {
    id: bone

    property real phase: 0
    property real w: 1
    property real s: 1

    width: (parent ? parent.width : 0) * w
    height: 12 * s
    radius: Math.min(height / 2, 6 * s)
    color: Qt.alpha(Theme.cream, 0.07)
    clip: true

    Rectangle {
        readonly property real band: Math.max(80 * bone.s, bone.width * 0.35)
        width: band
        height: bone.height
        x: -band + bone.phase * (bone.width + band)
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.alpha(Theme.cream, 0) }
            GradientStop { position: 0.5; color: Qt.alpha(Theme.cream, 0.08) }
            GradientStop { position: 1.0; color: Qt.alpha(Theme.cream, 0) }
        }
    }
}
