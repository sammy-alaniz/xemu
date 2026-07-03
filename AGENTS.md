# Agent Notes

## Browser Automation

- For this browser display branch, prefer direct Firefox WebDriver BiDi when testing the browser runtime. The original `browser` branch used this path because Playwright's Firefox launcher can fail or lag the evidence from real Firefox.
- The Firefox BiDi path starts Firefox directly with `--headless --remote-debugging-port=<port> --profile <tmp-profile>` and connects to `ws://127.0.0.1:<port>/session`.
- Use `scripts/xbox-browser-runtime-firefox-bidi.mjs` against the already-running local server, normally `http://127.0.0.1:8765/browser/xbox-boot/`.
- The current page uses auto assets from `/__xemu_assets__/manifest.json`; do not depend on the old `#requireHddInput` or `/__xemu_smoke_asset/...` controls from the original branch.
- For this display experiment, interactive mode is the useful default because the GL renderer errors happen after the old smoke path could report `pass`.
- The browser OpenGL build intentionally sets `-sOFFSCREENCANVASES_TO_PTHREAD= ` with a single-space value. Emscripten treats this as a string and trims it to an empty default at runtime. The display experiment creates a PFIFO-local `OffscreenCanvas`; avoid handing `#canvas` through pthread attrs unless you are deliberately debugging ownership transfer.

Example:

```sh
XEMU_BROWSER_RUNTIME_PAGE_URL=http://127.0.0.1:8765/browser/xbox-boot/ \
XEMU_BROWSER_RUNTIME_BUILD_DIR=../../build-wasm \
XEMU_BROWSER_RUNTIME_INTERACTIVE=1 \
XEMU_BROWSER_RUNTIME_DUMP_TRANSCRIPT=1 \
node scripts/xbox-browser-runtime-firefox-bidi.mjs
```
