import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// omashelf: your recent clipboard items as cards down the right edge of the
// screen. Drag a card into any app and its contents land where you drop it:
// text goes into the text field, an image or copied file arrives as a file.
//
//   drag      drop the item into another window
//   click     copy it back onto the clipboard
//   Esc / 󰅖   close the shelf
//
// It reads the history Omarchy's clipboard manager keeps and never writes it.
//
//   omarchy-shell shell toggle iluxav.omashelf '{}'
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property var items: []
  property string status: ""

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  readonly property string historyPath: Quickshell.env("HOME") + "/.local/state/omarchy/clipboard-history.json"
  readonly property int shelfLimit: 40
  // Cards show a few lines; dragging always carries the whole entry.
  readonly property int previewChars: 400

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int shelfWidth: Style.space(320)

  function open(payloadJson) {
    root.opened = true
    historyFile.reload()
  }

  function close() {
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  // ---- history ------------------------------------------------------------

  function load(raw) {
    var parsed = []
    try { parsed = JSON.parse(String(raw || "[]")) } catch (e) { parsed = [] }
    if (!Array.isArray(parsed)) parsed = []

    var next = []
    for (var i = 0; i < parsed.length && next.length < root.shelfLimit; i++) {
      var item = root.shelfItem(parsed[i], i)
      if (item) next.push(item)
    }
    root.items = next
  }

  function shelfItem(entry, historyIndex) {
    if (typeof entry === "string") entry = { type: "text", text: entry }
    if (!entry || typeof entry !== "object") return null

    if (entry.type === "image" && entry.path) {
      var path = String(entry.path)
      return {
        kind: "image",
        historyIndex: historyIndex,
        label: "Image",
        preview: "",
        thumbnail: Util.fileUrl(path),
        path: path,
        mime: String(entry.mime || "image/png"),
        mimeData: { "text/uri-list": root.uriList([path]) }
      }
    }

    var text = String(entry.text || "")
    if (entry.type !== "text" || text.trim().length === 0) return null

    var paths = root.filePaths(text)
    if (paths.length > 0) {
      var names = paths.map(root.fileName)
      return {
        kind: "file",
        historyIndex: historyIndex,
        label: paths.length === 1 ? "File" : paths.length + " files",
        preview: names.join("\n"),
        thumbnail: paths.length === 1 && root.isImagePath(paths[0]) ? Util.fileUrl(paths[0]) : "",
        path: "",
        mime: "",
        mimeData: { "text/uri-list": root.uriList(paths) }
      }
    }

    var lines = text.split("\n").length
    return {
      kind: "text",
      historyIndex: historyIndex,
      label: text.length + " chars" + (lines > 1 ? " · " + lines + " lines" : ""),
      preview: text.slice(0, root.previewChars),
      thumbnail: "",
      path: "",
      mime: "",
      // Offered under every name text targets ask for, so GTK, Qt, Electron
      // and XWayland apps all find one they accept.
      mimeData: {
        "text/plain;charset=utf-8": text,
        "text/plain": text,
        "UTF8_STRING": text
      }
    }
  }

  // Copied files arrive as file:// lines. Only treat an entry as files when
  // every line is one, so ordinary text that mentions a URI stays text.
  function filePaths(text) {
    var lines = String(text).split(/\r?\n/)
    var paths = []
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      if (line.indexOf("file://") !== 0) return []
      var path = line.substring(7)
      if (path.indexOf("localhost/") === 0) path = path.substring(9)
      if (path.charAt(0) !== "/") return []
      try { path = decodeURIComponent(path) } catch (e) {}
      paths.push(path)
    }
    return paths
  }

  function uriList(paths) {
    return paths.map(Util.fileUrl).join("\r\n") + "\r\n"
  }

  function fileName(path) {
    var parts = String(path).split("/")
    return parts[parts.length - 1] || String(path)
  }

  function isImagePath(path) {
    return /\.(png|jpe?g|webp|gif|bmp|tiff?)$/i.test(String(path))
  }

  // ---- actions ------------------------------------------------------------

  // The clipboard manager's own helpers, so a copy from the shelf behaves
  // exactly like one from Super+Ctrl+V.
  function copy(item) {
    if (item.kind === "image") {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-file", "--copy-only", item.mime, item.path])
    } else {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-text", "--copy-only", "--history-index", String(item.historyIndex)])
    }
    root.flash("Copied")
  }

  function flash(message) {
    root.status = message
    statusTimer.restart()
  }

  Timer {
    id: statusTimer
    interval: 1400
    onTriggered: root.status = ""
  }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    printErrors: false
    onLoaded: root.load(text())
    onLoadFailed: root.load("[]")
    onFileChanged: reload()
  }

  // ---- window -------------------------------------------------------------

  PanelWindow {
    id: panel
    visible: root.opened
    // Only the right edge is anchored, so the compositor centres it vertically.
    anchors.right: true
    margins.right: Style.gapsOut * 2
    implicitWidth: root.shelfWidth
    implicitHeight: Math.round((panel.screen ? panel.screen.height : 1080) * 0.7)
    color: "transparent"
    WlrLayershell.namespace: "omashelf"
    WlrLayershell.layer: WlrLayer.Top
    // Focus only when clicked, so the window you are dropping into keeps it.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore

    BorderSurface {
      id: frame
      anchors.fill: parent
      radius: root.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.close()
            event.accepted = true
          }
        }
      }

      Item {
        id: content
        anchors.fill: parent
        anchors.topMargin: frame.contentTopInset
        anchors.rightMargin: frame.contentRightInset
        anchors.bottomMargin: frame.contentBottomInset
        anchors.leftMargin: frame.contentLeftInset

        Item {
          id: header
          width: parent.width
          height: Math.max(Style.space(28), Style.font.heading + Style.space(8))

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Shelf"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Text {
            anchors.right: closeButton.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: root.status
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            id: closeButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "󰅖"
            color: root.foreground
            opacity: closeArea.containsMouse ? 1 : 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading

            MouseArea {
              id: closeArea
              anchors.fill: parent
              anchors.margins: -Style.space(6)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.close()
            }
          }
        }

        ListView {
          id: list
          anchors.top: header.bottom
          anchors.topMargin: Style.space(8)
          anchors.bottom: footer.top
          anchors.bottomMargin: Style.space(8)
          width: parent.width
          clip: true
          spacing: Style.space(6)
          boundsBehavior: Flickable.StopAtBounds
          model: root.items

          delegate: Rectangle {
            id: card
            required property var modelData
            required property int index

            readonly property bool hot: dragArea.containsMouse || dragArea.drag.active

            width: ListView.view.width
            height: cardBody.implicitHeight + Style.space(10) * 2
            radius: root.cornerRadius
            color: hot ? root.selectedBackground : Util.alpha(root.foreground, 0.06)

            Column {
              id: cardBody
              x: Style.space(10)
              y: Style.space(10)
              width: parent.width - Style.space(10) * 2
              spacing: Style.space(6)

              Image {
                visible: card.modelData.thumbnail !== ""
                width: parent.width
                height: visible ? Style.space(110) : 0
                source: card.modelData.thumbnail
                sourceSize.width: width * 2
                fillMode: Image.PreserveAspectFit
                horizontalAlignment: Image.AlignLeft
                asynchronous: true
                smooth: true
              }

              Text {
                visible: card.modelData.preview !== ""
                width: parent.width
                textFormat: Text.PlainText
                text: card.modelData.preview
                color: card.hot ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 4
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                text: card.modelData.label
                color: card.hot ? root.selectedText : root.foreground
                opacity: 0.55
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            // What actually gets dragged. It is invisible and snaps back after
            // the drop, so the card itself never moves.
            Item {
              id: dragProxy
              width: card.width
              height: card.height
              Drag.active: dragArea.drag.active
              Drag.dragType: Drag.Automatic
              Drag.supportedActions: Qt.CopyAction
              Drag.proposedAction: Qt.CopyAction
              Drag.mimeData: card.modelData.mimeData
              Drag.onDragFinished: function(dropAction) {
                dragProxy.x = 0
                dragProxy.y = 0
                if (dropAction !== Qt.IgnoreAction) root.flash("Dropped")
              }
            }

            MouseArea {
              id: dragArea
              anchors.fill: parent
              hoverEnabled: true
              // Keep the list from turning a card drag into a scroll.
              preventStealing: true
              cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
              drag.target: dragProxy
              onPressed: function(mouse) {
                dragProxy.Drag.hotSpot.x = mouse.x
                dragProxy.Drag.hotSpot.y = mouse.y
                card.grabToImage(function(result) { dragProxy.Drag.imageSource = result.url })
              }
              onReleased: {
                dragProxy.x = 0
                dragProxy.y = 0
              }
              onClicked: root.copy(card.modelData)
            }
          }
        }

        Text {
          anchors.centerIn: list
          visible: root.items.length === 0
          text: "Clipboard is empty"
          color: root.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
        }

        Text {
          id: footer
          anchors.bottom: parent.bottom
          width: parent.width
          text: "Drag into any app · click to copy"
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }
}
