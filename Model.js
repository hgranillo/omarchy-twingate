var CONN_ONLINE = "online"
var CONN_OFFLINE = "offline"
var CONN_STOPPED = "stopped"
var CONN_NOT_CONFIGURED = "not-configured"
var CONN_AUTHENTICATING = "authenticating"
var CONN_UNKNOWN = "unknown"

var MODE_OK = "ok"
var MODE_OFF = "off"
var MODE_WARN = "warn"

var LOCKED_FLOW_PREFIX = "locked-rid:"

// client_visibility 1 is exactly the set `twingate resources` prints; 2 is the
// set it only prints under --all.
var VISIBLE = 1

// `systemctl is-active` prints one of these while the unit changes state.
var TRANSITIONAL = ["activating", "deactivating", "reloading"]

var STATUS_WORDS = {
  "online": CONN_ONLINE,
  "offline": CONN_OFFLINE,
  "not-configured": CONN_NOT_CONFIGURED,
  "authenticating": CONN_AUTHENTICATING
}

// `which a b c` exits non-zero when any argument is missing but still prints
// the ones it found, so the capability probe reads stdout, not the exit code.
function parseWhich(raw, names) {
  var found = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "") continue
    var base = line.split("/").pop()
    found[base] = true
  }
  var out = {}
  for (var n = 0; n < names.length; n++) out[names[n]] = found[names[n]] === true
  return out
}

function firstLine(text) {
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line !== "") return line
  }
  return ""
}

function parseStatus(text) {
  var line = firstLine(text)
  if (line === "") return CONN_UNKNOWN
  var word = line.split(":")[0].trim().toLowerCase()
  var conn = STATUS_WORDS[word]
  return conn === undefined ? CONN_UNKNOWN : conn
}

function isTransitional(word) {
  return TRANSITIONAL.indexOf(String(word || "").trim()) !== -1
}

function statusLabel(conn, error) {
  if (error) return "Unavailable"
  if (conn === CONN_ONLINE) return "Online"
  if (conn === CONN_OFFLINE) return "Offline"
  if (conn === CONN_STOPPED) return "Service stopped"
  if (conn === CONN_NOT_CONFIGURED) return "Not configured"
  if (conn === CONN_AUTHENTICATING) return "Authenticating"
  return "Unknown"
}

// Locked resources are deliberately absent: a network can hold resources that
// are never authorized, and treating those as a fault leaves the icon warning
// permanently, which makes it signal nothing.
function iconMode(conn, hasError, expiredCount) {
  if (hasError) return MODE_WARN
  if (conn === CONN_UNKNOWN || conn === CONN_NOT_CONFIGURED || conn === CONN_AUTHENTICATING) return MODE_WARN
  if (conn === CONN_ONLINE) return expiredCount > 0 ? MODE_WARN : MODE_OK
  return MODE_OFF
}

function isWebUrl(url) {
  return /^https?:\/\//i.test(String(url || ""))
}

// Twingate publishes no explicit flag. The `locked-rid:` prefix on auth_flow_id
// is the explicit signal and matches the blank AUTH STATUS column that
// `twingate resources` prints; a zero auth_expires_at is the fallback only for
// entries that carry no flow id at all.
function isLocked(entry) {
  var flow = String(entry.auth_flow_id || "")
  if (flow !== "") return flow.indexOf(LOCKED_FLOW_PREFIX) === 0
  return !entry.auth_expires_at
}

function count(value, unit) {
  return value === 1 ? value + " " + unit : value + " " + unit + "s"
}

// Round to the nearest unit rather than truncating. Truncating reports a token
// that expires in 47h59m as "1 day", where `twingate resources` says "2 days".
function humanize(seconds) {
  if (seconds < 60) return "less than a minute"
  var minutes = Math.round(seconds / 60)
  if (minutes < 60) return count(minutes, "minute")
  var hours = Math.round(seconds / 3600)
  if (hours < 24) return count(hours, "hour")
  return count(Math.round(seconds / 86400), "day")
}

function resourceFrom(entry) {
  var openUrl = String(entry.open_url || "")
  var address = String(entry.address || "")
  var adminUrl = String(entry.admin_url || "")
  var canOpen = entry.can_open_in_browser === undefined ? true : !!entry.can_open_in_browser
  var browsable = false
  if (canOpen) {
    // A wildcard address such as `*.prd.example.com` is not a host, so opening
    // it resolves to nothing useful even when Twingate marks it openable.
    browsable = openUrl !== "" ? isWebUrl(openUrl) : (address !== "" && address.indexOf("*") === -1)
  }
  return {
    name: String(entry.name || "(unnamed)"),
    address: address,
    locked: isLocked(entry),
    expiresAt: parseInt(entry.auth_expires_at || 0, 10) || 0,
    adminLink: isWebUrl(adminUrl) ? adminUrl : "",
    openUrl: openUrl,
    authState: String(entry.auth_state || ""),
    visibility: parseInt(entry.client_visibility || VISIBLE, 10) || VISIBLE,
    pending: String(entry.auth_state || "") === "pending",
    browsable: browsable,
    browseUrl: isWebUrl(openUrl) ? openUrl : "https://" + address
  }
}

function isHidden(resource) {
  return resource.visibility !== VISIBLE
}

function decorate(resources, nowSec) {
  var out = []
  for (var i = 0; i < resources.length; i++) {
    var r = resources[i]
    var expired = !r.locked && r.expiresAt > 0 && r.expiresAt <= nowSec
    // A pending flow is already running, so it is not waiting on the user.
    var needsAuth = r.locked && !r.pending
    var state = needsAuth ? "locked" : (expired ? "expired" : (r.pending ? "pending" : "ok"))
    var text
    if (r.pending) text = "Pending"
    else if (r.locked) text = "Not authorized"
    else if (r.expiresAt <= 0) text = "Authorized"
    else if (r.expiresAt <= nowSec) text = "Auth expired"
    else text = "Auth expires in " + humanize(Math.round(r.expiresAt - nowSec))

    var copy = {}
    for (var key in r) copy[key] = r[key]
    copy.expired = expired
    copy.needsAuth = needsAuth
    copy.authorized = !r.locked && !expired
    copy.state = state
    copy.expiryText = text
    out.push(copy)
  }
  return sortResources(out)
}

var STATE_RANK = { "locked": 0, "expired": 1, "pending": 2, "ok": 3 }

function sortResources(resources) {
  return resources.slice().sort(function (a, b) {
    var rank = STATE_RANK[a.state] - STATE_RANK[b.state]
    if (rank !== 0) return rank
    var an = a.name.toLowerCase()
    var bn = b.name.toLowerCase()
    return an < bn ? -1 : (an > bn ? 1 : 0)
  })
}

function parseResources(text, includeHidden) {
  var payload
  try {
    payload = JSON.parse(String(text || ""))
  } catch (e) {
    return { ok: false, error: String(e), networkName: "", userEmail: "", adminUrl: "", resources: [] }
  }
  if (!payload || typeof payload !== "object" || payload instanceof Array)
    return { ok: false, error: "expected a JSON object", networkName: "", userEmail: "", adminUrl: "", resources: [] }

  var entries = payload.resources instanceof Array ? payload.resources : []
  var resources = []
  for (var i = 0; i < entries.length; i++) {
    if (!entries[i] || typeof entries[i] !== "object") continue
    var r = resourceFrom(entries[i])
    if (includeHidden !== true && r.visibility !== VISIBLE) continue
    resources.push(r)
  }

  var user = payload.user
  var email = ""
  if (user && typeof user === "object") email = String(user.email || "")
  else if (user) email = String(user)

  return {
    ok: true,
    error: "",
    networkName: String(payload.network_name || ""),
    userEmail: email,
    adminUrl: isWebUrl(payload.admin_url) ? String(payload.admin_url) : "",
    resources: resources
  }
}

function resourceGlyph(resource) {
  if (resource.state === "pending") return "\u{F13AB}"
  if (resource.state === "locked") return "\u{F033E}"
  if (resource.state === "expired") return "\u{F0026}"
  return "\u{F012C}"
}

function partition(resources) {
  var needsAuth = []
  var reachable = []
  for (var i = 0; i < resources.length; i++) {
    var r = resources[i]
    if (r.needsAuth || r.expired || r.pending) needsAuth.push(r)
    else reachable.push(r)
  }
  return { needsAuth: needsAuth, reachable: reachable }
}

// A name that no longer resolves is dropped: access can be revoked between
// sessions.
function recentResources(resources, names, cap) {
  var byName = {}
  for (var i = 0; i < resources.length; i++) byName[resources[i].name] = resources[i]
  var out = []
  var seen = {}
  for (var n = 0; n < names.length && out.length < cap; n++) {
    var name = String(names[n] || "")
    if (name === "" || seen[name]) continue
    if (byName[name] === undefined) continue
    seen[name] = true
    out.push(byName[name])
  }
  return out
}

function pushRecent(names, name, cap) {
  var next = [String(name)]
  for (var i = 0; i < names.length && next.length < cap; i++) {
    var existing = String(names[i] || "")
    if (existing !== "" && existing !== name && next.indexOf(existing) === -1) next.push(existing)
  }
  return next
}

function excludeNames(resources, names) {
  if (names.length === 0) return resources
  var drop = {}
  for (var n = 0; n < names.length; n++) drop[names[n]] = true
  var out = []
  for (var i = 0; i < resources.length; i++) if (!drop[resources[i].name]) out.push(resources[i])
  return out
}

function filterResources(resources, query, cap) {
  var q = String(query || "").trim().toLowerCase()
  var matched = []
  for (var i = 0; i < resources.length; i++) {
    var r = resources[i]
    if (q === "" || r.name.toLowerCase().indexOf(q) !== -1 || r.address.toLowerCase().indexOf(q) !== -1)
      matched.push(r)
  }
  var limit = cap > 0 ? cap : matched.length
  return {
    rows: matched.slice(0, limit),
    total: matched.length,
    truncated: matched.length > limit
  }
}

// Non-locked resources share the account session policy flow, so the nearest
// expiry among them is when the Twingate session itself lapses.
function soonestExpiryAt(resources, nowSec) {
  var best = 0
  for (var i = 0; i < resources.length; i++) {
    var r = resources[i]
    if (r.locked || r.expiresAt <= nowSec) continue
    if (best === 0 || r.expiresAt < best) best = r.expiresAt
  }
  return best
}

function sessionExpiryText(resources, nowSec) {
  var at = soonestExpiryAt(resources, nowSec)
  if (at > 0) return "Session expires in " + humanize(Math.round(at - nowSec))
  // auth_expires_at is 0 on every resource when no policy requires timed
  // re-authentication, which is the common case and says nothing worth a line.
  for (var i = 0; i < resources.length; i++)
    if (!resources[i].locked && resources[i].expiresAt > 0) return "Session expired"
  return ""
}

function expiredCount(resources) {
  var n = 0
  for (var i = 0; i < resources.length; i++) if (resources[i].expired) n++
  return n
}

function needsAuthCount(resources) {
  var n = 0
  for (var i = 0; i < resources.length; i++) if (resources[i].needsAuth) n++
  return n
}

function splitColumns(line) {
  var parts = String(line || "").split("\t")
  var out = []
  for (var i = 0; i < parts.length; i++) {
    var field = parts[i].trim()
    if (field !== "") out.push(field)
  }
  return out
}

function parseAccounts(text) {
  var lines = String(text || "").split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line.trim() === "") continue
    var cols = splitColumns(line)
    if (cols.length === 0) continue
    if (cols[0].toUpperCase() === "EMAIL") continue
    out.push({
      email: cols[0],
      network: cols.length > 1 ? cols[1] : "",
      networkUrl: cols.length > 2 ? cols[2] : ""
    })
  }
  return out
}

function parseExitNodes(text) {
  var raw = String(text || "")
  if (/no exit nodes are available/i.test(raw)) return []
  var lines = raw.split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line.trim() === "") continue
    var cols = splitColumns(line)
    if (cols.length === 0) continue
    var head = cols[0].toUpperCase()
    if (head === "NAME" || head === "EXIT NODE" || head === "ID") continue
    out.push({
      name: cols[0],
      active: /\*|\bactive\b|\bcurrent\b/i.test(line)
    })
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    CONN_ONLINE: CONN_ONLINE, CONN_OFFLINE: CONN_OFFLINE, CONN_STOPPED: CONN_STOPPED,
    CONN_NOT_CONFIGURED: CONN_NOT_CONFIGURED, CONN_AUTHENTICATING: CONN_AUTHENTICATING, CONN_UNKNOWN: CONN_UNKNOWN,
    MODE_OK: MODE_OK, MODE_OFF: MODE_OFF, MODE_WARN: MODE_WARN,
    iconMode: iconMode,
    parseWhich: parseWhich,
    parseStatus: parseStatus, isTransitional: isTransitional, statusLabel: statusLabel,
    isWebUrl: isWebUrl, isLocked: isLocked, humanize: humanize,
    parseResources: parseResources, decorate: decorate,
    isHidden: isHidden,
    resourceGlyph: resourceGlyph,
    partition: partition, filterResources: filterResources,
    recentResources: recentResources, pushRecent: pushRecent, excludeNames: excludeNames,
    soonestExpiryAt: soonestExpiryAt, sessionExpiryText: sessionExpiryText, needsAuthCount: needsAuthCount, expiredCount: expiredCount,
    parseAccounts: parseAccounts, parseExitNodes: parseExitNodes
  }
}
