import QtQuick
import "Singletons"

/**
 * Scrolling column for long option lists in the stepped popovers: grows with
 * its items up to `maxHeight` (scaled), then scrolls, with a fade at the
 * bottom while there is more below. ensureVisible(item) scrolls just enough
 * to show one of its items.
 */
Flickable {
    id: pl

    property real s: 1
    property real maxHeight: 250
    default property alias items: plCol.data
    property alias spacing: plCol.spacing

    width: parent ? parent.width : 0
    implicitHeight: Math.min(plCol.implicitHeight, maxHeight * s)
    height: implicitHeight
    contentHeight: plCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    function ensureVisible(item) {
        var y = item.mapToItem(plCol, 0, 0).y;
        if (y < contentY)
            contentY = y;
        else if (y + item.height > contentY + height)
            contentY = y + item.height - height;
    }

    Column {
        id: plCol
        parent: pl.contentItem
        width: pl.width
        spacing: 6 * pl.s
    }

    Rectangle {
        parent: pl
        z: 2
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 28 * pl.s
        visible: pl.contentY + pl.height < pl.contentHeight - 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.alpha(Theme.cardBot, 0) }
            GradientStop { position: 1.0; color: Theme.cardBot }
        }
    }
}
