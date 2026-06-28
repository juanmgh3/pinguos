// bridge/ascii.js
// CC: Tweaked terminals are 8-bit, ASCII-only. Make any string renderable.
const PUNCT = {
  "¿": "?", "¡": "!",          // ¿ ¡
  "—": "-", "–": "-",          // — –
  "…": "...", "•": "*",        // … •
  "“": '"', "”": '"', "„": '"', // “ ” „
  "‘": "'", "’": "'",          // ‘ ’
  "→": "->", "←": "<-",        // → ←
  " ": " ",                 // non-breaking space
};
function toTerminalAscii(s) {
  if (typeof s !== "string") return s;
  s = s.replace(/[¿¡—–…•“”„‘’→← ]/g, (c) => PUNCT[c] || c);
  s = s.normalize("NFKD").replace(/[̀-ͯ]/g, ""); // strip accents
  s = s.replace(/[^\x09\x0a\x0d\x20-\x7e]/g, "");          // drop the rest
  return s;
}
module.exports = { toTerminalAscii };
