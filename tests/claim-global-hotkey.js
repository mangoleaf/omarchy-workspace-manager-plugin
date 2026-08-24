// node tests/claim-global-hotkey.js
// The capture handler calls claimGlobalHotkey, and a call with no function
// behind it throws mid-handler and takes the autosave down with it — which is
// how changing a hotkey stopped reaching workspaces.conf. Guards that the
// function exists, is reachable under the name the handler uses, and hands a
// combination to one action at a time.
const fs = require("fs")
const assert = require("assert")

const src = fs.readFileSync(__dirname + "/../Editor.qml", "utf8")

const m = src.match(/\n  function claimGlobalHotkey\(action, keys\) \{[\s\S]*?\n  \}/)
assert.ok(m, "claimGlobalHotkey() is missing from Editor.qml — the capture handler calls it")

// Every win.<name>() the file calls has to be a function the file declares,
// or it throws the moment that line runs.
const declared = new Set([...src.matchAll(/^\s*function (\w+)\(/gm)].map((d) => d[1]))
for (const [, name] of src.matchAll(/\bwin\.(\w+)\(/g)) {
  assert.ok(declared.has(name), `Editor.qml calls win.${name}() but never declares it`)
}

const load = new Function("win", `${m[0]}\n win.claimGlobalHotkey = claimGlobalHotkey;`)

function editor(rename, jump, editor_) {
  const win = { renameKey: rename, jumpKey: jump, editorKey: editor_, conflictNote: "", noteExpires: false }
  load(win)
  return win
}

// Jump takes a combination the rename hotkey holds: rename gives it up.
let win = editor("SUPER + SHIFT + F2", "SUPER + SHIFT + grave", "SUPER + SHIFT + F4")
win.claimGlobalHotkey("jump", "SUPER + SHIFT + F2")
assert.strictEqual(win.renameKey, "")
assert.strictEqual(win.jumpKey, "SUPER + SHIFT + grave", "the claiming action keeps whatever it had")
assert.match(win.conflictNote, /Rename/)
assert.strictEqual(win.noteExpires, true, "the steal notice is a passing remark")

// A combination nothing else holds disturbs no one.
win = editor("SUPER + SHIFT + F2", "SUPER + SHIFT + grave", "SUPER + SHIFT + F4")
win.claimGlobalHotkey("jump", "SUPER + SHIFT + F3")
assert.deepStrictEqual([win.renameKey, win.editorKey], ["SUPER + SHIFT + F2", "SUPER + SHIFT + F4"])
assert.strictEqual(win.conflictNote, "")

// Clearing a hotkey is not a claim on every other empty one.
win = editor("", "SUPER + SHIFT + grave", "")
win.claimGlobalHotkey("jump", "")
assert.deepStrictEqual([win.renameKey, win.editorKey], ["", ""])
assert.strictEqual(win.conflictNote, "")

console.log("ok — 3 cases + no undefined win.*() calls")
