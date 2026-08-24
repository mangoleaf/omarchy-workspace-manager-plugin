// node tests/pick-app-moves-pin.js
// Guards the rule that an app pins to one workspace at a time: picking an app
// that is already pinned elsewhere has to move the tag, and has to match class
// names exactly so "signal" never strips "signal-desktop".
const fs = require("fs")
const assert = require("assert")

const src = fs.readFileSync(__dirname + "/../Editor.qml", "utf8")

function grab(name) {
  const m = src.match(new RegExp(`\\n  function ${name}\\([^)]*\\) \\{[\\s\\S]*?\\n  \\}`))
  assert.ok(m, `${name}() not found in Editor.qml — did its signature or indentation change?`)
  return m[0]
}

const load = new Function("win", `${grab("removeApp")}\n${grab("pickApp")}
  win.removeApp = removeApp; win.pickApp = pickApp;`)

function editor(apps, pickerRow) {
  const win = { rows: apps.map((a) => ({ apps: a })), appsPickerRow: pickerRow, touch() {} }
  load(win)
  return win
}

// Already pinned on row 0, picked for row 2: the tag moves.
let win = editor(["signal,firefox", "", "code"], 2)
win.pickApp("signal")
assert.deepStrictEqual(win.rows.map((r) => r.apps), ["firefox", "", "code,signal"])
assert.strictEqual(win.appsPickerRow, -1, "picker should close")

// Exact matches only: a longer class that merely starts the same is left alone.
win = editor(["signal-desktop", ""], 1)
win.pickApp("signal")
assert.deepStrictEqual(win.rows.map((r) => r.apps), ["signal-desktop", "signal"])

// Picking an app onto the row it already sits on is a no-op, not a duplicate.
win = editor(["signal,firefox"], 0)
win.pickApp("signal")
assert.deepStrictEqual(win.rows.map((r) => r.apps), ["signal,firefox"])

// Cancelled picker changes nothing.
win = editor(["signal"], -1)
win.pickApp("firefox")
assert.deepStrictEqual(win.rows.map((r) => r.apps), ["signal"])

console.log("ok — 4 cases")
