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

import qrcode from "../../vendor/qrcode-generator";

const MAX_LENGTH = 2000;
const DEBOUNCE_MS = 100;

// Best error-correction level that still keeps QRs compact for typical
// URL payloads. `M` recovers ~15% of the code so a scratched print still
// scans.
const ERROR_CORRECTION = "M";

// `0` = auto-select the smallest QR "type number" (version) that fits.
const TYPE_NUMBER = 0;

// PNG export dimensions. High enough to look sharp when embedded in slides
// or printed at ~3 inches wide, small enough to keep the file well under
// 100 KB.
const EXPORT_SIZE = 1024;

const QRPreview = {
  mounted() {
    this.input = document.getElementById(this.el.dataset.qrInput);
    this.preview = this.el.querySelector("[data-qr-preview]");
    this.empty = this.el.querySelector("[data-qr-empty]");
    this.downloadBtn = this.el.querySelector("[data-qr-download]");
    this.copyBtn = this.el.querySelector("[data-qr-copy]");
    this.qr = null;

    if (!this.input || !this.preview) return;

    this.render(this.input.value);

    this.handleInput = () => {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = setTimeout(
        () => this.render(this.input.value),
        DEBOUNCE_MS,
      );
    };

    // `input` is the correct event for typing on every modern browser.
    // We also listen for `change` and `blur` as belt-and-braces coverage
    // for iOS Safari edge cases (autocorrect commit, dictation, etc.).
    this.input.addEventListener("input", this.handleInput);
    this.input.addEventListener("change", this.handleInput);
    this.input.addEventListener("blur", this.handleInput);

    if (this.downloadBtn) {
      this.handleDownload = (e) => {
        e.preventDefault();
        this.downloadPng();
      };
      this.downloadBtn.addEventListener("click", this.handleDownload);
    }

    if (this.copyBtn) {
      this.handleCopy = (e) => {
        e.preventDefault();
        this.copyImage();
      };
      this.copyBtn.addEventListener("click", this.handleCopy);

      // Some browsers (notably Firefox) don't implement `ClipboardItem`
      // at all — hide the copy button entirely there instead of showing
      // one that always fails.
      if (typeof ClipboardItem === "undefined") {
        this.copyBtn.hidden = true;
      }
    }
  },

  destroyed() {
    clearTimeout(this.debounceTimer);
    if (this.input) {
      this.input.removeEventListener("input", this.handleInput);
      this.input.removeEventListener("change", this.handleInput);
      this.input.removeEventListener("blur", this.handleInput);
    }
    if (this.downloadBtn && this.handleDownload) {
      this.downloadBtn.removeEventListener("click", this.handleDownload);
    }
    if (this.copyBtn && this.handleCopy) {
      this.copyBtn.removeEventListener("click", this.handleCopy);
    }
  },

  render(text) {
    const trimmed = (text || "").trim();

    if (trimmed.length === 0 || trimmed.length > MAX_LENGTH) {
      this.qr = null;
      this.text = "";
      this.showEmptyState();
      this.setActionsDisabled(true);
      return;
    }

    try {
      const qr = qrcode(TYPE_NUMBER, ERROR_CORRECTION);
      qr.addData(trimmed);
      qr.make();
      // `scalable: true` emits a viewBox-only SVG so CSS controls sizing.
      this.preview.innerHTML = qr.createSvgTag({
        cellSize: 4,
        margin: 0,
        scalable: true,
      });
      this.qr = qr;
      this.text = trimmed;
      this.showPreview();
      this.setActionsDisabled(false);
    } catch (err) {
      console.warn("QR generation failed:", err);
      this.qr = null;
      this.showEmptyState();
      this.setActionsDisabled(true);
    }
  },

  showPreview() {
    this.preview.hidden = false;
    if (this.empty) this.empty.hidden = true;
  },

  showEmptyState() {
    this.preview.hidden = true;
    this.preview.innerHTML = "";
    if (this.empty) this.empty.hidden = false;
  },

  setActionsDisabled(disabled) {
    for (const btn of [this.downloadBtn, this.copyBtn]) {
      if (!btn) continue;
      btn.disabled = disabled;
      btn.setAttribute("aria-disabled", String(disabled));
    }
  },

  // Rasterizes the current QR to a PNG blob at EXPORT_SIZE x EXPORT_SIZE.
  // Draws directly onto a canvas from the QR matrix — that keeps output
  // pixel-perfect (no anti-aliasing artefacts) and avoids the fragile
  // "SVG-into-an-Image-tag" round-trip.
  toPngBlob() {
    return new Promise((resolve, reject) => {
      if (!this.qr) return reject(new Error("no qr"));

      const modules = this.qr.getModuleCount();
      const cellSize = Math.floor(EXPORT_SIZE / modules);
      const size = cellSize * modules;

      const canvas = document.createElement("canvas");
      canvas.width = size;
      canvas.height = size;
      const ctx = canvas.getContext("2d");

      ctx.fillStyle = "#ffffff";
      ctx.fillRect(0, 0, size, size);

      ctx.fillStyle = "#000000";
      for (let row = 0; row < modules; row++) {
        for (let col = 0; col < modules; col++) {
          if (this.qr.isDark(row, col)) {
            ctx.fillRect(col * cellSize, row * cellSize, cellSize, cellSize);
          }
        }
      }

      canvas.toBlob((blob) => {
        if (blob) resolve(blob);
        else reject(new Error("toBlob returned null"));
      }, "image/png");
    });
  },

  filename() {
    const label = (this.text || "qr")
      .replace(/^https?:\/\//, "")
      .replace(/[^a-z0-9-_.]+/gi, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 60);

    return `qr-${label || "code"}.png`;
  },

  async downloadPng() {
    if (!this.qr) return;

    try {
      const blob = await this.toPngBlob();
      const url = URL.createObjectURL(blob);

      const a = document.createElement("a");
      a.href = url;
      a.download = this.filename();
      document.body.appendChild(a);
      a.click();
      a.remove();

      // Give the browser a moment to actually kick off the download
      // before we revoke the object URL.
      setTimeout(() => URL.revokeObjectURL(url), 1000);

      this.flashButtonLabel(this.downloadBtn);
    } catch (err) {
      console.warn("QR download failed:", err);
    }
  },

  async copyImage() {
    if (!this.qr) return;

    // iOS Safari requires the ClipboardItem's data to be a *synchronously*
    // resolved Promise — so we build the blob first and hand it over.
    try {
      const blob = await this.toPngBlob();

      // Preferred: modern async clipboard API.
      if (navigator.clipboard && typeof ClipboardItem !== "undefined") {
        const item = new ClipboardItem({ "image/png": blob });
        await navigator.clipboard.write([item]);
        this.flashButtonLabel(this.copyBtn);
        return;
      }

      // iOS fallback: Web Share API — user can pick "Copy" or share
      // to any app that accepts images.
      if (navigator.canShare && navigator.canShare({ files: [] })) {
        const file = new File([blob], this.filename(), { type: "image/png" });
        if (navigator.canShare({ files: [file] })) {
          await navigator.share({ files: [file] });
          return;
        }
      }

      console.warn("Clipboard image copy is not supported in this browser.");
    } catch (err) {
      // Users hitting `AbortError` from a cancelled share sheet isn't
      // actually a problem — swallow it silently.
      if (err && err.name !== "AbortError") {
        console.warn("QR copy failed:", err);
      }
    }
  },

  // Briefly swap the button's inner text to give tactile confirmation
  // that the action succeeded (mirrors the copy-link button on the
  // shorten tab). Reads the temporary label from `data-copied-label`.
  flashButtonLabel(btn) {
    if (!btn) return;
    const label = btn.dataset.copiedLabel;
    if (!label) return;

    const labelEl = btn.querySelector("[data-label]");
    if (!labelEl) return;

    const original = labelEl.textContent;
    labelEl.textContent = label;
    clearTimeout(btn.__resetTimer);
    btn.__resetTimer = setTimeout(() => {
      labelEl.textContent = original;
    }, 1500);
  },
};

export default QRPreview;
