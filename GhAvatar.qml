import QtQuick
import Quickshell.Widgets
import "Singletons"

/**
 * Round GitHub avatar; `src` is the avatar URL, sized to 64px on fetch.
 */
ClippingRectangle {
    id: av

    property real s: 1
    property string src: ""
    property real size: 20
    width: size * av.s
    height: width
    radius: width / 2
    color: Theme.tileBg
    // ClippingRectangle reparents children into an inner item, so refer
    // to the avatar by id rather than through `parent`.
    Image {
        anchors.fill: parent
        source: av.src ? av.src + (av.src.indexOf("?") >= 0 ? "&" : "?") + "s=64" : ""
        sourceSize.width: 64
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
    }
}
