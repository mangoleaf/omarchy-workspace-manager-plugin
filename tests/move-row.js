// node tests/move-row.js
// Row order is the order the bars draw in, so a reorder that drops, duplicates
// or mangles a row changes what the user sees on screen. The drop lands in a
// gap rather than on a row, and gap numbering shifts when the dragged row is
// lifted out — that off-by-one is what this guards.
const fs = require("fs")
const assert = require("assert")

const src = fs.readFileSync(__dirname + "/../Editor.qml", "utf8")
const m = src.match(/\n  function moveRowToGap\(from, gap\) \{[\s\S]*?\n  \}/)
assert.ok(m, "moveRowToGap() is missing from Editor.qml — the row handle drops into it")

const load = new Function("win", `${m[0]}\n win.moveRowToGap = moveRowToGap;`)

function editor(labels) {
  const win = { rows: labels.map((l) => ({ label: l })), autosave() {} }
  load(win)
  return win
}
const order = (win) => win.rows.map((r) => r.label)

// Gap g is the space above row g. Dragging "a" into the gap below "c" —
// gap 3 — leaves it after c, not after d.
let win = editor(["a", "b", "c", "d"])
win.moveRowToGap(0, 3)
assert.deepStrictEqual(order(win), ["b", "c", "a", "d"])

// Dragged upward, where lifting the row out does not shift the target gap.
win = editor(["a", "b", "c", "d"])
win.moveRowToGap(3, 1)
assert.deepStrictEqual(order(win), ["a", "d", "b", "c"])

// The gap past the last row: the row goes to the end.
win = editor(["a", "b", "c"])
win.moveRowToGap(0, 3)
assert.deepStrictEqual(order(win), ["b", "c", "a"])

// The gap above the first row: the row goes to the front.
win = editor(["a", "b", "c"])
win.moveRowToGap(2, 0)
assert.deepStrictEqual(order(win), ["c", "a", "b"])

// Adjacent nudge downward — the case the off-by-one gets wrong if the lift
// is not accounted for. Gap 2 is below "b", so "a" ends up after it.
win = editor(["a", "b", "c"])
win.moveRowToGap(0, 2)
assert.deepStrictEqual(order(win), ["b", "a", "c"])

// Both gaps touching a row are that row's own place: dropping it back where
// it already is changes nothing, rather than shuffling it by one.
for (const gap of [1, 2]) {
  win = editor(["a", "b", "c"])
  win.moveRowToGap(1, gap)
  assert.deepStrictEqual(order(win), ["a", "b", "c"], `gap ${gap} is row 1's own place`)
}

// Off the ends: nothing moves and nothing is lost.
for (const [from, gap] of [[-1, 0], [3, 0], [0, -1], [0, 4]]) {
  win = editor(["a", "b", "c"])
  win.moveRowToGap(from, gap)
  assert.deepStrictEqual(order(win), ["a", "b", "c"], `moveRowToGap(${from}, ${gap}) should be a no-op`)
}

// The array is replaced rather than mutated in place, which is what makes the
// ListView re-read it — and every row still has to survive the trip.
win = editor(["a", "b", "c"])
const before = win.rows
win.moveRowToGap(0, 2)
assert.notStrictEqual(win.rows, before, "moveRowToGap must assign a new array")
assert.deepStrictEqual([...order(win)].sort(), ["a", "b", "c"])

console.log("ok — 12 cases")
