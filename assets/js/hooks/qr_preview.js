// Client-side QR code generation.
//
// Rendering QRs in the browser dodges a class of nasty mobile bugs where
// iOS Safari doesn't fire `input` events reliably during autocorrect /
// QuickType composition, which used to leave the preview stuck on stale
// text. It also removes the WebSocket round-trip and works if the LiveView
// socket happens to be reconnecting.
//
// The `qrcode-generator` vendor file is UMD; esbuild picks up the
// CommonJS-style `module.exports = factory()` and returns the factory
// function as the default export.

import qrcode from "../../vendor/qrcode-generator"

const MAX_LENGTH = 2000
const DEBOUNCE_MS = 100

// Best error-correction level that still keeps QRs compact for typical
// URL payloads. `M` recovers ~15% of the code so a scratched print still
// scans.
const ERROR_CORRECTION = "M"

// `0` = auto-select the smallest QR "type number" (version) that fits.
const TYPE_NUMBER = 0

const QRPreview = {
  mounted() {
    this.input = document.getElementById(this.el.dataset.qrInput)
    this.preview = this.el.querySelector("[data-qr-preview]")
    this.empty = this.el.querySelector("[data-qr-empty]")

    if (!this.input || !this.preview) return

    this.render(this.input.value)

    this.handleInput = () => {
      clearTimeout(this.debounceTimer)
      this.debounceTimer = setTimeout(
        () => this.render(this.input.value),
        DEBOUNCE_MS
      )
    }

    // `input` is the correct event for typing on every modern browser.
    // We also listen for `change` and `blur` as belt-and-braces coverage
    // for iOS Safari edge cases (autocorrect commit, dictation, etc.).
    this.input.addEventListener("input", this.handleInput)
    this.input.addEventListener("change", this.handleInput)
    this.input.addEventListener("blur", this.handleInput)
  },

  destroyed() {
    clearTimeout(this.debounceTimer)
    if (!this.input) return
    this.input.removeEventListener("input", this.handleInput)
    this.input.removeEventListener("change", this.handleInput)
    this.input.removeEventListener("blur", this.handleInput)
  },

  render(text) {
    const trimmed = (text || "").trim()

    if (trimmed.length === 0 || trimmed.length > MAX_LENGTH) {
      this.showEmptyState()
      return
    }

    try {
      const qr = qrcode(TYPE_NUMBER, ERROR_CORRECTION)
      qr.addData(trimmed)
      qr.make()
      // `scalable: true` emits a viewBox-only SVG so CSS controls sizing.
      this.preview.innerHTML = qr.createSvgTag({
        cellSize: 4,
        margin: 0,
        scalable: true,
      })
      this.showPreview()
    } catch (err) {
      console.warn("QR generation failed:", err)
      this.showEmptyState()
    }
  },

  showPreview() {
    this.preview.hidden = false
    if (this.empty) this.empty.hidden = true
  },

  showEmptyState() {
    this.preview.hidden = true
    this.preview.innerHTML = ""
    if (this.empty) this.empty.hidden = false
  },
}

export default QRPreview
