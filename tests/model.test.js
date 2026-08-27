const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const path = require("node:path")

const M = require("../Model.js")

const NOW = 1800000000
const raw = fs.readFileSync(path.join(__dirname, "fixtures", "resources.json"), "utf8")
const byName = (list) => Object.fromEntries(list.map((r) => [r.name, r]))

test("parseStatus maps the daemon's first line", () => {
  assert.equal(M.parseStatus("Online: User\ninternet_security: 0"), M.CONN_ONLINE)
  assert.equal(M.parseStatus("offline"), M.CONN_OFFLINE)
  assert.equal(M.parseStatus("not-configured"), M.CONN_NOT_CONFIGURED)
  assert.equal(M.parseStatus("authenticating: x"), M.CONN_AUTHENTICATING)
  assert.equal(M.parseStatus("\n\n  Online: User"), M.CONN_ONLINE)
  assert.equal(M.parseStatus("something else"), M.CONN_UNKNOWN)
  assert.equal(M.parseStatus(""), M.CONN_UNKNOWN)
  assert.equal(M.parseStatus(null), M.CONN_UNKNOWN)
})

test("isTransitional matches only systemd's in-between words", () => {
  for (const w of ["activating", "deactivating", "reloading"]) assert.ok(M.isTransitional(w))
  for (const w of ["active", "inactive", "failed", ""]) assert.ok(!M.isTransitional(w))
})

test("iconMode ignores never-authorized resources", () => {
  // A network can hold permanently locked resources. Warning on those leaves the
  // icon lit forever, so only a lapsed authorization counts as a fault.
  assert.equal(M.iconMode(M.CONN_ONLINE, false, 0), M.MODE_OK)
  assert.equal(M.iconMode(M.CONN_ONLINE, false, 2), M.MODE_WARN)
  assert.equal(M.iconMode(M.CONN_ONLINE, true, 0), M.MODE_WARN)
  assert.equal(M.iconMode(M.CONN_OFFLINE, false, 0), M.MODE_OFF)
  assert.equal(M.iconMode(M.CONN_STOPPED, false, 0), M.MODE_OFF)
  assert.equal(M.iconMode(M.CONN_UNKNOWN, false, 0), M.MODE_WARN)
  assert.equal(M.iconMode(M.CONN_NOT_CONFIGURED, false, 0), M.MODE_WARN)
  assert.equal(M.iconMode(M.CONN_AUTHENTICATING, false, 0), M.MODE_WARN)
})

test("isLocked reads the flow id, not the expiry", () => {
  assert.ok(M.isLocked({ auth_flow_id: "locked-rid:42", auth_expires_at: 0 }))
  assert.ok(!M.isLocked({ auth_flow_id: "9000", auth_expires_at: 0 }))
  assert.ok(!M.isLocked({ auth_flow_id: "9000", auth_expires_at: 123 }))
  // Only an absent flow id falls back to the expiry.
  assert.ok(M.isLocked({ auth_expires_at: 0 }))
  assert.ok(!M.isLocked({ auth_expires_at: 123 }))
})

test("a zero expiry on a session-policy resource is authorized, not locked", () => {
  // Every resource on the network this was built against was in exactly this
  // shape: covered by the account session, with no expiry reported yet. Reading
  // the zero as "unauthorized" would flag the whole network.
  const parsed = M.parseResources(JSON.stringify({
    resources: [{
      name: "shared-session", address: "app.example", auth_flow_id: "9000",
      auth_expires_at: 0, auth_state: "none", can_open_in_browser: true,
      client_visibility: 1,
    }],
  }), false)
  assert.ok(parsed.ok)
  const [r] = M.decorate(parsed.resources, NOW)
  assert.equal(r.locked, false)
  assert.equal(r.needsAuth, false)
  assert.equal(r.expired, false)
  assert.equal(r.authorized, true)
  assert.equal(r.state, "ok")
  assert.equal(r.expiryText, "Authorized")
})

test("humanize rounds instead of truncating", () => {
  assert.equal(M.humanize(30), "less than a minute")
  assert.equal(M.humanize(90), "2 minutes")
  assert.equal(M.humanize(3599), "1 hour")
  assert.equal(M.humanize(3600), "1 hour")
  assert.equal(M.humanize(5400), "2 hours")
  // 47h59m must read as "2 days", matching what `twingate resources` prints.
  assert.equal(M.humanize(172740), "2 days")
  assert.equal(M.humanize(86400), "1 day")
})

test("parseResources separates hidden resources", () => {
  const visible = M.parseResources(raw, false)
  const all = M.parseResources(raw, true)
  assert.ok(visible.ok)
  assert.equal(visible.networkName, "Acme Corp")
  assert.equal(visible.userEmail, "you@example.com")
  assert.equal(visible.adminUrl, "https://acme.twingate.com")
  assert.equal(all.resources.length, visible.resources.length + 1)
  assert.equal(all.resources.filter(M.isHidden).length, 1)
  assert.ok(!visible.resources.some(M.isHidden))
})

test("parseResources takes the email from a user object or a bare string", () => {
  assert.equal(M.parseResources(JSON.stringify({ user: { email: "a@b.c" }, resources: [] }), false).userEmail, "a@b.c")
  assert.equal(M.parseResources(JSON.stringify({ user: "a@b.c", resources: [] }), false).userEmail, "a@b.c")
})

test("parseResources reports bad input instead of throwing", () => {
  for (const bad of ["", "not json", "[]", "null", "42"]) {
    const out = M.parseResources(bad, false)
    assert.equal(out.ok, false, `expected failure for ${JSON.stringify(bad)}`)
    assert.deepEqual(out.resources, [])
  }
})

test("browsable honours the flag, the scheme, and wildcards", () => {
  const r = byName(M.parseResources(raw, true).resources)
  assert.equal(r["grafana"].browsable, true)
  assert.equal(r["grafana"].browseUrl, "https://grafana.acme.example")
  // No open_url, so the address is used -- but a wildcard is not a host.
  assert.equal(r["staging-services"].browsable, false)
  assert.equal(r["prod-postgres"].browsable, false)
  assert.equal(r["office-printer"].browsable, false)
  assert.equal(r["internal-wiki"].browsable, true)
  assert.equal(r["internal-wiki"].browseUrl, "https://wiki.int.acme.example")
})

test("decorate classifies each resource and sorts attention first", () => {
  const d = M.decorate(M.parseResources(raw, false).resources, NOW)
  const r = byName(d)
  assert.equal(r["prod-postgres"].state, "locked")
  assert.equal(r["prod-vault"].state, "locked")
  assert.equal(r["legacy-jenkins"].state, "expired")
  assert.equal(r["grafana"].state, "ok")
  assert.equal(r["grafana"].expiryText, "Auth expires in 2 days")
  assert.equal(r["internal-wiki"].expiryText, "Auth expires in 5 hours")
  assert.equal(r["legacy-jenkins"].expiryText, "Auth expired")
  assert.equal(r["prod-postgres"].expiryText, "Not authorized")

  const ranks = d.map((x) => ["locked", "expired", "pending", "ok"].indexOf(x.state))
  assert.deepEqual(ranks, [...ranks].sort((a, b) => a - b), "states must be grouped by urgency")
  const locked = d.filter((x) => x.state === "locked").map((x) => x.name)
  assert.deepEqual(locked, [...locked].sort(), "ties break alphabetically")
})

test("partition pins anything needing attention", () => {
  const d = M.decorate(M.parseResources(raw, false).resources, NOW)
  const { needsAuth, reachable } = M.partition(d)
  assert.deepEqual(needsAuth.map((r) => r.name), ["prod-postgres", "prod-vault", "legacy-jenkins"])
  assert.deepEqual(reachable.map((r) => r.name), ["grafana", "internal-wiki", "staging-services"])
  assert.equal(M.needsAuthCount(d), 2)
  assert.equal(M.expiredCount(d), 1)
})

test("filterResources matches name and address, and caps", () => {
  const d = M.decorate(M.parseResources(raw, false).resources, NOW)
  assert.deepEqual(M.filterResources(d, "vault", 0).rows.map((r) => r.name), ["prod-vault"])
  assert.deepEqual(M.filterResources(d, "wiki.int", 0).rows.map((r) => r.name), ["internal-wiki"])
  assert.deepEqual(M.filterResources(d, "PROD-", 0).rows.map((r) => r.name), ["prod-postgres", "prod-vault"])
  assert.equal(M.filterResources(d, "nothing-matches", 0).rows.length, 0)

  const capped = M.filterResources(d, "", 2)
  assert.equal(capped.rows.length, 2)
  assert.equal(capped.total, d.length)
  assert.equal(capped.truncated, true)
  assert.equal(M.filterResources(d, "", 0).truncated, false)
  assert.equal(M.filterResources(d, "", 0).rows.length, d.length)
})

test("sessionExpiryText reports the nearest live authorization", () => {
  const d = M.decorate(M.parseResources(raw, false).resources, NOW)
  assert.equal(M.sessionExpiryText(d, NOW), "Session expires in 5 hours")
  const noExpiry = M.decorate(M.parseResources(JSON.stringify({
    resources: [{ name: "a", address: "a.example", auth_flow_id: "9000", auth_expires_at: 0, client_visibility: 1 }],
  }), false).resources, NOW)
  assert.equal(M.sessionExpiryText(noExpiry, NOW), "")
  assert.equal(M.soonestExpiryAt(d, NOW), NOW + 3600 * 5)
})

test("parseExitNodes takes the node name from the first column", () => {
  // A second column is a status, not a label -- reading it made every node "-".
  assert.deepEqual(M.parseExitNodes("NAME\tSTATUS\nfrankfurt-1\t-\nlondon-1\t-\n"),
    [{ name: "frankfurt-1", active: false }, { name: "london-1", active: false }])
  assert.deepEqual(M.parseExitNodes("No exit nodes are available"), [])
  assert.deepEqual(M.parseExitNodes(""), [])
  assert.deepEqual(M.parseExitNodes("NAME\nberlin-1 *\n"), [{ name: "berlin-1 *", active: true }])
})

test("parseAccounts skips the header row", () => {
  const out = M.parseAccounts("EMAIL\tNETWORK\tNETWORK URL\nyou@example.com\tAcme Corp\tacme.twingate.com\n")
  assert.deepEqual(out, [{ email: "you@example.com", network: "Acme Corp", networkUrl: "acme.twingate.com" }])
  assert.deepEqual(M.parseAccounts(""), [])
  assert.deepEqual(M.parseAccounts("EMAIL\tNETWORK\tNETWORK URL\n"), [])
})

test("parseWhich reads stdout, not the exit code", () => {
  // `which a b c` exits non-zero when any argument is missing but still prints
  // the ones it found.
  assert.deepEqual(M.parseWhich("/usr/bin/twingate-notifier\n/usr/bin/twingate\n/usr/bin/systemctl\n",
    ["twingate-notifier", "twingate", "systemctl"]),
    { "twingate-notifier": true, twingate: true, systemctl: true })
  assert.deepEqual(M.parseWhich("/usr/bin/twingate-notifier\n", ["twingate-notifier", "twingate"]),
    { "twingate-notifier": true, twingate: false })
  assert.deepEqual(M.parseWhich("", ["twingate-notifier"]), { "twingate-notifier": false })
})

test("statusLabel words every state", () => {
  assert.equal(M.statusLabel(M.CONN_ONLINE, false), "Online")
  assert.equal(M.statusLabel(M.CONN_OFFLINE, false), "Offline")
  assert.equal(M.statusLabel(M.CONN_STOPPED, false), "Service stopped")
  assert.equal(M.statusLabel(M.CONN_NOT_CONFIGURED, false), "Not configured")
  assert.equal(M.statusLabel(M.CONN_AUTHENTICATING, false), "Authenticating")
  assert.equal(M.statusLabel(M.CONN_UNKNOWN, false), "Unknown")
  assert.equal(M.statusLabel(M.CONN_ONLINE, true), "Unavailable")
})

test("isWebUrl only passes http and https", () => {
  for (const u of ["http://a.example", "https://a.example", "HTTPS://A.EXAMPLE"]) assert.ok(M.isWebUrl(u))
  for (const u of ["ftp://a.example", "file:///etc/passwd", "a.example", "", null]) assert.ok(!M.isWebUrl(u))
})

test("recentResources resolves names in order and drops what is gone", () => {
  const d = M.decorate(M.parseResources(raw, false).resources, NOW)
  const names = ["staging-services", "revoked-host", "grafana"]
  assert.deepEqual(M.recentResources(d, names, 5).map((r) => r.name), ["staging-services", "grafana"])
  assert.deepEqual(M.recentResources(d, names, 1).map((r) => r.name), ["staging-services"])
  assert.deepEqual(M.recentResources(d, [], 5), [])
  assert.deepEqual(M.recentResources(d, ["grafana", "grafana"], 5).map((r) => r.name), ["grafana"])
})

test("pushRecent puts the newest first, dedupes, and caps", () => {
  assert.deepEqual(M.pushRecent(["b", "c"], "a", 5), ["a", "b", "c"])
  assert.deepEqual(M.pushRecent(["b", "c"], "c", 5), ["c", "b"])
  assert.deepEqual(M.pushRecent([], "a", 5), ["a"])
  assert.deepEqual(M.pushRecent(["b", "c", "d", "e", "f"], "a", 5), ["a", "b", "c", "d", "e"])
  assert.deepEqual(M.pushRecent(["a", "b"], "a", 5), ["a", "b"])
})

test("excludeNames lifts rows out of the main list without reordering", () => {
  const d = M.decorate(M.parseResources(raw, false).resources, NOW)
  const kept = M.excludeNames(d, ["grafana", "prod-vault"]).map((r) => r.name)
  assert.ok(!kept.includes("grafana"))
  assert.ok(!kept.includes("prod-vault"))
  assert.equal(kept.length, d.length - 2)
  assert.deepEqual(kept, d.map((r) => r.name).filter((n) => n !== "grafana" && n !== "prod-vault"))
  assert.deepEqual(M.excludeNames(d, []).map((r) => r.name), d.map((r) => r.name))
})

test("sessionExpiryText stays quiet unless re-authentication is due", () => {
  const authorized = (name) => ({
    name, address: name + ".example", auth_flow_id: "9000",
    auth_expires_at: 0, auth_state: "none", can_open_in_browser: true, client_visibility: 1,
  })
  const decode = (list) => M.decorate(M.parseResources(JSON.stringify({ resources: list }), false).resources, NOW)

  assert.equal(M.sessionExpiryText(decode([authorized("a")]), NOW), "")
  assert.equal(M.sessionExpiryText([], NOW), "")
  const lockedOnly = decode([{ ...authorized("b"), auth_flow_id: "locked-rid:1" }])
  assert.equal(M.sessionExpiryText(lockedOnly, NOW), "")
  const live = decode([{ ...authorized("c"), auth_expires_at: NOW + 3600 * 5 }])
  assert.equal(M.sessionExpiryText(live, NOW), "Session expires in 5 hours")
  const past = decode([{ ...authorized("d"), auth_expires_at: NOW - 60 }])
  assert.equal(M.sessionExpiryText(past, NOW), "Session expired")
})

test("a live authorization means the session is not expired", () => {
  const base = { auth_flow_id: "9000", auth_state: "none", can_open_in_browser: true, client_visibility: 1 }
  const decode = (list) => M.decorate(M.parseResources(JSON.stringify({ resources: list }), false).resources, NOW)

  // One lapsed, one live: the live one proves the session works.
  const mixed = decode([
    { name: "stale", address: "s.example", auth_expires_at: NOW - 3600, ...base },
    { name: "live", address: "l.example", auth_expires_at: NOW + 3600 * 2, ...base },
  ])
  assert.equal(M.sessionExpiryText(mixed, NOW), "Session expires in 2 hours")

  const allStale = decode([{ name: "stale", address: "s.example", auth_expires_at: NOW - 3600, ...base }])
  assert.equal(M.sessionExpiryText(allStale, NOW), "Session expired")
})

test("plainText strips what Qt would treat as markup", () => {
  assert.equal(M.plainText("<img src=x onerror=y>"), "img src=x onerror=y")
  assert.equal(M.plainText("prod-db.example"), "prod-db.example")
  assert.equal(M.plainText("a\u0001b\u007fc"), "a b c")
  assert.equal(M.plainText(null), "")
  assert.equal(M.plainText(undefined), "")
})

test("parseUpdateCheck only reports a checkout that is strictly behind", () => {
  assert.deepEqual(M.parseUpdateCheck("3 abc123"), { count: 3, rev: "abc123" })
  assert.deepEqual(M.parseUpdateCheck("0"), { count: 0, rev: "" })
  assert.deepEqual(M.parseUpdateCheck(""), { count: 0, rev: "" })
  assert.deepEqual(M.parseUpdateCheck("dev"), { count: 0, rev: "" })
  assert.deepEqual(M.parseUpdateCheck(null), { count: 0, rev: "" })
  assert.deepEqual(M.parseUpdateCheck("  2   deadbeef  "), { count: 2, rev: "deadbeef" })
})
