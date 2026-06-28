// bridge/fspath.js
const path = require("node:path");

// Resolve an in-game /fs/<urlPath> request to an absolute file path inside
// distDir, or null if it escapes. distDir may be relative or absolute; both the
// base and the resolved path are normalized to absolute so the containment
// check is reliable regardless of how DIST_DIR was passed.
function safeFsPath(distDir, urlPath) {
  const base = path.resolve(distDir);
  let rel;
  try {
    rel = decodeURIComponent(urlPath);
  } catch {
    return null;
  }
  const abs = path.resolve(base, rel);
  if (abs !== base && !abs.startsWith(base + path.sep)) return null;
  return abs;
}
module.exports = { safeFsPath };
