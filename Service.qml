import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property bool panelOpen: false
  property string pluginId: ""

  property bool notifierInstalled: false
  property bool cliInstalled: false
  property bool systemctlInstalled: false
  property bool probed: false
  // Session authentication is push-based: the daemon raises the request and this
  // user service turns it into the notification that opens the browser. With it
  // stopped, Twingate can never ask, and nothing on the desktop says why.
  property bool authPromptsActive: true
  property bool authPromptsProbed: false

  property string conn: Model.CONN_UNKNOWN

  // -1 follows reality; 0 or 1 while a toggle is still catching up. Without it
  // the switch sits dead through the polkit dialog.
  property int _desired: -1
  readonly property bool active: _desired === -1 ? (conn === Model.CONN_ONLINE) : (_desired === 1)

  property string networkName: ""
  property string userEmail: ""
  property string adminUrl: ""

  property var allResources: []
  property var rawResources: []
  property var resources: []

  // Exists only so time-dependent bindings have something to depend on; QML
  // will not re-evaluate a binding that calls Date.now() on its own.
  property int nowSec: 0

  property var exitNodes: []
  property var accounts: []
  property string switchingExitNode: ""
  property string switchingAccount: ""
  property string authenticating: ""

  property int updateCount: 0
  property string actionStatus: ""
  property string lastError: ""

  readonly property int statusIntervalSec: intSetting("statusIntervalSec", 10, 5, 600)
  readonly property int resourcesIntervalSec: intSetting("resourcesIntervalSec", 60, 15, 3600)
  readonly property bool showHidden: setting("showHidden", false) === true
  readonly property bool notifications: setting("notifications", true) === true
  readonly property int maxResourceRows: intSetting("maxResourceRows", 12, 0, 200)
  readonly property bool checkForUpdates: setting("checkForUpdates", true) === true

  readonly property var _split: Model.partition(resources)
  readonly property var needsAuthResources: _split.needsAuth
  readonly property var reachableResources: _split.reachable
  readonly property int lockedCount: Model.needsAuthCount(resources)
  readonly property int expiredCount: Model.expiredCount(resources)
  readonly property string iconMode: Model.iconMode(conn, lastError !== "", expiredCount)
  readonly property string sessionExpiry: Model.sessionExpiryText(resources, nowSec)
  readonly property string statusText: Model.statusLabel(conn, lastError !== "")

  readonly property bool busy: capsProcess.running || notifierProcess.running || unitProcess.running
    || controlProcess.running || discoverProcess.running || cliActionProcess.running

  property var _queue: []
  property string _kind: ""
  property string _pendingNotifierError: ""
  property var _discoverQueue: []
  property string _discoverKind: ""
  property string _announced: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function stamp() {
    nowSec = Math.floor(Date.now() / 1000)
    return nowSec
  }

  function probe() {
    if (capsProcess.running) return
    capsProcess.command = ["which", "twingate-notifier", "twingate", "systemctl"]
    capsProcess.running = true
  }

  function refresh() {
    if (!probed) { probe(); return }
    refreshStatus(false)
  }

  function refreshAll() {
    probed = false
    probe()
  }

  // Only a request that has not started may be shared. Joining an in-flight one
  // would answer the new caller with output the daemon produced before it asked.
  function enqueue(kind, arg, force) {
    if (!notifierInstalled) return
    if (force !== true) {
      for (var i = 0; i < _queue.length; i++)
        if (_queue[i].kind === kind && _queue[i].arg === arg) return
    }
    var next = _queue.slice()
    next.push({ kind: kind, arg: arg })
    _queue = next
    pumpQueue()
  }

  function pumpQueue() {
    if (notifierProcess.running || _queue.length === 0) return
    var next = _queue.slice()
    var job = next.shift()
    _queue = next
    _kind = job.kind
    notifierStdout.reset()
    notifierProcess.command = job.arg === "" ? ["twingate-notifier", job.kind]
                                             : ["twingate-notifier", job.kind, job.arg]
    notifierProcess.running = true
    if (!pollWatchdog.running) pollWatchdog.start()
  }

  function refreshStatus(force) { enqueue("status", "", force === true) }
  function refreshResources(force) { enqueue("resources", "", force === true) }

  function authenticate(name) {
    if (String(name || "") === "") return
    authenticating = String(name)
    actionStatus = "Continue in your browser…"
    actionStatusTimer.restart()
    enqueue("auth", String(name), true)
  }

  function enqueueDiscover(kind) {
    if (!cliInstalled) return
    for (var i = 0; i < _discoverQueue.length; i++)
      if (_discoverQueue[i] === kind) return
    var next = _discoverQueue.slice()
    next.push(kind)
    _discoverQueue = next
    pumpDiscover()
  }

  function pumpDiscover() {
    if (discoverProcess.running || _discoverQueue.length === 0) return
    var next = _discoverQueue.slice()
    var kind = next.shift()
    _discoverQueue = next
    _discoverKind = kind
    discoverProcess.command = kind === "exit-nodes"
      ? ["twingate", "exit-node", "list", "-d"]
      : ["twingate", "account", "list", "-d"]
    discoverProcess.running = true
    if (!pollWatchdog.running) pollWatchdog.start()
  }

  function discover() {
    enqueueDiscover("exit-nodes")
    enqueueDiscover("accounts")
  }

  function applyStatus(next) {
    conn = next
    lastError = ""
    if (_desired !== -1 && (conn === Model.CONN_ONLINE) === (_desired === 1)) _desired = -1
    if (conn === Model.CONN_ONLINE) refreshResources(false)
    else if (conn === Model.CONN_STOPPED) { resources = []; rawResources = []; allResources = [] }
    announce()
  }

  // A daemon that did not answer is not a state change, and announcing it would
  // announce the recovery too. The first resolution is skipped so every login
  // does not raise a notification.
  function announce() {
    if (!notifications || conn === Model.CONN_UNKNOWN) return
    if (_announced === "") { _announced = conn; return }
    if (_announced === conn) return
    _announced = conn
    var body = networkName === "" ? statusText : networkName
    Quickshell.execDetached(["notify-send", "-u", "low", "-a", "Twingate", "Twingate " + statusText, body])
  }

  function applyResources(raw) {
    var parsed = Model.parseResources(raw, true)
    // A stale list beats an empty panel, so an unparseable reply changes nothing.
    if (!parsed.ok) { lastError = String(parsed.error).substring(0, 140); return }
    networkName = parsed.networkName
    userEmail = parsed.userEmail
    adminUrl = parsed.adminUrl
    allResources = parsed.resources
    applyVisibility()
  }

  function applyVisibility() {
    var visible = []
    for (var i = 0; i < allResources.length; i++) {
      if (Model.isHidden(allResources[i]) && !showHidden) continue
      visible.push(allResources[i])
    }
    rawResources = visible
    resources = Model.decorate(visible, stamp())
  }

  function redecorate() {
    if (rawResources.length > 0) resources = Model.decorate(rawResources, stamp())
  }

  onShowHiddenChanged: if (allResources.length > 0) applyVisibility()

  function toggleConnection() {
    if (!notifierInstalled || !systemctlInstalled || controlProcess.running) return
    if (active) runControl("stop", 0)
    else runControl("start", 1)
  }

  function runControl(verb, desired) {
    _desired = desired
    lastError = ""
    actionStatus = verb === "start" ? "Connecting…" : "Disconnecting…"
    controlProcess.command = ["systemctl", verb, "twingate.service"]
    controlProcess.running = true
    controlWatchdog.restart()
    desiredGuard.restart()
  }

  function copyToClipboard(value) {
    var text = String(value || "")
    if (text === "") return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(text) + " | wl-copy"])
    actionStatus = "Copied " + text
    actionStatusTimer.restart()
  }

  function openUrl(url) {
    if (!Model.isWebUrl(url)) return
    Quickshell.execDetached(["omarchy-launch-browser", String(url)])
  }

  readonly property bool exitNodeRouting: {
    for (var i = 0; i < exitNodes.length; i++) if (exitNodes[i].active === true) return true
    return false
  }

  function setExitNode(node) {
    if (!cliInstalled || cliActionProcess.running || !node) return
    switchingExitNode = String(node.name || "")
    // `start` turns routing on; changing nodes while it is already on is `switch`.
    var verb = node.active ? "stop" : (exitNodeRouting ? "switch" : "start")
    cliActionProcess.command = verb === "stop"
      ? ["twingate", "exit-node", "stop", "-d"]
      : ["twingate", "exit-node", verb, String(node.name), "-d"]
    cliActionProcess.running = true
  }

  function switchAccount(email) {
    if (!cliInstalled || cliActionProcess.running || String(email || "") === "") return
    switchingAccount = String(email)
    cliActionProcess.command = ["twingate", "account", "switch", String(email), "-d"]
    cliActionProcess.running = true
  }

  // Omarchy clones plugins into a directory named by the manifest id and never
  // pulls them, so a published plugin has to notice its own updates.
  readonly property string pluginDir: pluginId === "" ? ""
    : Quickshell.env("HOME") + "/.config/omarchy/plugins/" + pluginId

  function probeAuthPrompts() {
    if (!systemctlInstalled || authProbeProcess.running) return
    authProbeProcess.command = ["systemctl", "--user", "is-active", "twingate-desktop-notifier"]
    authProbeProcess.running = true
  }

  function enableAuthPrompts() {
    if (authActionProcess.running) return
    actionStatus = "Starting Twingate notifications…"
    authActionProcess.command = ["systemctl", "--user", "enable", "--now", "twingate-desktop-notifier"]
    authActionProcess.running = true
  }

  function checkUpdate() {
    if (!checkForUpdates || pluginDir === "" || updateProcess.running) return
    updateProcess.command = ["bash", "-lc",
      "cd " + Util.shellQuote(pluginDir)
      + " && git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1"
      + " && timeout 20 git fetch -q"
      + " && git rev-list --count HEAD..@{u} || echo 0"]
    updateProcess.running = true
  }

  function settle() {
    refreshStatus(true)
    settleTimer.restart()
  }

  Timer {
    id: statusTimer
    interval: root.statusIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: resourcesTimer
    interval: root.resourcesIntervalSec * 1000
    repeat: true
    running: root.notifierInstalled
    onTriggered: root.refreshResources(false)
  }

  Timer {
    id: expiryTicker
    interval: 30000
    repeat: true
    running: root.panelOpen && root.rawResources.length > 0
    onTriggered: root.redecorate()
  }

  Timer {
    id: discoverTimer
    interval: 300000
    repeat: true
    running: root.cliInstalled
    triggeredOnStart: true
    onTriggered: root.discover()
  }

  Timer {
    // After a fresh login the first poll usually lands before twingate.service
    // has finished activating, which left the icon stale until the next tick.
    id: startupRamp
    property int ticks: 0
    interval: 2000
    repeat: true
    running: true
    onTriggered: {
      ticks += 1
      if (root.conn !== Model.CONN_UNKNOWN || ticks >= 15) startupRamp.running = false
      else root.refresh()
    }
  }

  Timer {
    // systemd reports the unit up before the daemon answers status requests.
    id: settleTimer
    interval: 2000
    repeat: false
    onTriggered: {
      root.refreshStatus(true)
      root.refreshResources(true)
    }
  }

  Timer {
    // A poll is skipped while its own process still runs, so one that never
    // exits stops the panel refreshing permanently. Armed on the launch that
    // needs it and never restarted: restarting pushes the deadline out ahead of
    // a hung process forever.
    id: pollWatchdog
    interval: 15000
    repeat: false
    onTriggered: {
      // Cancelling leaves the child alive, and a live twingate-notifier keeps
      // holding the daemon socket that the next call needs.
      if (notifierProcess.running) notifierProcess.running = false
      if (discoverProcess.running) discoverProcess.running = false
      if (unitProcess.running) unitProcess.running = false
    }
  }

  Timer {
    // The polkit dialog blocks until the user answers it.
    id: controlWatchdog
    interval: 120000
    repeat: false
    onTriggered: {
      if (!controlProcess.running) return
      controlProcess.running = false
      root._desired = -1
      root.actionStatus = "Authentication timed out"
      actionStatusTimer.restart()
    }
  }

  Timer {
    // systemd and polkit can both succeed while the daemon never reaches Online.
    id: desiredGuard
    interval: 30000
    repeat: false
    onTriggered: root._desired = -1
  }

  Timer {
    // Late enough that a login is not competing with the first status poll.
    id: updateDelay
    interval: 20000
    repeat: false
    running: root.checkForUpdates
    onTriggered: root.checkUpdate()
  }

  Timer {
    id: updateTimer
    interval: 86400000
    repeat: true
    running: root.checkForUpdates
    onTriggered: root.checkUpdate()
  }

  Timer {
    id: actionStatusTimer
    interval: 2200
    repeat: false
    onTriggered: {
      root.actionStatus = ""
      root.authenticating = ""
    }
  }

  Process {
    id: capsProcess
    running: false
    command: []
    stdout: StdioCollector { id: capsStdout; waitForEnd: true }
    onExited: function(exitCode) {
      var caps = Model.parseWhich(capsStdout.text, ["twingate-notifier", "twingate", "systemctl"])
      root.notifierInstalled = caps["twingate-notifier"]
      root.cliInstalled = caps["twingate"]
      root.systemctlInstalled = caps["systemctl"]
      root.probed = true
      if (!root.notifierInstalled) {
        root.conn = Model.CONN_UNKNOWN
        root.lastError = "Twingate client is not installed or not on PATH"
        return
      }
      root.refreshStatus(true)
      root.refreshResources(true)
      root.discover()
      root.probeAuthPrompts()
    }
  }

  Process {
    id: notifierProcess
    running: false
    command: []
    stdout: CappedStdout { id: notifierStdout }
    stderr: StdioCollector { id: notifierStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var stdout = String(notifierStdout.text || "")
      var stderr = String(notifierStderr.text || "")
      var kind = root._kind
      root._kind = ""

      if (notifierStdout.truncated) {
        root.lastError = "twingate-notifier " + kind + " produced more output than the panel will read"
        root.pumpQueue()
        return
      }

      if (kind === "status") {
        if (exitCode === 0 && stdout.trim() !== "") root.applyStatus(Model.parseStatus(stdout))
        else {
          // An empty reply means the daemon accepted the IPC command and
          // answered nothing, which is indistinguishable from a stopped unit.
          root._pendingNotifierError = stderr.trim()
          if (root.systemctlInstalled && !unitProcess.running) {
            unitProcess.command = ["systemctl", "is-active", "twingate.service"]
            unitProcess.running = true
          }
        }
      } else if (kind === "resources") {
        if (exitCode === 0 && stdout.trim() !== "") root.applyResources(stdout)
      } else if (kind === "auth") {
        if (exitCode !== 0) {
          root.lastError = (stderr.trim() || stdout.trim() || "Authentication failed").substring(0, 140)
          root.actionStatus = root.lastError
          actionStatusTimer.restart()
        }
        root.settle()
      }
      root.pumpQueue()
    }
  }

  Process {
    id: unitProcess
    running: false
    command: []
    stdout: StdioCollector { id: unitStdout; waitForEnd: true }
    onExited: function(exitCode) {
      // is-active exits non-zero for a stopped unit, so the word decides.
      var word = String(unitStdout.text || "").trim()
      if (Model.isTransitional(word)) return
      if (word === "active") {
        root.conn = Model.CONN_UNKNOWN
        root.lastError = root._pendingNotifierError || "daemon is not answering status requests"
      } else if (word !== "") {
        root.conn = Model.CONN_STOPPED
        root.lastError = ""
        root.resources = []
        root.rawResources = []
        root.allResources = []
        if (root._desired === 0) root._desired = -1
      } else {
        // systemctl never answered, which says nothing about the unit.
        // Reporting "stopped" here would offer Connect over a live tunnel.
        root.conn = Model.CONN_UNKNOWN
        root.lastError = root._pendingNotifierError || "cannot read the state of twingate.service"
      }
      root._pendingNotifierError = ""
      root.announce()
    }
  }

  Process {
    id: controlProcess
    running: false
    command: []
    stdout: StdioCollector { id: controlStdout; waitForEnd: true }
    stderr: StdioCollector { id: controlStderr; waitForEnd: true }
    onExited: function(exitCode) {
      controlWatchdog.stop()
      var stderr = String(controlStderr.text || "")
      var stdout = String(controlStdout.text || "")
      if (exitCode !== 0) {
        // A cancelled polkit dialog exits non-zero; the switch must stop lying.
        root._desired = -1
        desiredGuard.stop()
        root.lastError = (stderr.trim() || stdout.trim() || "Could not change the Twingate service").substring(0, 140)
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      root.settle()
    }
  }

  Process {
    id: discoverProcess
    running: false
    command: []
    stdout: StdioCollector { id: discoverStdout; waitForEnd: true }
    onExited: function(exitCode) {
      var stdout = String(discoverStdout.text || "")
      var kind = root._discoverKind
      root._discoverKind = ""
      if (exitCode === 0) {
        if (kind === "exit-nodes") root.exitNodes = Model.parseExitNodes(stdout)
        else root.accounts = Model.parseAccounts(stdout)
      }
      root.pumpDiscover()
    }
  }

  Process {
    id: authProbeProcess
    running: false
    command: []
    stdout: StdioCollector { id: authProbeStdout; waitForEnd: true }
    onExited: function(exitCode) {
      var word = String(authProbeStdout.text || "").trim()
      if (Model.isTransitional(word)) return
      root.authPromptsActive = word === "active"
      root.authPromptsProbed = true
    }
  }

  Process {
    id: authActionProcess
    running: false
    command: []
    stderr: StdioCollector { id: authActionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.lastError = (String(authActionStderr.text || "").trim()
          || "Could not start Twingate notifications").substring(0, 140)
        root.actionStatus = root.lastError
      } else {
        root.actionStatus = "Twingate notifications running"
      }
      actionStatusTimer.restart()
      root.probeAuthPrompts()
    }
  }

  Process {
    id: updateProcess
    running: false
    command: []
    stdout: StdioCollector { id: updateStdout; waitForEnd: true }
    onExited: function(exitCode) {
      var n = parseInt(String(updateStdout.text || "").trim(), 10)
      root.updateCount = isFinite(n) && n > 0 ? n : 0
    }
  }

  Process {
    id: cliActionProcess
    running: false
    command: []
    stdout: StdioCollector { id: cliActionStdout; waitForEnd: true }
    stderr: StdioCollector { id: cliActionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var stderr = String(cliActionStderr.text || "")
      var stdout = String(cliActionStdout.text || "")
      if (exitCode !== 0) {
        root.lastError = (stderr.trim() || stdout.trim() || "Twingate command failed").substring(0, 140)
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      }
      root.switchingExitNode = ""
      root.switchingAccount = ""
      root.discover()
      root.settle()
    }
  }
}
