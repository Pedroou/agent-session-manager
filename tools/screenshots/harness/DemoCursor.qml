import QtQuick

// A drawn pointer, so a scripted click reads as a click.
//
// Nothing in the widget knows this exists; it is painted over the top for the
// recording only. The real cursor cannot be used - grabToImage renders the item,
// not the screen, so the pointer has to be part of the scene.
Item {
    id: cursor

    property color ink: "#101214"
    property color paper: "#ffffff"
    property string caption: ""

    // A real pointer is a good deal narrower than it is tall - about five to
    // eight. The first pass drew one at four to five, which is what made it look
    // stretched next to the widget.
    width: 18
    height: 27
    z: 900

    function click(rightButton) {
        ring.rightButton = rightButton === true
        ripple.restart()
    }

    // Drawn first so the arrow sits on top of its own ripple.
    Rectangle {
        id: ring
        property bool rightButton: false
        x: -width / 2
        y: -height / 2
        width: 8
        height: 8
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: ring.rightButton ? "#f97316" : "#ffffff"
        opacity: 0
    }

    SequentialAnimation {
        id: ripple
        ParallelAnimation {
            NumberAnimation { target: ring; property: "width"; from: 8; to: 40
                              duration: 420; easing.type: Easing.OutCubic }
            NumberAnimation { target: ring; property: "height"; from: 8; to: 40
                              duration: 420; easing.type: Easing.OutCubic }
            SequentialAnimation {
                NumberAnimation { target: ring; property: "opacity"; from: 0; to: 0.95; duration: 60 }
                NumberAnimation { target: ring; property: "opacity"; to: 0
                                  duration: 360; easing.type: Easing.OutCubic }
            }
        }
    }

    Canvas {
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.beginPath()
            ctx.moveTo(1.4, 1.4)
            ctx.lineTo(1.4, 21.3)
            ctx.lineTo(6.2, 16.9)
            ctx.lineTo(9.4, 23.9)
            ctx.lineTo(12.4, 22.5)
            ctx.lineTo(9.3, 15.8)
            ctx.lineTo(15.2, 15.5)
            ctx.closePath()
            ctx.fillStyle = cursor.paper
            ctx.fill()
            ctx.lineWidth = 1.6
            ctx.lineJoin = "round"
            ctx.strokeStyle = cursor.ink
            ctx.stroke()
        }
    }

    // Only ever used to name the one gesture a drawn pointer cannot show by
    // itself. White, not a status colour: a pill in orange read as part of the
    // widget rather than as an annotation over it.
    Rectangle {
        visible: cursor.caption !== ""
        x: 14
        y: 24
        width: label.implicitWidth + 14
        height: label.implicitHeight + 8
        radius: height / 2
        color: cursor.paper

        Text {
            id: label
            anchors.centerIn: parent
            text: cursor.caption
            color: cursor.ink
            font.pixelSize: 11
            font.bold: true
        }
    }
}
