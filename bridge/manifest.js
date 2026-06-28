// bridge/manifest.js
const fs = require("node:fs");
const path = require("node:path");

function walk(dir, base, out) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      if (entry.name === "tests") continue; // never ship tests
      walk(path.join(dir, entry.name), base, out);
    } else if (entry.isFile()) {
      const rel = path.relative(base, path.join(dir, entry.name));
      out.push({ path: "/" + rel.split(path.sep).join("/") });
    }
  }
}

function buildManifest(distDir, version) {
  const files = [];
  walk(distDir, distDir, files);
  files.sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0));
  return { version, files };
}
module.exports = { buildManifest };
