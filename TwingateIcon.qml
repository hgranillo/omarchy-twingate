import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Ui

Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property string mode: "ok"
  property color ringColor: Color.popups.background

  // Omarchy themes carry no success or warning tokens, so these are fixed
  // rather than picked from Color.
  property color connectedColor: "#3fb950"
  property color disconnectedColor: "#f85149"
  property color problemColor: "#d29922"

  readonly property color modeColor: mode === "off" ? disconnectedColor
                                   : (mode === "warn" ? problemColor : connectedColor)

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Shape {
    id: shield
    anchors.fill: parent
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: root.color
      strokeWidth: 0
      // Drawn on a 24x24 box.
      PathSvg {
        path: "M12 2.2 L20.2 5.4 V11.6 C20.2 16.7 16.7 20.8 12 22.1 C7.3 20.8 3.8 16.7 3.8 11.6 V5.4 Z"
      }
    }

    transform: Scale {
      origin.x: 0
      origin.y: 0
      xScale: shield.width / 24
      yScale: shield.height / 24
    }
  }

  BorderSurface {
    width: Math.max(5, parent.width * 0.36)
    height: width
    radius: width / 2
    color: root.modeColor
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    // The ring separates the dot from the shield behind it. At 5 px a glyph
    // would be unreadable, so colour alone carries the state.
    borderSpec: Border.flat(root.ringColor, 1)
  }
}
