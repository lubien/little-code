// Client-side QR code generation + customization (colors, border, radius,
// center logo). Everything is rendered onto a <canvas> so the preview and
// the PNG export are visually identical.
//
// The `qrcode-generator` vendor file is UMD; esbuild picks up its
// CommonJS export as the default.

import qrcode from "../../vendor/qrcode-generator";

const MAX_LENGTH = 2000;
const DEBOUNCE_MS = 100;

// `0` = auto-select the smallest QR "type number" (version) that fits.
const TYPE_NUMBER = 0;
const EC_DEFAULT = "M"; // ~15% recovery
const EC_WITH_LOGO = "H"; // ~30% recovery, safe under a logo overlay

// Canvas size for both preview and PNG export. High enough to stay crisp
// on print, small enough to keep the PNG under ~100 KB.
const EXPORT_SIZE = 1024;

// ---- presets ----------------------------------------------------------
//
// borderWidth / radius / padding are expressed as fractions of the
// canvas size so they scale cleanly. Colors are picked so QR contrast
// stays above ~5:1 for reliable scanning.
const PRESETS = {
  classic: {
    fg: "#0f172a",
    bg: "#ffffff",
    borderColor: "#0f172a",
    borderWidth: 0,
    radius: 0,
    padding: 0.06,
  },
  business: {
    fg: "#0f172a",
    bg: "#ffffff",
    borderColor: "#94a3b8",
    borderWidth: 0.008,
    radius: 0.04,
    padding: 0.06,
  },
  bubble: {
    fg: "#1e3a8a",
    bg: "#dbeafe",
    borderColor: "#1e3a8a",
    borderWidth: 0.02,
    radius: 0.18,
    padding: 0.08,
  },
  "lo-fi": {
    fg: "#7c2d12",
    bg: "#fef3c7",
    borderColor: "#7c2d12",
    borderWidth: 0,
    radius: 0.08,
    padding: 0.06,
  },
  developer: {
    fg: "#22c55e",
    bg: "#0a0a0a",
    borderColor: "#22c55e",
    borderWidth: 0,
    radius: 0.02,
    padding: 0.05,
  },
  sunset: {
    fg: "#7c2d12",
    bg: "#fed7aa",
    borderColor: "#7c2d12",
    borderWidth: 0.012,
    radius: 0.1,
    padding: 0.06,
  },
  neon: {
    fg: "#f0abfc",
    bg: "#0f172a",
    borderColor: "#22d3ee",
    borderWidth: 0.012,
    radius: 0.06,
    padding: 0.05,
  },
  print: {
    fg: "#000000",
    bg: "#ffffff",
    borderColor: "#000000",
    borderWidth: 0.006,
    radius: 0.02,
    padding: 0.06,
  },
};

const DEFAULT_PRESET = "classic";

// Slider ranges. Each slider is an integer in the DOM (for a11y and clean
// URL / event story) and gets divided down to the fractional value the
// renderer expects.
//
//   * Border width: slider 0..40 → 0..0.04 (0–4% of canvas) via /1000
//   * Radius:      slider 0..50 → 0..0.50 (0–50% of canvas) via /100
//   * Logo size:   slider 10..30 → 0.10..0.30 fraction via /100
//
// The upper bound on logo size is deliberately conservative — QR
// error-correction level H recovers ~30% of the code, and any logo
// wider than ~30% starts occluding timing / alignment patterns that
// the scanner *needs* to lock onto. Larger logos would still render
// but wouldn't reliably scan.
const BORDER_WIDTH_MAX = 40;
const BORDER_WIDTH_DIVISOR = 1000;
const RADIUS_MAX = 50;
const RADIUS_DIVISOR = 100;
const LOGO_SIZE_DIVISOR = 100;

// Logo defaults — same look as before for users who don't touch the
// controls.
const DEFAULT_LOGO_SIZE = 0.22;
const DEFAULT_LOGO_ROUNDED = false;

const QRPreview = {
  mounted() {
    this.input = document.getElementById(this.el.dataset.qrInput);
    this.preview = this.el.querySelector("[data-qr-preview]");
    this.empty = this.el.querySelector("[data-qr-empty]");

    this.downloadBtn = this.el.querySelector("[data-qr-download]");
    this.copyBtn = this.el.querySelector("[data-qr-copy]");

    this.fgInput = this.el.querySelector("[data-qr-fg]");
    this.bgInput = this.el.querySelector("[data-qr-bg]");
    this.borderColorInput = this.el.querySelector("[data-qr-border-color]");
    this.borderWidthInput = this.el.querySelector("[data-qr-border-width]");
    this.radiusInput = this.el.querySelector("[data-qr-radius]");
    this.logoInput = this.el.querySelector("[data-qr-logo]");
    this.logoRemoveBtn = this.el.querySelector("[data-qr-logo-remove]");
    this.resetBtn = this.el.querySelector("[data-qr-reset]");
    this.presetButtons = Array.from(
      this.el.querySelectorAll("[data-qr-preset]"),
    );

    if (!this.input || !this.preview) return;

    this.qr = null;
    this.text = "";
    this.canvas = null;
    this.options = {
      ...PRESETS[DEFAULT_PRESET],
      logo: null,
      logoObjectUrl: null,
      logoSize: DEFAULT_LOGO_SIZE,
      logoRounded: DEFAULT_LOGO_ROUNDED,
    };

    this.logoSizeInput = this.el.querySelector("[data-qr-logo-size]");
    this.logoRoundedInput = this.el.querySelector("[data-qr-logo-rounded]");

    // --- text input --------------------------------------------------
    this.handleInput = () => this.scheduleRender();
    this.input.addEventListener("input", this.handleInput);
    this.input.addEventListener("change", this.handleInput);
    this.input.addEventListener("blur", this.handleInput);

    // --- customization: colors / border / radius --------------------
    this.wireColor(this.fgInput, "fg");
    this.wireColor(this.bgInput, "bg");
    this.wireColor(this.borderColorInput, "borderColor");
    this.wireRange(this.borderWidthInput, "borderWidth", BORDER_WIDTH_DIVISOR);
    this.wireRange(this.radiusInput, "radius", RADIUS_DIVISOR);
    this.wireRange(this.logoSizeInput, "logoSize", LOGO_SIZE_DIVISOR);
    this.wireCheckbox(this.logoRoundedInput, "logoRounded");

    // --- customization: logo ----------------------------------------
    if (this.logoInput) {
      this.handleLogoChange = (e) => this.onLogoPicked(e);
      this.logoInput.addEventListener("change", this.handleLogoChange);
    }
    if (this.logoRemoveBtn) {
      this.handleLogoRemove = (e) => {
        e.preventDefault();
        this.clearLogo();
      };
      this.logoRemoveBtn.addEventListener("click", this.handleLogoRemove);
    }

    // --- reset -------------------------------------------------------
    if (this.resetBtn) {
      this.handleReset = (e) => {
        e.preventDefault();
        this.applyPreset(DEFAULT_PRESET);
        this.clearLogo();
        // Reset logo controls too.
        this.options.logoSize = DEFAULT_LOGO_SIZE;
        this.options.logoRounded = DEFAULT_LOGO_ROUNDED;
        if (this.logoSizeInput) {
          this.logoSizeInput.value = String(
            Math.round(DEFAULT_LOGO_SIZE * LOGO_SIZE_DIVISOR),
          );
        }
        if (this.logoRoundedInput) {
          this.logoRoundedInput.checked = DEFAULT_LOGO_ROUNDED;
        }
      };
      this.resetBtn.addEventListener("click", this.handleReset);
    }

    // --- presets -----------------------------------------------------
    this.presetHandlers = [];
    for (const btn of this.presetButtons) {
      const handler = (e) => {
        e.preventDefault();
        this.applyPreset(btn.dataset.qrPreset);
      };
      btn.addEventListener("click", handler);
      this.presetHandlers.push([btn, handler]);
    }

    // --- action buttons ---------------------------------------------
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
      if (typeof ClipboardItem === "undefined") this.copyBtn.hidden = true;
    }

    // Pull whatever's currently in the form controls (which may have
    // been rendered with any default) into our options state.
    this.syncFromInputs();
    this.updatePresetHighlight();

    this.render(this.input.value);
  },

  destroyed() {
    clearTimeout(this.debounceTimer);
    this.revokeLogoUrl();

    if (this.input) {
      this.input.removeEventListener("input", this.handleInput);
      this.input.removeEventListener("change", this.handleInput);
      this.input.removeEventListener("blur", this.handleInput);
    }
    for (const [el, handlers] of this.wiredControls || []) {
      for (const [event, handler] of handlers) {
        el.removeEventListener(event, handler);
      }
    }
    if (this.logoInput && this.handleLogoChange) {
      this.logoInput.removeEventListener("change", this.handleLogoChange);
    }
    if (this.logoRemoveBtn && this.handleLogoRemove) {
      this.logoRemoveBtn.removeEventListener("click", this.handleLogoRemove);
    }
    if (this.resetBtn && this.handleReset) {
      this.resetBtn.removeEventListener("click", this.handleReset);
    }
    for (const [btn, handler] of this.presetHandlers || []) {
      btn.removeEventListener("click", handler);
    }
    if (this.downloadBtn && this.handleDownload) {
      this.downloadBtn.removeEventListener("click", this.handleDownload);
    }
    if (this.copyBtn && this.handleCopy) {
      this.copyBtn.removeEventListener("click", this.handleCopy);
    }
  },

  // -------- wiring helpers ------------------------------------------

  wireColor(el, key) {
    if (!el) return;
    const handler = (e) => this.setOption(key, e.target.value);
    el.addEventListener("input", handler);
    el.addEventListener("change", handler);
    this.wiredControls = this.wiredControls || [];
    this.wiredControls.push([
      el,
      [
        ["input", handler],
        ["change", handler],
      ],
    ]);
  },

  wireRange(el, key, divisor) {
    if (!el) return;
    const handler = (e) => {
      const raw = Number(e.target.value) || 0;
      this.setOption(key, raw / divisor);
    };
    el.addEventListener("input", handler);
    el.addEventListener("change", handler);
    this.wiredControls = this.wiredControls || [];
    this.wiredControls.push([
      el,
      [
        ["input", handler],
        ["change", handler],
      ],
    ]);
  },

  wireCheckbox(el, key) {
    if (!el) return;
    const handler = (e) => this.setOption(key, !!e.target.checked);
    el.addEventListener("change", handler);
    this.wiredControls = this.wiredControls || [];
    this.wiredControls.push([el, [["change", handler]]]);
  },

  // -------- state ---------------------------------------------------

  setOption(key, value) {
    this.options[key] = value;
    this.updatePresetHighlight();
    this.scheduleRender();
  },

  scheduleRender() {
    clearTimeout(this.debounceTimer);
    this.debounceTimer = setTimeout(
      () => this.render(this.input.value),
      DEBOUNCE_MS,
    );
  },

  syncFromInputs() {
    if (this.fgInput) this.options.fg = this.fgInput.value || this.options.fg;
    if (this.bgInput) this.options.bg = this.bgInput.value || this.options.bg;
    if (this.borderColorInput) {
      this.options.borderColor =
        this.borderColorInput.value || this.options.borderColor;
    }
    if (this.borderWidthInput) {
      const v = Number(this.borderWidthInput.value) || 0;
      this.options.borderWidth = v / BORDER_WIDTH_DIVISOR;
    }
    if (this.radiusInput) {
      const v = Number(this.radiusInput.value) || 0;
      this.options.radius = v / RADIUS_DIVISOR;
    }
    if (this.logoSizeInput) {
      const v = Number(this.logoSizeInput.value) || 0;
      this.options.logoSize = v / LOGO_SIZE_DIVISOR;
    }
    if (this.logoRoundedInput) {
      this.options.logoRounded = !!this.logoRoundedInput.checked;
    }
  },

  // -------- presets -------------------------------------------------

  applyPreset(name) {
    const preset = PRESETS[name];
    if (!preset) return;

    Object.assign(this.options, preset);

    // Sync UI controls so the sliders and pickers reflect the preset.
    if (this.fgInput) this.fgInput.value = preset.fg;
    if (this.bgInput) this.bgInput.value = preset.bg;
    if (this.borderColorInput) this.borderColorInput.value = preset.borderColor;
    if (this.borderWidthInput) {
      this.borderWidthInput.value = String(
        Math.round(preset.borderWidth * BORDER_WIDTH_DIVISOR),
      );
    }
    if (this.radiusInput) {
      this.radiusInput.value = String(
        Math.round(preset.radius * RADIUS_DIVISOR),
      );
    }

    this.updatePresetHighlight();
    this.scheduleRender();
  },

  // Highlight whichever preset (if any) exactly matches the current
  // options. This makes the buttons feel like radio buttons even though
  // the user can still tweak individual controls afterwards.
  updatePresetHighlight() {
    for (const btn of this.presetButtons) {
      const preset = PRESETS[btn.dataset.qrPreset];
      const active = preset && this.matchesPreset(preset);
      btn.setAttribute("aria-pressed", active ? "true" : "false");
      btn.classList.toggle("ring", active);
      btn.classList.toggle("ring-primary", active);
      btn.classList.toggle("ring-2", active);
    }
  },

  matchesPreset(preset) {
    const eq = (a, b) =>
      typeof a === "string"
        ? a.toLowerCase() === (b || "").toLowerCase()
        : Math.abs((a || 0) - (b || 0)) < 1e-6;

    return (
      eq(this.options.fg, preset.fg) &&
      eq(this.options.bg, preset.bg) &&
      eq(this.options.borderColor, preset.borderColor) &&
      eq(this.options.borderWidth, preset.borderWidth) &&
      eq(this.options.radius, preset.radius) &&
      eq(this.options.padding, preset.padding)
    );
  },

  // -------- logo ----------------------------------------------------

  onLogoPicked(event) {
    const file = event.target.files && event.target.files[0];
    if (!file) return;

    this.revokeLogoUrl();
    const url = URL.createObjectURL(file);
    const img = new Image();

    img.onload = () => {
      this.options.logo = img;
      this.options.logoObjectUrl = url;
      if (this.logoRemoveBtn) this.logoRemoveBtn.hidden = false;
      this.scheduleRender();
    };
    img.onerror = () => {
      URL.revokeObjectURL(url);
      console.warn("QR logo failed to load");
    };
    img.src = url;
  },

  clearLogo() {
    this.revokeLogoUrl();
    this.options.logo = null;
    if (this.logoInput) this.logoInput.value = "";
    if (this.logoRemoveBtn) this.logoRemoveBtn.hidden = true;
    this.scheduleRender();
  },

  revokeLogoUrl() {
    if (this.options && this.options.logoObjectUrl) {
      URL.revokeObjectURL(this.options.logoObjectUrl);
      this.options.logoObjectUrl = null;
    }
  },

  // -------- rendering -----------------------------------------------

  render(text) {
    const trimmed = (text || "").trim();

    if (trimmed.length === 0 || trimmed.length > MAX_LENGTH) {
      this.qr = null;
      this.text = "";
      this.showEmptyState();
      this.setActionsDisabled(true);
      return;
    }

    const ec = this.options.logo ? EC_WITH_LOGO : EC_DEFAULT;

    try {
      const qr = qrcode(TYPE_NUMBER, ec);
      qr.addData(trimmed);
      qr.make();
      this.qr = qr;
      this.text = trimmed;
      this.drawToCanvas();
      this.showPreview();
      this.setActionsDisabled(false);
    } catch (err) {
      console.warn("QR generation failed:", err);
      this.qr = null;
      this.showEmptyState();
      this.setActionsDisabled(true);
    }
  },

  drawToCanvas(sizePx) {
    const size = sizePx || EXPORT_SIZE;
    const canvas = document.createElement("canvas");
    canvas.width = size;
    canvas.height = size;
    canvas.style.width = "100%";
    canvas.style.height = "100%";
    canvas.style.display = "block";

    const ctx = canvas.getContext("2d");

    const radius = size * (this.options.radius || 0);
    const borderWidth = size * (this.options.borderWidth || 0);
    const padding = size * (this.options.padding || 0.06);

    // Rounded background fill.
    ctx.fillStyle = this.options.bg;
    roundedRectPath(ctx, 0, 0, size, size, radius);
    ctx.fill();

    // Border stroke, inset by half the width so it sits inside the canvas.
    if (borderWidth > 0 && this.options.borderColor) {
      const inset = borderWidth / 2;
      ctx.strokeStyle = this.options.borderColor;
      ctx.lineWidth = borderWidth;
      roundedRectPath(
        ctx,
        inset,
        inset,
        size - 2 * inset,
        size - 2 * inset,
        Math.max(0, radius - inset),
      );
      ctx.stroke();
    }

    // QR module grid, inset by the quiet zone and any border width.
    const drawableStart = padding + borderWidth;
    const drawable = size - 2 * drawableStart;
    const modules = this.qr.getModuleCount();
    const cellSize = Math.floor(drawable / modules);
    const actualDrawable = cellSize * modules;
    // Recenter any leftover fractional pixels.
    const offset = drawableStart + (drawable - actualDrawable) / 2;

    // Pre-compute the area the logo will occupy so we can skip modules
    // underneath it — otherwise QR dots either peek through the rounded
    // corners of the backdrop or bleed through transparent parts of the
    // uploaded image, which looks broken.
    const reserved = this.reservedLogoRect(size);

    ctx.fillStyle = this.options.fg;
    for (let row = 0; row < modules; row++) {
      for (let col = 0; col < modules; col++) {
        if (!this.qr.isDark(row, col)) continue;

        const cellX = offset + col * cellSize;
        const cellY = offset + row * cellSize;

        if (reserved && rectsOverlap(cellX, cellY, cellSize, reserved)) {
          continue;
        }

        ctx.fillRect(cellX, cellY, cellSize, cellSize);
      }
    }

    if (this.options.logo) this.drawLogo(ctx, size);

    if (this.canvas !== canvas) {
      this.canvas = canvas;
      this.preview.innerHTML = "";
      this.preview.appendChild(canvas);
    }

    return canvas;
  },

  // Rectangle (in canvas pixels) that the logo will occupy — used to
  // skip modules that would otherwise render underneath the overlay,
  // so we don't get QR dots peeking through transparent parts of the
  // uploaded image.
  reservedLogoRect(size) {
    const logo = this.options.logo;
    if (!logo) return null;

    // Hard-clamp the drawing side too, so even a bad `options.logoSize`
    // value (e.g. via a stale query string) can't produce an unscannable
    // QR. Matches the slider max.
    const areaFrac = clamp(this.options.logoSize ?? DEFAULT_LOGO_SIZE, 0.05, 0.3);
    const logoArea = size * areaFrac;

    // Fitted image bounds (preserve aspect ratio) — modules hug the
    // logo tightly so non-square images still let the code fill in.
    const scale = Math.min(logoArea / logo.width, logoArea / logo.height);
    const w = logo.width * scale;
    const h = logo.height * scale;
    return { x: (size - w) / 2, y: (size - h) / 2, width: w, height: h };
  },

  drawLogo(ctx, size) {
    const logo = this.options.logo;
    const areaFrac = clamp(this.options.logoSize ?? DEFAULT_LOGO_SIZE, 0.05, 0.3);
    const logoArea = size * areaFrac;

    // Fit the logo preserving aspect ratio.
    const scale = Math.min(logoArea / logo.width, logoArea / logo.height);
    const drawW = logo.width * scale;
    const drawH = logo.height * scale;
    const drawX = (size - drawW) / 2;
    const drawY = (size - drawH) / 2;

    if (this.options.logoRounded) {
      // Clip the image to a rounded rect so square avatars look softer.
      ctx.save();
      const minSide = Math.min(drawW, drawH);
      const clipRadius = Math.round(minSide * 0.2);
      roundedRectPath(ctx, drawX, drawY, drawW, drawH, clipRadius);
      ctx.clip();
      ctx.drawImage(logo, drawX, drawY, drawW, drawH);
      ctx.restore();
    } else {
      ctx.drawImage(logo, drawX, drawY, drawW, drawH);
    }
  },

  showPreview() {
    this.preview.hidden = false;
    if (this.empty) this.empty.hidden = true;
  },

  showEmptyState() {
    this.canvas = null;
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

  // -------- export --------------------------------------------------

  toPngBlob() {
    return new Promise((resolve, reject) => {
      if (!this.qr) return reject(new Error("no qr"));
      const canvas = this.drawToCanvas(EXPORT_SIZE);
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
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      this.flashButtonLabel(this.downloadBtn);
    } catch (err) {
      console.warn("QR download failed:", err);
    }
  },

  async copyImage() {
    if (!this.qr) return;
    try {
      const blob = await this.toPngBlob();

      if (navigator.clipboard && typeof ClipboardItem !== "undefined") {
        const item = new ClipboardItem({ "image/png": blob });
        await navigator.clipboard.write([item]);
        this.flashButtonLabel(this.copyBtn);
        return;
      }
      if (navigator.canShare && navigator.canShare({ files: [] })) {
        const file = new File([blob], this.filename(), { type: "image/png" });
        if (navigator.canShare({ files: [file] })) {
          await navigator.share({ files: [file] });
          return;
        }
      }
      console.warn("Clipboard image copy is not supported in this browser.");
    } catch (err) {
      if (err && err.name !== "AbortError") {
        console.warn("QR copy failed:", err);
      }
    }
  },

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

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

// True when the axis-aligned cell (`cx`, `cy`, `cs`x`cs`) overlaps the
// given rectangle. Uses strict inequalities so cells that only *touch*
// the edge of the rectangle are still drawn (avoids ugly one-pixel
// gaps around the reserved area).
function rectsOverlap(cx, cy, cs, r) {
  return (
    cx < r.x + r.width &&
    cx + cs > r.x &&
    cy < r.y + r.height &&
    cy + cs > r.y
  );
}

// Rounded-rect path used for both the background fill and the border
// stroke. Older Safari doesn't ship `CanvasRenderingContext2D.roundRect`
// so we draw the arcs ourselves.
function roundedRectPath(ctx, x, y, w, h, r) {
  const radius = Math.max(0, Math.min(r, w / 2, h / 2));
  ctx.beginPath();
  ctx.moveTo(x + radius, y);
  ctx.lineTo(x + w - radius, y);
  ctx.quadraticCurveTo(x + w, y, x + w, y + radius);
  ctx.lineTo(x + w, y + h - radius);
  ctx.quadraticCurveTo(x + w, y + h, x + w - radius, y + h);
  ctx.lineTo(x + radius, y + h);
  ctx.quadraticCurveTo(x, y + h, x, y + h - radius);
  ctx.lineTo(x, y + radius);
  ctx.quadraticCurveTo(x, y, x + radius, y);
  ctx.closePath();
}

export default QRPreview;
