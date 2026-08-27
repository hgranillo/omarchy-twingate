import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.hgranillo.twingate"
  ipcTarget: "io.github.hgranillo.twingate"
  manageIpc: false

  property string focusSection: "header"
  property int authIndex: 0
  property int resourceIndex: 0
  property int recentIndex: 0
  property int noticeIndex: 0
  property int exitNodeIndex: 0
  property int accountIndex: 0
  property bool cursorActive: false
  property string filterText: ""
  property int phraseIndex: 0

  readonly property var activePhrases: [
    "Guarding resources",
    "Checking policies",
    "Warming connectors",
    "Resolving private names",
    "Verifying every hop",
    "Sealing tunnels",
    "Minding the gateways",
    "Keeping ports shut",
    "Routing quietly",
    "Trusting nothing"
  ]

  // Only while there is nothing to report. Any fault keeps the real status on
  // screen, where the hero is the only place that spells it out.
  readonly property bool rotatingPhrases: twingate.conn === Model.CONN_ONLINE && twingate.lastError === ""
  readonly property string heroStatusText: rotatingPhrases
    ? activePhrases[phraseIndex % activePhrases.length]
    : twingate.statusText

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color barIconColor: twingate.active ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property color iconColor: twingate.active ? foreground : dim
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"

  // The panel must still show the search field and some resources below this
  // section, so it is capped even though every row in it is actionable.
  readonly property int authRowCap: 6
  readonly property var authView: Model.filterResources(twingate.needsAuthResources, filterText, authRowCap)
  readonly property var authRows: authView.rows
  readonly property var listedResources: showRecent
    ? Model.excludeNames(twingate.reachableResources, recentRows.map(function (r) { return r.name }))
    : twingate.reachableResources
  readonly property var resourceView: Model.filterResources(listedResources, filterText, twingate.maxResourceRows)
  readonly property var resourceRows: resourceView.rows

  readonly property int recentCap: 5
  readonly property var recentNames: settings.recentResources instanceof Array ? settings.recentResources : []
  readonly property var recentRows: Model.recentResources(twingate.reachableResources, recentNames, recentCap)

  readonly property bool showAuth: authRows.length > 0
  readonly property bool showSearch: twingate.notifierInstalled && (twingate.resources.length > 0 || filterText !== "")
  readonly property bool showResources: twingate.notifierInstalled && (twingate.reachableResources.length > 0 || filterText !== "")
  // Hidden while filtering: a search is already aiming at something, and the
  // duplicate rows would only be noise.
  readonly property bool showRecent: filterText === "" && recentRows.length > 0
  readonly property bool showExitNodes: twingate.cliInstalled && twingate.exitNodes.length > 0
  readonly property bool showAccounts: twingate.cliInstalled && twingate.accounts.length > 1
  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && twingate.systemctlInstalled

  readonly property string toggleHint: twingate.active
    ? "Disconnect Twingate (asks for authentication)"
    : "Connect Twingate (asks for authentication)"

  readonly property var notices: {
    var out = []
    if (twingate.probed && !twingate.notifierInstalled) out.push("install")
    if (twingate.notifierInstalled && twingate.authPromptsProbed && !twingate.authPromptsActive) out.push("prompts")
    if (twingate.conn === Model.CONN_NOT_CONFIGURED) out.push("setup")
    if (twingate.updateCount > 0) out.push("update")
    return out
  }

  readonly property string installDocsUrl: "https://www.twingate.com/docs/linux#pacman-arch-linux"

  function noticeGlyph(kind) {
    if (kind === "install") return "\u{F059F}"
    if (kind === "prompts") return "\u{F009A}"
    if (kind === "setup") return "\u{F0493}"
    return "\u{F06B0}"
  }

  function noticeLabel(kind) {
    if (kind === "install") return "Install Twingate"
    if (kind === "prompts") return "Turn on Twingate sign-in prompts"
    if (kind === "setup") return "Finish Twingate setup"
    return "Update this panel"
  }

  function noticeDetail(kind) {
    if (kind === "install") return "The twingate client is not on PATH. Opens Twingate's install guide for Arch."
    if (kind === "prompts") return "Twingate asks you to sign in through a desktop notification. That service is not running, so it cannot ask."
    if (kind === "setup") return "The client is installed but has no network configured."
    return twingate.updateCount === 1 ? "1 new commit upstream" : twingate.updateCount + " new commits upstream"
  }

  function runNotice(kind) {
    if (kind === "install") twingate.openUrl(installDocsUrl)
    else if (kind === "prompts") twingate.enableAuthPrompts()
    else if (kind === "setup") present("sudo twingate setup")
    else present("omarchy plugin update " + moduleName + " && omarchy-restart-shell")
  }

  readonly property string heroDetail: {
    if (twingate.lockedCount === 0) return ""
    return twingate.lockedCount + (twingate.lockedCount === 1 ? " needs auth" : " need auth")
  }

  function sectionRows(section) {
    if (section === "auth") return authRows.length
    if (section === "notices") return notices.length
    if (section === "recent") return recentRows.length
    if (section === "resources") return resourceRows.length
    if (section === "exitNodes") return twingate.exitNodes.length
    if (section === "accounts") return twingate.accounts.length
    return 1
  }

  function visibleSections() {
    var list = ["header"]
    if (notices.length > 0) list.push("notices")
    if (showSearch) list.push("search")
    if (showAuth) list.push("auth")
    if (showRecent) list.push("recent")
    if (showResources && resourceRows.length > 0) list.push("resources")
    if (showExitNodes) list.push("exitNodes")
    if (showAccounts) list.push("accounts")
    return list
  }

  function sectionIndex(section) {
    if (section === "auth") return authIndex
    if (section === "notices") return noticeIndex
    if (section === "recent") return recentIndex
    if (section === "resources") return resourceIndex
    if (section === "exitNodes") return exitNodeIndex
    if (section === "accounts") return accountIndex
    return 0
  }

  function setSectionIndex(section, value) {
    if (section === "auth") authIndex = value
    else if (section === "notices") noticeIndex = value
    else if (section === "recent") recentIndex = value
    else if (section === "resources") resourceIndex = value
    else if (section === "exitNodes") exitNodeIndex = value
    else if (section === "accounts") accountIndex = value
  }

  function ensureCursor() {
    var sections = visibleSections()
    if (sections.indexOf(focusSection) === -1) focusSection = sections[0]
    var rows = sectionRows(focusSection)
    var index = sectionIndex(focusSection)
    if (index < 0) setSectionIndex(focusSection, 0)
    else if (index >= rows) setSectionIndex(focusSection, Math.max(0, rows - 1))
  }

  function moveCursor(dx, dy) {
    if (dy === 0) return
    var sections = visibleSections()
    var at = sections.indexOf(focusSection)
    if (at === -1) { focusSection = sections[0]; return }
    var rows = sectionRows(focusSection)
    var index = sectionIndex(focusSection) + dy
    if (index >= 0 && index < rows) { setSectionIndex(focusSection, index); scrollCursorIntoView(); return }
    var nextAt = at + dy
    if (nextAt < 0 || nextAt >= sections.length) return
    focusSection = sections[nextAt]
    setSectionIndex(focusSection, dy > 0 ? 0 : Math.max(0, sectionRows(focusSection) - 1))
    scrollCursorIntoView()
  }

  function firstListSection() {
    var order = ["auth", "recent", "resources"]
    var sections = visibleSections()
    for (var i = 0; i < order.length; i++)
      if (sections.indexOf(order[i]) !== -1 && sectionRows(order[i]) > 0) return order[i]
    return ""
  }

  function selectedResource() {
    // Leaving the search box aims at the top result rather than nothing.
    if (focusSection === "search") {
      var section = firstListSection()
      if (section === "auth") return authRows[0]
      if (section === "recent") return recentRows[0]
      if (section === "resources") return resourceRows[0]
      return null
    }
    if (focusSection === "auth" && authIndex < authRows.length) return authRows[authIndex]
    if (focusSection === "recent" && recentIndex < recentRows.length) return recentRows[recentIndex]
    if (focusSection === "resources" && resourceIndex < resourceRows.length) return resourceRows[resourceIndex]
    return null
  }

  function activateCursor() {
    if (focusSection === "header") { twingate.toggleConnection(); return }
    if (focusSection === "notices") {
      if (noticeIndex < notices.length) runNotice(notices[noticeIndex])
      return
    }
    if (focusSection === "search") {
      var target = selectedResource()
      if (target) { if (target.needsAuth) twingate.authenticate(target.name); else copyResource(target) }
      else search.forceActiveFocus()
      return
    }
    if (focusSection === "auth") {
      var locked = authRows[authIndex]
      if (locked) twingate.authenticate(locked.name)
      return
    }
    if (focusSection === "recent" || focusSection === "resources") {
      copyResource(selectedResource())
      return
    }
    if (focusSection === "exitNodes") {
      var node = twingate.exitNodes[exitNodeIndex]
      if (node) twingate.setExitNode(node)
      return
    }
    if (focusSection === "accounts") {
      var account = twingate.accounts[accountIndex]
      if (account) twingate.switchAccount(account.email)
    }
  }

  function scrollItemIntoView(item) {
    if (!item || !panelFlick) return
    var top = item.mapToItem(column, 0, 0).y
    var bottom = top + item.height
    if (top < panelFlick.contentY) panelFlick.contentY = Math.max(0, top - Style.space(8))
    else if (bottom > panelFlick.contentY + panelFlick.height)
      panelFlick.contentY = Math.min(Math.max(0, panelFlick.contentHeight - panelFlick.height),
                                    bottom - panelFlick.height + Style.space(8))
  }

  function scrollCursorIntoView() { Qt.callLater(function() { scrollItemIntoView(cursorItem) }) }
  property Item cursorItem: null

  function present(command) {
    if (!bar) return
    bar.run("omarchy-launch-floating-terminal-with-presentation " + Util.shellQuote(command))
    close()
  }

  function rememberResource(resource) {
    if (!resource || !bar || !bar.shell || typeof bar.shell.updateEntryInline !== "function") return
    var entry = { id: root.moduleName }
    for (var key in settings) if (key !== "id") entry[key] = settings[key]
    entry.recentResources = Model.pushRecent(recentNames, resource.name, recentCap)
    bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function copyResource(resource) {
    if (!resource) return
    twingate.copyToClipboard(resource.address)
    rememberResource(resource)
  }

  function openResource(resource) {
    if (!resource || !resource.browsable) return
    twingate.openUrl(resource.browseUrl)
    rememberResource(resource)
  }

  function setFilter(next) {
    filterText = next
    resourceIndex = 0
    ensureCursor()
  }

  function toggleHidden() {
    if (!bar || !bar.shell) return
    var entry = { id: root.moduleName }
    for (var key in settings) if (key !== "id") entry[key] = settings[key]
    entry.showHidden = !twingate.showHidden
    bar.shell.updateEntryInline(root.moduleName, entry)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    setFilter("")
    if (search) search.text = ""
    if (panelFlick) panelFlick.contentY = 0
    twingate.refreshStatus(true)
    twingate.refreshResources(true)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  onAuthRowsChanged: ensureCursor()
  onResourceRowsChanged: ensureCursor()
  onRecentRowsChanged: ensureCursor()
  onNoticesChanged: ensureCursor()

  Service {
    id: twingate
    settings: root.settings
    panelOpen: root.opened
    pluginId: root.moduleName
  }

  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && root.rotatingPhrases
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
    }
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  Connections {
    target: root
    function onRotatingPhrasesChanged() {
      if (!root.rotatingPhrases) {
        phraseSwap.stop()
        hero.metaOpacity = 1.0
      }
    }
  }

  Connections {
    target: twingate
    function onExitNodesChanged() { root.ensureCursor() }
    function onAccountsChanged() { root.ensureCursor() }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { twingate.refreshAll(); return "ok" }
    function connect(): string { if (!twingate.active) twingate.toggleConnection(); return "ok" }
    function disconnect(): string { if (twingate.active) twingate.toggleConnection(); return "ok" }
    function toggleConnection(): string { twingate.toggleConnection(); return "ok" }
    function status(): string { return twingate.statusText }
    function network(): string { return twingate.networkName }
    function auth(name: string): string { twingate.authenticate(name); return "ok" }
    function list(): string {
      var out = []
      for (var i = 0; i < twingate.resources.length; i++) {
        var r = twingate.resources[i]
        out.push(r.name + "\t" + r.address + "\t" + r.expiryText)
      }
      return out.join("\n")
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: {
      var head = (twingate.networkName === "" ? "Twingate" : twingate.networkName) + ": " + twingate.statusText
      return twingate.sessionExpiry === "" ? head : head + "\n" + twingate.sessionExpiry
    }
    iconComponent: Component {
      Item {
        TwingateIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: root.barIconColor
          ringColor: Color.bar.background
          mode: twingate.iconMode
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) twingate.toggleConnection()
      else if (buttonCode === Qt.MiddleButton) twingate.refreshAll()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: search.activeFocus
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "/") { root.focusSection = "search"; root.cursorActive = true; search.forceActiveFocus() }
        else if (t === "t" || t === "T") twingate.toggleConnection()
        else if (t === "r" || t === "R") twingate.refreshAll()
        else if (t === "H") root.toggleHidden()
        else if (t === "c" || t === "C") root.copyResource(root.selectedResource())
        else if (t === "o" || t === "O") root.openResource(root.selectedResource())
        else if (t === "a" || t === "A") {
          var authTarget = root.selectedResource()
          if (authTarget && authTarget.needsAuth) twingate.authenticate(authTarget.name)
        }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            // Exposed for the hero's trailingControl, whose `root` resolves to
            // PanelHero rather than this Panel.
            readonly property bool ringVisible: root.headerHasCursor
            function focusHero() { root.cursorActive = true; root.focusSection = "header" }

            PanelHero {
              id: hero
              width: parent.width
              title: twingate.networkName === "" ? "Twingate" : twingate.networkName
              meta: root.heroStatusText
              detail: root.heroDetail
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: twingate.active ? 1.0 : 0.5
              iconComponent: Component {
                TwingateIcon {
                  iconSize: Style.font.display
                  color: root.iconColor
                  mode: twingate.iconMode
                }
              }
              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: twingate.systemctlInstalled && twingate.notifierInstalled
                  checked: twingate.active
                  busy: twingate.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: twingate.toggleConnection()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: root.toggleHint
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            visible: twingate.actionStatus !== "" || twingate.lastError !== ""
            width: parent.width
            text: twingate.actionStatus !== "" ? twingate.actionStatus : twingate.lastError
            color: twingate.lastError !== "" && twingate.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            visible: twingate.actionStatus === "" && twingate.lastError === ""
            width: parent.width
            spacing: Style.space(2)

            Text {
              visible: twingate.userEmail !== ""
              width: parent.width
              text: twingate.userEmail
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Text {
              visible: twingate.sessionExpiry !== ""
              width: parent.width
              text: twingate.sessionExpiry
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          Repeater {
            model: root.notices
            ActionNotice {
              required property var modelData
              required property int index
              width: parent.width
              kind: modelData
              rowIndex: index
            }
          }

          TextField {
            id: search
            visible: root.showSearch
            width: parent.width
            placeholderText: "Search resources…"
            foreground: root.foreground
            verticalPadding: Style.space(4)
            hasCursor: root.cursorActive && root.focusSection === "search"
            text: root.filterText
            onTextEdited: root.setFilter(text)
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                keyCatcher.forceActiveFocus()
                var landing = root.firstListSection()
                root.focusSection = landing === "" ? "search" : landing
                if (landing !== "") root.setSectionIndex(landing, 0)
                event.accepted = true
              } else if (event.key === Qt.Key_Down) {
                keyCatcher.forceActiveFocus()
                var next = root.firstListSection()
                if (next !== "") { root.focusSection = next; root.setSectionIndex(next, 0) }
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                var hit = root.selectedResource()
                if (hit) { if (hit.needsAuth) twingate.authenticate(hit.name); else root.copyResource(hit) }
                event.accepted = true
              }
            }
          }

          PanelSeparator { visible: root.showAuth; foreground: root.foreground }

          Column {
            visible: root.showAuth
            width: parent.width
            spacing: Style.space(4)

            PanelSectionHeader {
              text: "NEEDS AUTHENTICATION"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.authRows
              AuthResourceRow {
                required property var modelData
                required property int index
                width: parent.width
                resource: modelData
                rowIndex: index
              }
            }

            Text {
              visible: root.authView.truncated
              width: parent.width
              text: "+" + (root.authView.total - root.authRows.length) + " more  ·  type to narrow"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          PanelSeparator { visible: root.showRecent; foreground: root.foreground }

          Column {
            visible: root.showRecent
            width: parent.width
            spacing: Style.space(4)

            PanelSectionHeader {
              text: "RECENT"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.recentRows
              ResourceRow {
                required property var modelData
                required property int index
                width: parent.width
                resource: modelData
                rowIndex: index
                section: "recent"
              }
            }
          }

          PanelSeparator { visible: root.showResources; foreground: root.foreground }

          Column {
            visible: root.showResources
            width: parent.width
            spacing: Style.space(4)

            PanelSectionHeader {
              text: "RESOURCES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: root.resourceRows.length === 0
              width: parent.width
              text: "No resources match “" + root.filterText + "”"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Repeater {
              model: root.resourceRows
              ResourceRow {
                required property var modelData
                required property int index
                width: parent.width
                resource: modelData
                rowIndex: index
              }
            }

            Text {
              visible: root.resourceView.truncated
              width: parent.width
              text: "+" + (root.resourceView.total - root.resourceRows.length) + " more  ·  type to narrow"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          PanelSeparator { visible: root.showExitNodes; foreground: root.foreground }

          Column {
            visible: root.showExitNodes
            width: parent.width
            spacing: Style.space(4)

            PanelSectionHeader {
              text: "EXIT NODES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: twingate.exitNodes
              ExitNodeRow {
                required property var modelData
                required property int index
                width: parent.width
                node: modelData
                rowIndex: index
              }
            }
          }

          PanelSeparator { visible: root.showAccounts; foreground: root.foreground }

          Column {
            visible: root.showAccounts
            width: parent.width
            spacing: Style.space(4)

            PanelSectionHeader {
              text: "ACCOUNTS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: twingate.accounts
              AccountRow {
                required property var modelData
                required property int index
                width: parent.width
                account: modelData
                rowIndex: index
              }
            }
          }

          Row {
            visible: twingate.notifierInstalled
            width: parent.width
            spacing: Style.space(6)

            PanelActionButton {
              iconText: "\u{F0450}"
              tooltipText: "Refresh"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: twingate.refreshAll()
            }

            PanelActionButton {
              visible: twingate.adminUrl !== ""
              iconText: "\u{F059F}"
              tooltipText: "Open the Twingate admin console"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: twingate.openUrl(twingate.adminUrl)
            }

            PanelActionButton {
              iconText: "\u{F06E}"
              tooltipText: twingate.showHidden ? "Hide hidden resources" : "Show hidden resources"
              foreground: twingate.showHidden ? root.foreground : root.dim
              fontFamily: root.fontFamily
              onClicked: root.toggleHidden()
            }
          }
        }
      }
    }
  }

  component ActionNotice: CursorSurface {
    id: notice
    property string kind: ""
    property int rowIndex: 0
    readonly property string glyph: root.noticeGlyph(kind)
    readonly property string label: root.noticeLabel(kind)
    readonly property string detail: root.noticeDetail(kind)

    hasCursor: root.cursorActive && root.focusSection === "notices" && root.noticeIndex === rowIndex
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: noticeInner.implicitHeight + Style.spacing.lg
    onHasCursorChanged: if (hasCursor) root.cursorItem = notice

    Row {
      id: noticeInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        text: notice.glyph
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        width: parent.width - Style.space(22) - Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          width: parent.width
          text: notice.label
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          visible: notice.detail !== ""
          text: notice.detail
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: { root.cursorActive = true; root.focusSection = "notices"; root.noticeIndex = notice.rowIndex }
      onClicked: root.runNotice(notice.kind)

      PanelToolTip {
        visible: parent.containsMouse
        text: {
          if (notice.kind === "install") return "Opens the official install guide in your browser"
          if (notice.kind === "prompts") return "Starts the Twingate notification service"
          return "Opens a terminal so you can see what runs"
        }
        fontFamily: root.fontFamily
      }
    }
  }

  component AuthResourceRow: CursorSurface {
    id: authRow
    property var resource: null
    property int rowIndex: 0
    readonly property bool inFlight: resource && twingate.authenticating === String(resource.name || "")

    hasCursor: root.cursorActive && root.focusSection === "auth" && root.authIndex === rowIndex
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: authInner.implicitHeight + Style.spacing.md
    onHasCursorChanged: if (hasCursor) root.cursorItem = authRow

    Row {
      id: authInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        text: authRow.resource ? Model.resourceGlyph(authRow.resource) : ""
        color: authRow.resource && authRow.resource.expired ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
        opacity: authRow.inFlight ? 0.45 : 1.0

        SequentialAnimation on opacity {
          running: authRow.inFlight
          NumberAnimation { to: 1.0; duration: 420; easing.type: Easing.InOutQuad }
          NumberAnimation { to: 0.45; duration: 420; easing.type: Easing.InOutQuad }
          loops: Animation.Infinite
        }
      }

      Column {
        width: parent.width - Style.space(22) - Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          width: parent.width
          text: authRow.resource ? authRow.resource.name : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: authRow.resource
            ? (authRow.resource.state === "locked" ? authRow.resource.address
                                                   : authRow.resource.expiryText + "  ·  " + authRow.resource.address)
            : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: { root.cursorActive = true; root.focusSection = "auth"; root.authIndex = authRow.rowIndex }
      onClicked: if (authRow.resource) twingate.authenticate(authRow.resource.name)

      PanelToolTip {
        visible: parent.containsMouse
        text: "Authenticate " + (authRow.resource ? authRow.resource.name : "")
        fontFamily: root.fontFamily
      }
    }
  }

  component ResourceRow: CursorSurface {
    id: resourceRow
    property var resource: null
    property int rowIndex: 0
    property string section: "resources"
    readonly property bool hot: hasCursor

    hasCursor: root.cursorActive && root.focusSection === section && root.sectionIndex(section) === rowIndex
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: resourceInner.implicitHeight + Style.spacing.md
    onHasCursorChanged: if (hasCursor) root.cursorItem = resourceRow

    Row {
      id: resourceInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        id: resourceGlyph
        text: resourceRow.resource && resourceRow.resource.state !== "ok"
          ? Model.resourceGlyph(resourceRow.resource) : ""
        color: resourceRow.resource && resourceRow.resource.expired ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        id: resourceLabels
        width: parent.width - resourceGlyph.width - openButton.width - copyButton.width - Style.space(24)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          width: parent.width
          text: resourceRow.resource ? resourceRow.resource.name : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: resourceRow.resource ? resourceRow.resource.address : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        id: openButton
        anchors.verticalCenter: parent.verticalCenter
        readonly property bool available: resourceRow.resource ? resourceRow.resource.browsable === true : false
        opacity: resourceRow.hot && available ? 1 : 0
        enabled: resourceRow.hot && available
        Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutQuad } }
        iconText: "\u{F059F}"
        tooltipText: "Open in browser"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.openResource(resourceRow.resource)
      }

      PanelActionButton {
        id: copyButton
        anchors.verticalCenter: parent.verticalCenter
        opacity: resourceRow.hot ? 1 : 0
        enabled: resourceRow.hot
        Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutQuad } }
        iconText: "\u{F018F}"
        tooltipText: "Copy address"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.copyResource(resourceRow.resource)
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      z: -1
      onEntered: {
        root.cursorActive = true
        root.focusSection = resourceRow.section
        root.setSectionIndex(resourceRow.section, resourceRow.rowIndex)
      }
      onClicked: root.copyResource(resourceRow.resource)

      PanelToolTip {
        visible: parent.containsMouse
        text: resourceRow.resource
          ? resourceRow.resource.address + "\n" + resourceRow.resource.expiryText
          : ""
        fontFamily: root.fontFamily
      }
    }
  }

  component ExitNodeRow: CursorSurface {
    id: exitNodeRow
    property var node: null
    property int rowIndex: 0
    readonly property bool nodeActive: node && node.active === true
    readonly property bool inFlight: node && twingate.switchingExitNode === String(node.name || "")

    hasCursor: root.cursorActive && root.focusSection === "exitNodes" && root.exitNodeIndex === rowIndex
    current: nodeActive
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: exitNodeInner.implicitHeight + Style.spacing.xl
    onHasCursorChanged: if (hasCursor) root.cursorItem = exitNodeRow

    Row {
      id: exitNodeInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        text: "\u{F11E2}"
        color: exitNodeRow.nodeActive ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
        opacity: exitNodeRow.inFlight ? 0.45 : 1.0

        SequentialAnimation on opacity {
          running: exitNodeRow.inFlight
          NumberAnimation { to: 1.0; duration: 420; easing.type: Easing.InOutQuad }
          NumberAnimation { to: 0.45; duration: 420; easing.type: Easing.InOutQuad }
          loops: Animation.Infinite
        }
      }

      Text {
        text: exitNodeRow.node ? String(exitNodeRow.node.name) : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: exitNodeRow.nodeActive
        elide: Text.ElideRight
        width: parent.width - Style.space(22) - Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: { root.cursorActive = true; root.focusSection = "exitNodes"; root.exitNodeIndex = exitNodeRow.rowIndex }
      onClicked: twingate.setExitNode(exitNodeRow.node)

      PanelToolTip {
        visible: parent.containsMouse
        text: exitNodeRow.nodeActive ? "Stop routing through this exit node" : "Route all traffic through this exit node"
        fontFamily: root.fontFamily
      }
    }
  }

  component AccountRow: CursorSurface {
    id: accountRow
    property var account: null
    property int rowIndex: 0
    readonly property bool currentAccount: account && twingate.userEmail !== "" && String(account.email) === twingate.userEmail
    readonly property bool inFlight: account && twingate.switchingAccount === String(account.email || "")

    hasCursor: root.cursorActive && root.focusSection === "accounts" && root.accountIndex === rowIndex
    current: currentAccount
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: accountInner.implicitHeight + Style.spacing.md
    onHasCursorChanged: if (hasCursor) root.cursorItem = accountRow

    Row {
      id: accountInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        text: ""
        color: accountRow.currentAccount ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
        opacity: accountRow.inFlight ? 0.45 : 1.0

        SequentialAnimation on opacity {
          running: accountRow.inFlight
          NumberAnimation { to: 1.0; duration: 420; easing.type: Easing.InOutQuad }
          NumberAnimation { to: 0.45; duration: 420; easing.type: Easing.InOutQuad }
          loops: Animation.Infinite
        }
      }

      Column {
        width: parent.width - Style.space(22) - Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          width: parent.width
          text: accountRow.account ? String(accountRow.account.email) : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: accountRow.currentAccount
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          visible: accountRow.account && String(accountRow.account.network) !== ""
          text: accountRow.account ? String(accountRow.account.network) : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: { root.cursorActive = true; root.focusSection = "accounts"; root.accountIndex = accountRow.rowIndex }
      onClicked: if (accountRow.account) twingate.switchAccount(accountRow.account.email)

      PanelToolTip {
        visible: parent.containsMouse
        text: accountRow.currentAccount ? "Signed in" : "Switch to this account"
        fontFamily: root.fontFamily
      }
    }
  }
}
