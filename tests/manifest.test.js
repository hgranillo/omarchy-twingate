const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const path = require("node:path")

const root = path.join(__dirname, "..")
const manifest = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"))

// Mirrors omarchy-plugin-validate, so a broken manifest fails here rather than
// silently refusing to load in the shell.
const ENTRY_POINT_FOR = {
  "bar-widget": "barWidget", bar: "bar", menu: "menu",
  overlay: "overlay", panel: "panel", service: "service",
}

test("schemaVersion is the number 1", () => {
  assert.strictEqual(manifest.schemaVersion, 1)
})

test("required fields are present", () => {
  for (const field of ["id", "name", "version", "kinds", "entryPoints"]) {
    assert.ok(manifest[field] !== undefined, `missing ${field}`)
  }
  assert.ok(Array.isArray(manifest.kinds) && manifest.kinds.length > 0)
})

test("id is well formed and outside the reserved namespace", () => {
  assert.match(manifest.id, /^[A-Za-z0-9][A-Za-z0-9._-]*$/)
  assert.ok(!manifest.id.startsWith("omarchy."), "omarchy.* is reserved for first-party plugins")
})

test("version is semver", () => {
  assert.match(manifest.version, /^\d+\.\d+\.\d+$/)
})

test("every declared kind has an entry point that exists", () => {
  for (const kind of manifest.kinds) {
    const key = ENTRY_POINT_FOR[kind]
    assert.ok(key, `unknown kind: ${kind}`)
    const file = manifest.entryPoints[key]
    assert.ok(file, `kind ${kind} has no entryPoints.${key}`)
    assert.ok(fs.existsSync(path.join(root, file)), `entry point does not exist: ${file}`)
  }
})

test("entry points are safe relative paths", () => {
  for (const [key, file] of Object.entries(manifest.entryPoints)) {
    assert.ok(!file.startsWith("/"), `${key} must not be absolute`)
    assert.ok(!file.includes(".."), `${key} must not escape the plugin directory`)
    assert.ok(!file.includes("\n"), `${key} must not contain a newline`)
  }
})

test("barWidget defaultSection is a real section", () => {
  const section = manifest.barWidget?.defaultSection
  if (section !== undefined) assert.ok(["left", "center", "right"].includes(section))
})

test("every schema key has a matching default", () => {
  // The shell writes `defaults` into a fresh layout entry and drives the
  // settings form from `schema`; a key in one and not the other is a bug.
  const defaults = manifest.barWidget?.defaults ?? {}
  const schema = manifest.barWidget?.schema ?? []
  for (const entry of schema) {
    assert.ok(entry.key in defaults, `schema key ${entry.key} has no entry in defaults`)
    assert.strictEqual(entry.defaultValue, defaults[entry.key],
      `schema defaultValue for ${entry.key} disagrees with defaults`)
  }
  for (const key of Object.keys(defaults)) {
    assert.ok(schema.some((e) => e.key === key), `default ${key} is not in schema`)
  }
})

test("the plugin tree carries no symlinks", () => {
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (entry.name === ".git") continue
      const full = path.join(dir, entry.name)
      assert.ok(!entry.isSymbolicLink(), `symlinks are rejected by omarchy plugin validate: ${full}`)
      if (entry.isDirectory()) walk(full)
    }
  }
  walk(root)
})

test("the README shows the preview image the repo ships", () => {
  const readme = fs.readFileSync(path.join(root, "README.md"), "utf8")
  assert.ok(readme.includes("preview.png"))
  assert.ok(fs.existsSync(path.join(root, "preview.png")))
})
