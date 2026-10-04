// Shared by verify-live-headers.mjs and the local mock: parses Cloudflare Pages `_headers` (path line, then indented `Name: value` lines) and matches request paths the way Pages does.
import { readFileSync } from 'node:fs'

export function parseHeadersFile(text) {
  const rules = []; let cur = null
  for (const raw of text.split(/\r?\n/)) {
    if (!raw.trim() || raw.trim().startsWith('#')) continue
    if (!/^\s/.test(raw)) { cur = { path: raw.trim(), headers: [] }; rules.push(cur); continue }
    const i = raw.indexOf(':'); if (i < 0 || !cur) continue
    cur.headers.push([raw.slice(0, i).trim().toLowerCase(), raw.slice(i + 1).trim()])
  }
  return rules
}
const toRegex = (path) => new RegExp('^' + path.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*') + '$')
/** Headers Pages would add for a path: every matching rule applies; repeated names are joined with ", " (Pages behaviour). */
export function headersFor(rules, pathname) {
  const out = new Map()
  for (const r of rules) if (toRegex(r.path).test(pathname)) for (const [k, v] of r.headers) out.set(k, out.has(k) ? `${out.get(k)}, ${v}` : v)
  return out
}
export const loadRules = (file) => parseHeadersFile(readFileSync(file, 'utf8'))
