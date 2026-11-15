---
trigger: glob
description: Security and DOM hygiene rules for sidecar and web UI HTML/JS/CSS
globs: "*.html,*.js,*.ts,*.css"
---

# Web UI Rules

## Security
* Build DOM nodes with `document.createElement`, `.textContent`, and
  `.setAttribute(...)` rather than interpolating untrusted values into
  `innerHTML` templates.
* Never rely solely on DOM `div.textContent` / `div.innerHTML` escaping inside
  HTML attributes; explicitly escape `"` (`&quot;`) and `'` (`&#39;`), and
  validate integers (`Number.isInteger`) before rendering numeric fields.
* Validate external link and navigation URLs with `new URL(raw)` against an
  explicit `https:` / `http:` protocol allowlist before assigning `<a href>` or
  calling `window.open` / bridge open helpers.
* Pair UI pages with `Content-Security-Policy` (nonce-based `script-src`,
  `default-src 'none'`, `base-uri 'none'`, `object-src 'none'`) and
  `X-Content-Type-Options: nosniff` headers.
