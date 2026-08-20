// node tests/strip-app-suffix.js
// Guards the one branch in TreeModel.js that rewrites what the user reads:
// dropping a title's trailing app name is only safe while it drops the app
// name and nothing else.
const fs = require("fs")
const assert = require("assert")

const src = fs.readFileSync(__dirname + "/../TreeModel.js", "utf8").replace(".pragma library", "")
const strip = new Function(src + "; return stripAppSuffix")()

const cases = [
  // The suffix names the app: it goes.
  ["YouTube — Mozilla Firefox", "firefox", "YouTube"],
  ["Drumeo - Dashboard - Musora — Mozilla Firefox", "firefox", "Drumeo - Dashboard - Musora"],
  ["Chat | Retail-AI Engineering | Microsoft Teams - Vivaldi", "vivaldi-stable",
   "Chat | Retail-AI Engineering | Microsoft Teams"],
  // The suffix is part of what the window is: it stays.
  ["Junk Removal - Ken Vault - Obsidian 1.13.7", "md.obsidian.Obsidian",
   "Junk Removal - Ken Vault - Obsidian 1.13.7"],
  ["Commits · main · mlstudios / ferrofin · GitLab", "firefox",
   "Commits · main · mlstudios / ferrofin · GitLab"],
  ["Signal", "signal", "Signal"],
  // Nothing to work with.
  ["", "firefox", ""],
  ["— Mozilla Firefox", "firefox", "— Mozilla Firefox"],
  ["Some Window", "", "Some Window"],
]

for (const [title, appClass, want] of cases) {
  const got = strip(title, appClass)
  assert.strictEqual(got, want, `strip(${JSON.stringify(title)}, ${JSON.stringify(appClass)}) === ${JSON.stringify(got)}, wanted ${JSON.stringify(want)}`)
}
console.log(`ok — ${cases.length} cases`)
