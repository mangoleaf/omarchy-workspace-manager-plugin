// node tests/text-plain-format.js
// A Text item defaults to Text.AutoText, which sniffs its string and renders
// anything that looks like markup as rich text — and rich text loads <img>,
// including from a remote URL. Window titles, app classes and monitor names
// are set by whatever owns the window, so a web page can put markup in its own
// title and have the shell fetch a stranger's URL when the switcher opens.
// Every Text item declares the format instead of guessing it. The rule is all
// of them rather than only the ones known to show untrusted text: working out
// which strings are attacker-controlled is the reasoning that fails.
const fs = require("fs")
const path = require("path")
const assert = require("assert")

const root = path.join(__dirname, "..")
const files = fs.readdirSync(root).filter((f) => f.endsWith(".qml")).sort()
assert.ok(files.length > 0, "no QML files found")

const offenders = []
let checked = 0

for (const file of files) {
  const lines = fs.readFileSync(path.join(root, file), "utf8").split("\n")
  lines.forEach((line, i) => {
    if (!/^\s*Text \{/.test(line)) return
    checked++
    // Inline form declares it on the same line, block form on the next.
    const declared = /textFormat:\s*Text\.PlainText/.test(line)
      || /textFormat:\s*Text\.PlainText/.test(lines[i + 1] || "")
    if (!declared) offenders.push(`${file}:${i + 1}`)
  })
}

assert.deepStrictEqual(offenders, [],
  `Text items without textFormat: Text.PlainText:\n  ${offenders.join("\n  ")}`)

console.log(`ok — ${checked} Text items, all PlainText`)
