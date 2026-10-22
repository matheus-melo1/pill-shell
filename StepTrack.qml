import QtQuick

/**
 * Sliding page track for the stepped popovers. Children are StepPages, each
 * with a fixed `page` number; `path` lists the pages of the current flow in
 * order and `pos` is where the flow is. Pages lay out by their place in
 * `path`, so a flow only ever slides between neighbours, and pages outside it
 * wait off to the right. The track takes the current page's height and clips.
 */
Item {
    id: track

    property var path: []
    property int pos: 0
    default property alias pages: holder.data

    clip: true
    implicitHeight: {
        var ch = holder.children;
        for (var i = 0; i < ch.length; i++)
            if (ch[i].at === track.pos)
                return ch[i].implicitHeight;
        return 0;
    }
    height: implicitHeight

    Item {
        id: holder
        anchors.fill: parent
    }
}
