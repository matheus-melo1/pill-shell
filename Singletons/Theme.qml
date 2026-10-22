pragma Singleton
import QtQuick
import Quickshell

Singleton {
    // --- Acento bem escuro (quase #000) -- antes era vermilion --------------
    readonly property color verm:     "#2e2e2e"
    readonly property color vermLit:  "#3d3d3d"
    readonly property color vermDeep: "#202020"
    readonly property color cream:    "#cfcfcf"
    readonly property color bright:   "#f0f0f0"
    readonly property color dim:      "#707070"
    readonly property color cardTop:  "#0e0e0e"
    readonly property color cardBot:  "#080808"
    readonly property color border:   "#1c1c1c"
    readonly property color shadow:     Qt.rgba(0, 0, 0, 0.6)
    readonly property color tileBg:   "#0c0c0c"
    readonly property color subtle:   "#9a9a9a"
    readonly property color faint:    "#5a5a5a"
    readonly property color iconDim:  "#b0b0b0"
    readonly property color hair:     Qt.rgba(0.85, 0.85, 0.85, 0.10)
    readonly property color sheen:    Qt.rgba(0.85, 0.85, 0.85, 0.05)
    readonly property color vermDim:   "#1f1f1f"
    readonly property color vermDimDeep: "#161616"
    readonly property color vermBurn:  "#242424"
    readonly property color tickRest:  "#9a9a9a"
    readonly property color threadBg:  Qt.rgba(0.88, 0.88, 0.88, 0.10)
    readonly property color flameCore: "#3a3a3a"
    readonly property color flameGlow: "#2a2a2a"

    /**
     * Flame canvas ramp: literal hex strings (color type won't work), fed
     * directly to Canvas addColorStop/strokeStyle. A color property serializes
     * to #aarrggbb and corrupts the gradient render.
     */
    readonly property string flameInk:   "#333333"
    readonly property string flameEmber: "#161616"
    readonly property string flameBurn:  "#1d1d1d"
    readonly property string flameTip:   "#444444"
    readonly property color todayWarm: "#444444"
    readonly property color ghost:     "#2a2a2a"
    readonly property color frameBg:      Qt.rgba(0.88, 0.88, 0.88, 0.04)
    readonly property color frameBorder:  Qt.rgba(0.88, 0.88, 0.88, 0.08)
    readonly property color creamMenu:     Qt.rgba(0.80, 0.80, 0.80, 0.82)
    readonly property color claude:    "#D97757"
    readonly property color ok:        "#3fb950"
    readonly property color warn:      "#d29922"
    readonly property color danger:    "#f85149"
    readonly property color info:      "#58a6ff"
    readonly property real shadowOpacity: 0.5
    readonly property string font: "Inter"
    readonly property string fontJp: "Zen Kaku Gothic New"

    /**
     * MPRIS trackArtists arrives as a JS array from some players and as a
     * plain string from others (Spotify); calling join on the string throws
     * and kills the whole binding. Handles both, falls back to trackArtist.
     */
    function joinArtists(artists, single) {
        if (artists && typeof artists.join === "function" && artists.length > 0)
            return artists.join(", ");
        if (artists && String(artists).length > 0)
            return String(artists);
        return single ? String(single) : "";
    }
}
