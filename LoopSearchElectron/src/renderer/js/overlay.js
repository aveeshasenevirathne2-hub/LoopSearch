(function () {
  'use strict';

  const { Icons, applyGlassAppearance, renderOpticalOrbHtml } = window.LoopUI;
  const {
    extractPrimaryURL,
    displayHostForUrl,
    evaluateMathExpression,
    extractDominantColor,
    analyzeRegionDetail,
    shouldApplyWebDarkCss,
    buildSearchUrl
  } = window.LoopVisionHelpers;

  const GLOW_PALETTES = {
    apple: ['#38bdf8', '#2563eb', '#60a5fa', '#818cf8', '#a5f3fc', '#38bdf8'],
    arctic: ['#22d3ee', '#0ea5e9', '#67e8f9', '#e0f2fe', '#0284c7', '#22d3ee'],
    violet: ['#a78bfa', '#7c3aed', '#f472b6', '#38bdf8', '#c4b5fd', '#a78bfa'],
    ember: ['#fb923c', '#ef4444', '#facc15', '#fb7185', '#fde047', '#fb923c']
  };

  const screenCanvas = document.getElementById('screen-canvas');
  const fxCanvas = document.getElementById('fx-canvas');
  const screenCtx = screenCanvas.getContext('2d');
  const fxCtx = fxCanvas.getContext('2d');
  const ocrLayer = document.getElementById('ocr-layer');

  const promptCapsule = document.getElementById('prompt-capsule');
  const capsuleHint = document.getElementById('capsule-hint');
  const historyPopover = document.getElementById('history-popover');
  const histList = document.getElementById('hist-list');
  const resultsSheet = document.getElementById('results-sheet');
  const webview = document.getElementById('lens-webview');
  const wvLoader = document.getElementById('wv-loader');
  const loaderStatusText = document.getElementById('loader-status-text');
  const cropThumb = document.getElementById('crop-thumb');
  const followUpInput = document.getElementById('follow-up-input');
  const ocrPreviewLine = document.getElementById('ocr-preview-line');
  const smartChipsBar = document.getElementById('smart-chips-bar');
  const aiAnswerCard = document.getElementById('ai-answer-card');
  const aiAnswerText = document.getElementById('ai-answer-text');

  const ENGINE_LABELS = {
    googleLens: 'Google Lens',
    perplexity: 'Perplexity',
    bing: 'Bing',
    aiExplain: 'Google AI'
  };
  const ENGINE_ORDER = ['googleLens', 'perplexity', 'bing', 'aiExplain'];

  let initData = null;
  let settings = {};
  let screenW = window.innerWidth;
  let screenH = window.innerHeight;
  let dpr = window.devicePixelRatio || 1;
  let safeInsets = { top: 0, left: 0, right: 0, bottom: 0 };

  let sourceImg = null;
  let activeMode = 'box'; // box | freehand | tap | text
  let activeEngine = 'googleLens';
  let webDarkMode = true;
  let sheetExpanded = false;
  let isMockDemo = false;

  // Selection & Gesture state
  let selectionRect = null; // { x, y, w, h }
  let freehandPoints = []; // [{ x, y }]
  let settledSelection = null; // { kind: 'box'|'freehand', rect, points, settledAt }
  let interaction = null; // { kind: 'draw-box'|'draw-free'|'move-box'|'resize-box'|'ocr-drag', startX, startY, corner, origRect }
  let isSearching = false;
  let isOcrRunning = false;

  // Current capture artifacts
  let lastCropPngBase64 = '';
  let lastCropJpegBase64 = '';
  let lastCropDataUrl = '';
  let lastCropW = 0;
  let lastCropH = 0;
  let lastOcrText = '';
  let fullScreenOcrLines = null;
  let lastLensUrl = '';
  let currentWebUrl = '';

  // Particle & animation state
  let overlayOpenedAt = performance.now();
  const stars = Array.from({ length: 26 }, () => ({
    x: Math.random(),
    y: Math.random(),
    size: 1.5 + Math.random() * 2.5,
    phase: Math.random() * Math.PI * 2,
    speed: 1.1 + Math.random() * 1.4
  }));
  const ambientSparks = Array.from({ length: 16 }, () => ({
    x: Math.random(),
    y: Math.random(),
    vy: 0.012 + Math.random() * 0.018,
    alpha: 0.15 + Math.random() * 0.35,
    r: 1 + Math.random() * 1.6
  }));
  const particles = [];
  const ripples = [];

  function populateStaticIcons() {
    document.getElementById('capsule-brand').innerHTML = Icons.brandMark(18);
    document.getElementById('mode-box').innerHTML = `${Icons.box(13)}<span>1 Box</span>`;
    document.getElementById('mode-freehand').innerHTML = `${Icons.lasso(13)}<span>2 Loop</span>`;
    document.getElementById('mode-tap').innerHTML = `${Icons.tap(13)}<span>3 Tap</span>`;
    document.getElementById('mode-text').innerHTML = `${Icons.text(13)}<span>4 Text</span>`;
    document.getElementById('cap-history-btn').innerHTML = Icons.history(14);
    document.getElementById('cap-studio-btn').innerHTML = Icons.gear(14);
    document.getElementById('cap-close-btn').innerHTML = Icons.close(13);

    document.getElementById('sheet-back-btn').innerHTML = Icons.back(14);
    document.getElementById('sheet-brand').innerHTML = Icons.brandMark(18);
    document.getElementById('sheet-dark-btn').innerHTML = Icons.moon(13);
    document.getElementById('sheet-pin-btn').innerHTML = Icons.pin(13);
    document.getElementById('sheet-ext-btn').innerHTML = Icons.external(13);
    document.getElementById('sheet-expand-btn').innerHTML = Icons.expand(13);
    document.getElementById('sheet-close-btn').innerHTML = Icons.close(13);
    document.getElementById('follow-up-send').innerHTML = Icons.send(13);
    document.getElementById('loader-orb-slot').innerHTML = renderOpticalOrbHtml(false);
  }
  populateStaticIcons();

  function setupCanvasSizes() {
    dpr = window.devicePixelRatio || (initData && initData.scaleFactor) || 1;
    screenCanvas.width = Math.max(1, Math.round(screenW * dpr));
    screenCanvas.height = Math.max(1, Math.round(screenH * dpr));
    screenCtx.setTransform(dpr, 0, 0, dpr, 0, 0);

    fxCanvas.width = Math.max(1, Math.round(screenW * dpr));
    fxCanvas.height = Math.max(1, Math.round(screenH * dpr));
    fxCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  function drawFrozenScreen() {
    if (!sourceImg) return;
    screenCtx.clearRect(0, 0, screenW, screenH);
    if (initData && initData.clipboardImageDataUrl) {
      screenCtx.fillStyle = '#070a14';
      screenCtx.fillRect(0, 0, screenW, screenH);
      const scale = Math.min((screenW * 0.65) / sourceImg.naturalWidth, (screenH * 0.65) / sourceImg.naturalHeight, 1.4);
      const dw = sourceImg.naturalWidth * scale;
      const dh = sourceImg.naturalHeight * scale;
      const dx = (screenW - dw) / 2;
      const dy = (screenH - dh) / 2;
      screenCtx.drawImage(sourceImg, dx, dy, dw, dh);
      initData._clipRect = { x: dx, y: dy, w: dw, h: dh };
    } else {
      screenCtx.drawImage(sourceImg, 0, 0, screenW, screenH);
    }
  }

  function setMode(mode) {
    activeMode = mode;
    document.querySelectorAll('.mode-pill').forEach((btn) => {
      btn.classList.toggle('active', btn.dataset.mode === mode);
    });
    const hints = {
      box: 'Drag a box around anything',
      freehand: 'Circle or loop around an object',
      tap: 'Click anywhere to smart-select',
      text: 'Click text on screen to copy'
    };
    capsuleHint.textContent = hints[mode] || hints.box;
    fxCanvas.style.cursor = mode === 'tap' ? 'pointer' : mode === 'text' ? 'text' : 'crosshair';

    if (mode === 'text') {
      ensureFullScreenOcr();
    } else {
      ocrLayer.innerHTML = '';
    }
  }

  async function ensureFullScreenOcr() {
    if (fullScreenOcrLines) {
      renderFullScreenOcrOverlay(fullScreenOcrLines);
      return;
    }
    if (!sourceImg || isMockDemo) return;
    isOcrRunning = true;
    capsuleHint.textContent = 'Scanning screen text...';
    try {
      const c = document.createElement('canvas');
      c.width = sourceImg.naturalWidth;
      c.height = sourceImg.naturalHeight;
      c.getContext('2d').drawImage(sourceImg, 0, 0);
      const pngBase64 = c.toDataURL('image/png').split(',')[1];
      const res = await window.loopSearch.runOcr(pngBase64);
      fullScreenOcrLines = res && Array.isArray(res.lines) ? res.lines : [];
      if (activeMode === 'text') {
        renderFullScreenOcrOverlay(fullScreenOcrLines);
        capsuleHint.textContent =
          fullScreenOcrLines.length > 0
            ? `Click any text to copy (${fullScreenOcrLines.length} lines)`
            : 'No selectable text detected here — try Box mode';
      }
    } finally {
      isOcrRunning = false;
    }
  }

  function renderFullScreenOcrOverlay(lines) {
    ocrLayer.innerHTML = '';
    if (!lines || lines.length === 0) return;
    for (const line of lines) {
      const box = document.createElement('div');
      box.className = 'ocr-word-box';
      box.style.left = `${line.x * screenW - 3}px`;
      box.style.top = `${line.y * screenH - 2}px`;
      box.style.width = `${Math.max(12, line.w * screenW + 6)}px`;
      box.style.height = `${Math.max(14, line.h * screenH + 4)}px`;
      box.title = `Click to copy: ${line.text}`;
      box.onclick = async (e) => {
        e.stopPropagation();
        await window.loopSearch.copyText(line.text);
        window.loopSearch.showToast(`Copied: ${line.text.slice(0, 32)}`, 'success');
      };
      ocrLayer.appendChild(box);
    }
  }

  function emitParticles(x, y, count = 4, speed = 70) {
    const palette = GLOW_PALETTES[settings.glowTheme || 'apple'] || GLOW_PALETTES.apple;
    for (let i = 0; i < count; i++) {
      const ang = Math.random() * Math.PI * 2;
      const sp = (0.3 + Math.random() * 0.7) * speed;
      particles.push({
        x,
        y,
        vx: Math.cos(ang) * sp,
        vy: Math.sin(ang) * sp,
        life: 0,
        maxLife: 0.45 + Math.random() * 0.45,
        r: 1.4 + Math.random() * 2.2,
        color: palette[i % palette.length]
      });
    }
  }

  function roundedRectPath(ctx, x, y, w, h, r) {
    const rad = Math.max(0, Math.min(r, w / 2, h / 2));
    ctx.beginPath();
    ctx.moveTo(x + rad, y);
    ctx.lineTo(x + w - rad, y);
    ctx.quadraticCurveTo(x + w, y, x + w, y + rad);
    ctx.lineTo(x + w, y + h - rad);
    ctx.quadraticCurveTo(x + w, y + h, x + w - rad, y + h);
    ctx.lineTo(x + rad, y + h);
    ctx.quadraticCurveTo(x, y + h, x, y + h - rad);
    ctx.lineTo(x, y + rad);
    ctx.quadraticCurveTo(x, y, x + rad, y);
    ctx.closePath();
  }

  function buildFreehandPath(ctx, pts, closePath = false) {
    if (!pts || pts.length < 2) return;
    ctx.beginPath();
    ctx.moveTo(pts[0].x, pts[0].y);
    for (let i = 1; i < pts.length - 1; i++) {
      const mx = (pts[i].x + pts[i + 1].x) * 0.5;
      const my = (pts[i].y + pts[i + 1].y) * 0.5;
      ctx.quadraticCurveTo(pts[i].x, pts[i].y, mx, my);
    }
    const last = pts[pts.length - 1];
    ctx.lineTo(last.x, last.y);
    if (closePath) ctx.closePath();
  }

  function makeSelectionPath(ctx, kind, rect, pts, closed = true) {
    if (kind === 'freehand' && pts && pts.length > 2) {
      buildFreehandPath(ctx, pts, closed);
    } else if (rect) {
      roundedRectPath(ctx, rect.x, rect.y, rect.w, rect.h, 16);
    }
  }

  function drawLuminousStrokeAndBloom(ctx, kind, rect, pts, elapsed, closed = true) {
    const cx = rect ? rect.x + rect.w / 2 : screenW / 2;
    const cy = rect ? rect.y + rect.h / 2 : screenH / 2;
    const palette = GLOW_PALETTES[settings.glowTheme || 'apple'] || GLOW_PALETTES.apple;
    const intensityMult =
      settings.glowIntensity === 'vivid' ? 1.35 : settings.glowIntensity === 'subtle' ? 0.65 : 1;

    let grad;
    if (typeof ctx.createConicGradient === 'function') {
      grad = ctx.createConicGradient(elapsed * 1.45, cx, cy);
      palette.forEach((col, i) => grad.addColorStop(i / (palette.length - 1), col));
    } else {
      grad = ctx.createLinearGradient(cx - 120, cy - 120, cx + 120, cy + 120);
      grad.addColorStop(0, palette[0]);
      grad.addColorStop(0.5, palette[1]);
      grad.addColorStop(1, palette[2]);
    }

    const bloomRings = [
      { width: 24, alpha: 0.06 * intensityMult },
      { width: 17, alpha: 0.10 * intensityMult },
      { width: 11, alpha: 0.16 * intensityMult },
      { width: 6.5, alpha: 0.28 * intensityMult },
      { width: 3.4, alpha: 0.58 * intensityMult }
    ];

    ctx.save();
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    ctx.strokeStyle = grad;
    for (const ring of bloomRings) {
      makeSelectionPath(ctx, kind, rect, pts, closed);
      ctx.globalAlpha = Math.min(1, ring.alpha);
      ctx.lineWidth = ring.width;
      ctx.stroke();
    }

    // Sharp white-cyan inner specular hairline
    makeSelectionPath(ctx, kind, rect, pts, closed);
    ctx.globalAlpha = 0.94;
    ctx.lineWidth = 1.65;
    ctx.strokeStyle = '#e0f2fe';
    ctx.stroke();
    ctx.restore();
  }

  function drawCornerBrackets(ctx, rect, settledAt, now) {
    if (!rect || rect.w < 28 || rect.h < 28) return;
    const dt = Math.max(0, (now - (settledAt || now)) / 1000);
    const springBoost = dt < 0.5 ? 1 + 0.08 * Math.exp(-dt * 9) * Math.cos(dt * 20) : 1;
    const pad = -3 * springBoost;
    const x = rect.x + pad;
    const y = rect.y + pad;
    const w = rect.w - pad * 2;
    const h = rect.h - pad * 2;
    const len = Math.min(18, Math.min(w, h) * 0.26);

    ctx.save();
    ctx.strokeStyle = '#ffffff';
    ctx.shadowColor = '#38bdf8';
    ctx.shadowBlur = 8;
    ctx.lineWidth = 2.6;
    ctx.lineCap = 'round';

    const corners = [
      [x, y + len, x, y, x + len, y],
      [x + w - len, y, x + w, y, x + w, y + len],
      [x, y + h - len, x, y + h, x + len, y + h],
      [x + w - len, y + h, x + w, y + h, x + w, y + h - len]
    ];
    for (const [x1, y1, cx, cy, x2, y2] of corners) {
      ctx.beginPath();
      ctx.moveTo(x1, y1);
      ctx.lineTo(cx, cy);
      ctx.lineTo(x2, y2);
      ctx.stroke();
    }
    ctx.restore();
  }

  function renderFxFrame(now) {
    const elapsed = (now - overlayOpenedAt) / 1000;
    const style = settings.visualStylePreset || 'crystal';
    const intensityMult =
      settings.glowIntensity === 'vivid' ? 1.35 : settings.glowIntensity === 'subtle' ? 0.6 : 1;
    const palette = GLOW_PALETTES[settings.glowTheme || 'apple'] || GLOW_PALETTES.apple;

    fxCtx.clearRect(0, 0, screenW, screenH);

    // 1. Focus-settle corner bezel (0 -> 20px smooth rounding over 0.45s)
    const settleProgress = Math.min(1, elapsed / 0.42);
    const easeSettle = 1 - Math.pow(1 - settleProgress, 3);
    const bezelRadius = 20 * easeSettle;

    // Subtle twilight tint when idle or spotlight around active selection
    const activeSel =
      interaction && interaction.kind === 'draw-box' && selectionRect
        ? { kind: 'box', rect: selectionRect, points: null }
        : interaction && interaction.kind === 'draw-free' && freehandPoints.length > 2
        ? { kind: 'freehand', rect: computeBounds(freehandPoints), points: freehandPoints, open: true }
        : settledSelection;

    fxCtx.save();
    fxCtx.beginPath();
    fxCtx.rect(0, 0, screenW, screenH);
    if (activeSel && activeSel.rect && activeSel.rect.w > 6 && activeSel.rect.h > 6) {
      if (activeSel.kind === 'freehand' && activeSel.points && activeSel.points.length > 2) {
        fxCtx.moveTo(activeSel.points[0].x, activeSel.points[0].y);
        for (let i = 1; i < activeSel.points.length; i++) {
          fxCtx.lineTo(activeSel.points[i].x, activeSel.points[i].y);
        }
        fxCtx.closePath();
      } else {
        const r = activeSel.rect;
        const rad = Math.min(16, r.w / 2, r.h / 2);
        fxCtx.moveTo(r.x + rad, r.y);
        fxCtx.lineTo(r.x + r.w - rad, r.y);
        fxCtx.quadraticCurveTo(r.x + r.w, r.y, r.x + r.w, r.y + rad);
        fxCtx.lineTo(r.x + r.w, r.y + r.h - rad);
        fxCtx.quadraticCurveTo(r.x + r.w, r.y + r.h, r.x + r.w - rad, r.y + r.h);
        fxCtx.lineTo(r.x + rad, r.y + r.h);
        fxCtx.quadraticCurveTo(r.x, r.y + r.h, r.x, r.y + r.h - rad);
        fxCtx.lineTo(r.x, r.y + rad);
        fxCtx.quadraticCurveTo(r.x, r.y, r.x + rad, r.y);
        fxCtx.closePath();
      }
      fxCtx.fillStyle = `rgba(4, 7, 18, ${0.42 * easeSettle})`;
    } else {
      fxCtx.fillStyle = `rgba(4, 8, 22, ${0.18 * easeSettle})`;
    }
    fxCtx.fill('evenodd');
    fxCtx.restore();

    // Outer settled screen glass vignette rim
    if (bezelRadius > 2) {
      fxCtx.save();
      fxCtx.beginPath();
      fxCtx.rect(0, 0, screenW, screenH);
      const rad = bezelRadius;
      fxCtx.moveTo(4 + rad, 4);
      fxCtx.lineTo(screenW - 4 - rad, 4);
      fxCtx.quadraticCurveTo(screenW - 4, 4, screenW - 4, 4 + rad);
      fxCtx.lineTo(screenW - 4, screenH - 4 - rad);
      fxCtx.quadraticCurveTo(screenW - 4, screenH - 4, screenW - 4 - rad, screenH - 4);
      fxCtx.lineTo(4 + rad, screenH - 4);
      fxCtx.quadraticCurveTo(4, screenH - 4, 4, screenH - 4 - rad);
      fxCtx.lineTo(4, 4 + rad);
      fxCtx.quadraticCurveTo(4, 4, 4 + rad, 4);
      fxCtx.closePath();
      fxCtx.fillStyle = 'rgba(2, 4, 10, 0.72)';
      fxCtx.fill('evenodd');

      roundedRectPath(fxCtx, 4, 4, screenW - 8, screenH - 8, bezelRadius);
      fxCtx.strokeStyle = 'rgba(125, 211, 252, 0.28)';
      fxCtx.lineWidth = 1.5;
      fxCtx.stroke();
      fxCtx.restore();
    }

    // 2. Twilight Aurora & Horizon Bottom Edge Glow Bar
    if (style !== 'stealth') {
      const styleGain = style === 'aurora' ? 1.25 : style === 'minimal' ? 0.45 : 0.85;
      const gAlpha = Math.min(0.45, 0.22 * intensityMult * styleGain);
      const hGrad = fxCtx.createRadialGradient(
        screenW * (0.5 + 0.08 * Math.sin(elapsed * 0.7)),
        screenH + 40,
        20,
        screenW * 0.5,
        screenH + 40,
        screenW * 0.55
      );
      hGrad.addColorStop(0, palette[0]);
      hGrad.addColorStop(0.5, palette[1]);
      hGrad.addColorStop(1, 'transparent');
      fxCtx.save();
      fxCtx.globalAlpha = gAlpha;
      fxCtx.fillStyle = hGrad;
      fxCtx.fillRect(0, screenH * 0.55, screenW, screenH * 0.45);
      fxCtx.restore();
    }

    // 3. Entry Light Wave Sweep (0.68s upward shimmer wave)
    if (elapsed < 0.74) {
      const wp = elapsed / 0.68;
      const wy = screenH * (1 - wp) - 40;
      const waveAlpha = Math.sin(Math.min(1, wp) * Math.PI) * 0.48 * intensityMult;
      const wg = fxCtx.createLinearGradient(0, wy - 90, 0, wy + 90);
      wg.addColorStop(0, 'transparent');
      wg.addColorStop(0.42, palette[1]);
      wg.addColorStop(0.52, '#ffffff');
      wg.addColorStop(0.62, palette[0]);
      wg.addColorStop(1, 'transparent');
      fxCtx.save();
      fxCtx.globalAlpha = Math.max(0, waveAlpha);
      fxCtx.fillStyle = wg;
      fxCtx.fillRect(0, wy - 90, screenW, 180);
      fxCtx.restore();
    }

    // 4. Twinkling 4-point Stars + Floating Ambient Sparks
    if (style !== 'stealth') {
      const starLimit = style === 'minimal' ? 10 : 26;
      fxCtx.save();
      for (let i = 0; i < starLimit; i++) {
        const s = stars[i];
        const sx = s.x * screenW;
        const sy = s.y * screenH;
        const a = (0.2 + 0.8 * (0.5 + 0.5 * Math.sin(elapsed * s.speed + s.phase))) * 0.55;
        fxCtx.globalAlpha = a * intensityMult;
        fxCtx.fillStyle = '#e0f2fe';
        const r = s.size;
        fxCtx.beginPath();
        fxCtx.moveTo(sx, sy - r);
        fxCtx.quadraticCurveTo(sx, sy, sx + r, sy);
        fxCtx.quadraticCurveTo(sx, sy, sx, sy + r);
        fxCtx.quadraticCurveTo(sx, sy, sx - r, sy);
        fxCtx.quadraticCurveTo(sx, sy, sx, sy - r);
        fxCtx.fill();
      }
      for (const sp of ambientSparks) {
        const py = ((sp.y - elapsed * sp.vy) % 1 + 1) % 1;
        fxCtx.globalAlpha = sp.alpha * intensityMult;
        fxCtx.fillStyle = palette[0];
        fxCtx.beginPath();
        fxCtx.arc(sp.x * screenW, py * screenH, sp.r, 0, Math.PI * 2);
        fxCtx.fill();
      }
      fxCtx.restore();
    }

    // 5. Active Selection Luminous 12-Ring Bloom + Brackets + Scan Beam
    if (activeSel && activeSel.rect && activeSel.rect.w > 4 && activeSel.rect.h > 4) {
      drawLuminousStrokeAndBloom(
        fxCtx,
        activeSel.kind,
        activeSel.rect,
        activeSel.points,
        elapsed,
        !activeSel.open
      );
      if (activeSel.kind === 'box') {
        drawCornerBrackets(fxCtx, activeSel.rect, activeSel.settledAt, now);
      }

      if ((isSearching || isOcrRunning) && !activeSel.open) {
        fxCtx.save();
        makeSelectionPath(fxCtx, activeSel.kind, activeSel.rect, activeSel.points, true);
        fxCtx.clip();
        const beamFrac = 0.5 + 0.5 * Math.sin(elapsed * 4.2);
        const by = activeSel.rect.y + beamFrac * activeSel.rect.h;
        const bg = fxCtx.createLinearGradient(0, by - 26, 0, by + 26);
        bg.addColorStop(0, 'transparent');
        bg.addColorStop(0.5, 'rgba(56, 189, 248, 0.42)');
        bg.addColorStop(1, 'transparent');
        fxCtx.fillStyle = bg;
        fxCtx.fillRect(activeSel.rect.x, by - 26, activeSel.rect.w, 52);
        fxCtx.restore();
      }
    }

    // 6. Tap Shockwave Ripples
    for (let i = ripples.length - 1; i >= 0; i--) {
      const rp = ripples[i];
      const dt = (now - rp.born) / 1000;
      if (dt > 0.72) {
        ripples.splice(i, 1);
        continue;
      }
      const p = dt / 0.72;
      const rad = 14 + 126 * (1 - Math.pow(1 - p, 3));
      const a = (1 - p) * 0.85;
      fxCtx.save();
      fxCtx.strokeStyle = palette[0];
      fxCtx.globalAlpha = a;
      fxCtx.lineWidth = 3 * (1 - p) + 0.8;
      fxCtx.beginPath();
      fxCtx.arc(rp.x, rp.y, rad, 0, Math.PI * 2);
      fxCtx.stroke();
      fxCtx.restore();
    }

    // 7. Interactive Drag / Burst Particles
    for (let i = particles.length - 1; i >= 0; i--) {
      const pt = particles[i];
      pt.life += 1 / 60;
      if (pt.life >= pt.maxLife) {
        particles.splice(i, 1);
        continue;
      }
      pt.x += pt.vx * (1 / 60);
      pt.y += pt.vy * (1 / 60);
      pt.vx *= 0.94;
      pt.vy *= 0.94;
      const a = 1 - pt.life / pt.maxLife;
      fxCtx.save();
      fxCtx.globalAlpha = a * 0.9;
      fxCtx.fillStyle = pt.color;
      fxCtx.beginPath();
      fxCtx.arc(pt.x, pt.y, pt.r * a + 0.5, 0, Math.PI * 2);
      fxCtx.fill();
      fxCtx.restore();
    }

    requestAnimationFrame(renderFxFrame);
  }

  function computeBounds(pts) {
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const p of pts) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    return {
      x: Math.max(0, minX),
      y: Math.max(0, minY),
      w: Math.max(1, maxX - minX),
      h: Math.max(1, maxY - minY)
    };
  }

  function pointInRect(px, py, r) {
    return r && px >= r.x && px <= r.x + r.w && py >= r.y && py <= r.y + r.h;
  }

  function hitCornerHandle(px, py, r) {
    if (!r) return null;
    const hit = 14;
    const corners = {
      nw: [r.x, r.y],
      ne: [r.x + r.w, r.y],
      sw: [r.x, r.y + r.h],
      se: [r.x + r.w, r.y + r.h]
    };
    for (const [k, [cx, cy]] of Object.entries(corners)) {
      if (Math.hypot(px - cx, py - cy) <= hit) return k;
    }
    return null;
  }

  // Pointer interactions on FX Canvas
  fxCanvas.addEventListener('pointerdown', (e) => {
    if (e.button !== 0) return;
    historyPopover.classList.remove('open');
    const x = e.clientX;
    const y = e.clientY;

    if (activeMode === 'tap') {
      ripples.push({ x, y, born: performance.now() });
      ripples.push({ x, y, born: performance.now() + 90 });
      emitParticles(x, y, 16, 130);
      const boxW = Math.min(260, Math.round(screenW * 0.22));
      const boxH = Math.min(180, Math.round(screenH * 0.22));
      const rx = Math.max(12, Math.min(screenW - boxW - 12, x - boxW / 2));
      const ry = Math.max(12, Math.min(screenH - boxH - 12, y - boxH / 2));
      const rect = { x: rx, y: ry, w: boxW, h: boxH };
      settledSelection = { kind: 'box', rect, points: null, settledAt: performance.now() };
      runSelectionSearch(settledSelection);
      return;
    }

    if (settledSelection && settledSelection.kind === 'box') {
      const corner = hitCornerHandle(x, y, settledSelection.rect);
      if (corner) {
        interaction = {
          kind: 'resize-box',
          startX: x,
          startY: y,
          corner,
          origRect: { ...settledSelection.rect }
        };
        fxCanvas.setPointerCapture(e.pointerId);
        return;
      }
      if (pointInRect(x, y, settledSelection.rect)) {
        interaction = {
          kind: 'move-box',
          startX: x,
          startY: y,
          origRect: { ...settledSelection.rect }
        };
        fxCanvas.setPointerCapture(e.pointerId);
        return;
      }
    }

    if (activeMode === 'freehand') {
      freehandPoints = [{ x, y }];
      selectionRect = null;
      settledSelection = null;
      interaction = { kind: 'draw-free', startX: x, startY: y };
      fxCanvas.setPointerCapture(e.pointerId);
      return;
    }

    // Box or Text drag
    selectionRect = { x, y, w: 0, h: 0 };
    settledSelection = null;
    interaction = { kind: 'draw-box', startX: x, startY: y };
    fxCanvas.setPointerCapture(e.pointerId);
  });

  fxCanvas.addEventListener('pointermove', (e) => {
    const x = e.clientX;
    const y = e.clientY;

    if (!interaction) {
      if (settledSelection && settledSelection.kind === 'box') {
        const corner = hitCornerHandle(x, y, settledSelection.rect);
        if (corner === 'nw' || corner === 'se') fxCanvas.style.cursor = 'nwse-resize';
        else if (corner === 'ne' || corner === 'sw') fxCanvas.style.cursor = 'nesw-resize';
        else if (pointInRect(x, y, settledSelection.rect)) fxCanvas.style.cursor = 'grab';
        else fxCanvas.style.cursor = activeMode === 'tap' ? 'pointer' : 'crosshair';
      }
      return;
    }

    if (interaction.kind === 'draw-box') {
      const rx = Math.min(interaction.startX, x);
      const ry = Math.min(interaction.startY, y);
      const rw = Math.abs(x - interaction.startX);
      const rh = Math.abs(y - interaction.startY);
      selectionRect = { x: rx, y: ry, w: rw, h: rh };
      if (Math.random() < 0.45) emitParticles(x, y, 2, 55);
    } else if (interaction.kind === 'draw-free') {
      const prev = freehandPoints[freehandPoints.length - 1];
      if (!prev || Math.hypot(x - prev.x, y - prev.y) > 4) {
        freehandPoints.push({ x, y });
        emitParticles(x, y, 2, 50);
      }
    } else if (interaction.kind === 'move-box') {
      const dx = x - interaction.startX;
      const dy = y - interaction.startY;
      const r = interaction.origRect;
      settledSelection.rect = {
        x: Math.max(4, Math.min(screenW - r.w - 4, r.x + dx)),
        y: Math.max(4, Math.min(screenH - r.h - 4, r.y + dy)),
        w: r.w,
        h: r.h
      };
    } else if (interaction.kind === 'resize-box') {
      const o = interaction.origRect;
      let left = o.x, top = o.y, right = o.x + o.w, bottom = o.y + o.h;
      if (interaction.corner.includes('w')) left = Math.min(right - 24, x);
      if (interaction.corner.includes('e')) right = Math.max(left + 24, x);
      if (interaction.corner.includes('n')) top = Math.min(bottom - 24, y);
      if (interaction.corner.includes('s')) bottom = Math.max(top + 24, y);
      settledSelection.rect = { x: left, y: top, w: right - left, h: bottom - top };
    }
  });

  fxCanvas.addEventListener('pointerup', (e) => {
    if (!interaction) return;
    const act = interaction;
    interaction = null;

    if (act.kind === 'draw-box') {
      if (selectionRect && selectionRect.w >= 16 && selectionRect.h >= 16) {
        emitParticles(selectionRect.x + selectionRect.w / 2, selectionRect.y + selectionRect.h / 2, 18, 150);
        settledSelection = { kind: 'box', rect: selectionRect, points: null, settledAt: performance.now() };
        runSelectionSearch(settledSelection);
      }
    } else if (act.kind === 'draw-free') {
      if (freehandPoints.length >= 6) {
        const bounds = computeBounds(freehandPoints);
        if (bounds.w >= 18 && bounds.h >= 18) {
          emitParticles(bounds.x + bounds.w / 2, bounds.y + bounds.h / 2, 20, 155);
          settledSelection = {
            kind: 'freehand',
            rect: bounds,
            points: [...freehandPoints],
            settledAt: performance.now()
          };
          runSelectionSearch(settledSelection);
        }
      }
    } else if (act.kind === 'move-box' || act.kind === 'resize-box') {
      if (settledSelection) {
        settledSelection.settledAt = performance.now();
        runSelectionSearch(settledSelection);
      }
    }
  });

  function cropSelectionToImages(sel) {
    const r = sel.rect;
    const scaleX = sourceImg.naturalWidth / screenW;
    const scaleY = sourceImg.naturalHeight / screenH;
    const sx = Math.max(0, Math.round(r.x * scaleX));
    const sy = Math.max(0, Math.round(r.y * scaleY));
    const sw = Math.max(8, Math.min(sourceImg.naturalWidth - sx, Math.round(r.w * scaleX)));
    const sh = Math.max(8, Math.min(sourceImg.naturalHeight - sy, Math.round(r.h * scaleY)));

    const pngCanvas = document.createElement('canvas');
    pngCanvas.width = sw;
    pngCanvas.height = sh;
    const pCtx = pngCanvas.getContext('2d');

    if (sel.kind === 'freehand' && sel.points && sel.points.length > 2) {
      pCtx.fillStyle = '#0c1018';
      pCtx.fillRect(0, 0, sw, sh);
      pCtx.save();
      pCtx.beginPath();
      sel.points.forEach((pt, idx) => {
        const lx = (pt.x - r.x) * scaleX;
        const ly = (pt.y - r.y) * scaleY;
        if (idx === 0) pCtx.moveTo(lx, ly);
        else pCtx.lineTo(lx, ly);
      });
      pCtx.closePath();
      pCtx.clip();
      pCtx.drawImage(sourceImg, sx, sy, sw, sh, 0, 0, sw, sh);
      pCtx.restore();
    } else {
      pCtx.drawImage(sourceImg, sx, sy, sw, sh, 0, 0, sw, sh);
    }

    const rgba = pCtx.getImageData(0, 0, sw, sh);
    const pngDataUrl = pngCanvas.toDataURL('image/png');

    // Scale to maxDim = 1200 for fast crisp Lens JPEG upload
    const maxDim = 1200;
    const jpegScale = Math.min(1, maxDim / Math.max(sw, sh));
    const jw = Math.max(8, Math.round(sw * jpegScale));
    const jh = Math.max(8, Math.round(sh * jpegScale));
    const jpegCanvas = document.createElement('canvas');
    jpegCanvas.width = jw;
    jpegCanvas.height = jh;
    jpegCanvas.getContext('2d').drawImage(pngCanvas, 0, 0, jw, jh);
    const jpegDataUrl = jpegCanvas.toDataURL('image/jpeg', 0.86);

    return {
      sw,
      sh,
      rgba,
      pngDataUrl,
      pngBase64: pngDataUrl.split(',')[1],
      jpegBase64: jpegDataUrl.split(',')[1]
    };
  }

  function placeResultsSheet(rect) {
    const margin = 18;
    const sheetW = resultsSheet.offsetWidth || 416;
    const sheetH = resultsSheet.offsetHeight || 580;
    const maxY = screenH - (safeInsets.bottom || 0) - 82 - sheetH;
    const clampedY = Math.max(margin + (safeInsets.top || 0), Math.min(maxY, rect.y - 12));

    let x;
    if (rect.x + rect.w + margin + sheetW <= screenW - margin) {
      x = rect.x + rect.w + margin;
    } else if (rect.x - margin - sheetW >= margin) {
      x = rect.x - margin - sheetW;
    } else {
      x = Math.max(margin, Math.min(screenW - sheetW - margin, screenW - sheetW - 24));
    }

    resultsSheet.style.left = `${Math.round(x)}px`;
    resultsSheet.style.top = `${Math.round(clampedY)}px`;
  }

  function renderSmartChips({ ocrText, qrPayload, urlMatch, mathResult, colorInfo, isLowInfo }) {
    smartChipsBar.innerHTML = '';

    const addChip = (html, onClick, accent = false) => {
      const btn = document.createElement('button');
      btn.className = 'smart-chip' + (accent ? ' accent' : '');
      btn.innerHTML = html;
      btn.onclick = onClick;
      smartChipsBar.appendChild(btn);
    };

    if (qrPayload) {
      const isUrl = /^https?:\/\//i.test(qrPayload);
      addChip(
        `${Icons.search(12)}<span>${isUrl ? 'QR Link: ' + displayHostForUrl(qrPayload) : 'Copy QR'}</span>`,
        () => {
          if (isUrl) window.loopSearch.openExternal(qrPayload);
          else {
            window.loopSearch.copyText(qrPayload);
            window.loopSearch.showToast('QR payload copied', 'success');
          }
        },
        true
      );
    }

    if (urlMatch) {
      addChip(
        `${Icons.external(12)}<span>Open ${displayHostForUrl(urlMatch)}</span>`,
        () => window.loopSearch.openExternal(urlMatch),
        true
      );
    }

    if (mathResult) {
      addChip(
        `<span>= ${mathResult.formatted}</span>`,
        async () => {
          await window.loopSearch.copyText(mathResult.formatted);
          window.loopSearch.showToast(`Copied answer: ${mathResult.formatted}`, 'success');
        },
        true
      );
    }

    if (colorInfo) {
      addChip(
        `<span class="color-swatch-circle" style="background:${colorInfo.hex}"></span><span>${colorInfo.hex}</span>`,
        async () => {
          await window.loopSearch.copyText(colorInfo.hex);
          window.loopSearch.showToast(`Copied color ${colorInfo.hex}`, 'success');
        }
      );
    }

    if (ocrText) {
      addChip(`${Icons.copy(12)}<span>Copy Text</span>`, async () => {
        await window.loopSearch.copyText(ocrText);
        window.loopSearch.showToast('Recognized text copied', 'success');
      });
      addChip(`${Icons.translate(12)}<span>Translate</span>`, () => {
        const url = `https://translate.google.com/?sl=auto&tl=en&text=${encodeURIComponent(ocrText)}&op=translate`;
        navigateWebview(url);
      });
    }

    addChip(`${Icons.sparkle(12)}<span>Explain</span>`, () => runExplainAi(), true);
    addChip(`${Icons.pin(12)}<span>Pin</span>`, () => pinCurrentCapture());
    addChip(`${Icons.save(12)}<span>Save</span>`, () => window.loopSearch.saveCapturePng(lastCropPngBase64));

    if (isLowInfo && !ocrText && !qrPayload) {
      ocrPreviewLine.style.display = 'block';
      ocrPreviewLine.textContent = 'Blank or uniform area detected — try widening your selection for clearer visual matches.';
    }
  }

  function navigateWebview(url) {
    if (!url) return;
    currentWebUrl = url;
    wvLoader.classList.remove('hidden');
    loaderStatusText.textContent = 'Loading results...';
    webview.src = url;
  }

  async function runSelectionSearch(sel) {
    const cropped = cropSelectionToImages(sel);
    lastCropPngBase64 = cropped.pngBase64;
    lastCropJpegBase64 = cropped.jpegBase64;
    lastCropDataUrl = cropped.pngDataUrl;
    lastCropW = cropped.sw;
    lastCropH = cropped.sh;

    cropThumb.src = cropped.pngDataUrl;
    aiAnswerCard.style.display = 'none';
    ocrPreviewLine.style.display = 'none';
    resultsSheet.classList.add('open');
    placeResultsSheet(sel.rect);

    const qrPayload = window.loopSearch.decodeQr(cropped.rgba.data, cropped.sw, cropped.sh);
    const colorInfo = extractDominantColor(cropped.rgba.data, cropped.sw, cropped.sh);
    const detailInfo = analyzeRegionDetail(cropped.rgba.data, cropped.sw, cropped.sh);

    lastOcrText = '';
    renderSmartChips({
      ocrText: isMockDemo ? 'JetBrains IntelliJ IDEA 2026.2  128 + 256  https://github.com' : '',
      qrPayload,
      urlMatch: isMockDemo ? 'https://github.com' : null,
      mathResult: isMockDemo ? { formatted: '384' } : null,
      colorInfo: isMockDemo ? { hex: '#38BDF8' } : colorInfo,
      isLowInfo: detailInfo.isLowInfo
    });

    if (isMockDemo) {
      lastOcrText = 'JetBrains IntelliJ IDEA 2026.2 • 128 + 256 = ? • https://github.com';
      ocrPreviewLine.style.display = 'block';
      ocrPreviewLine.textContent = `OCR: ${lastOcrText}`;
      loaderStatusText.textContent = 'Searching with Google Lens...';
      return;
    }

    isSearching = true;
    wvLoader.classList.remove('hidden');
    loaderStatusText.textContent = 'Searching with Google Lens...';

    // Run offline OCR + Google Lens upload concurrently
    const ocrPromise = window.loopSearch.runOcr(cropped.pngBase64).then((res) => {
      const txt = (res && res.text ? res.text : '').trim();
      lastOcrText = txt;
      if (txt) {
        ocrPreviewLine.style.display = 'block';
        ocrPreviewLine.textContent = txt.replace(/\s+/g, ' ');
        if (settings.autoCopyOcrText) {
          window.loopSearch.copyText(txt);
        }
      }
      renderSmartChips({
        ocrText: txt,
        qrPayload,
        urlMatch: extractPrimaryURL(txt),
        mathResult: evaluateMathExpression(txt),
        colorInfo,
        isLowInfo: detailInfo.isLowInfo
      });
      return txt;
    });

    const lensPromise = window.loopSearch.uploadToGoogleLens(cropped.jpegBase64);

    try {
      const [ocrText, lensRes] = await Promise.all([ocrPromise, lensPromise]);
      lastLensUrl = lensRes && lensRes.url ? lensRes.url : buildSearchUrl(activeEngine, ocrText);

      if (settings.openInBrowserFallback) {
        window.loopSearch.openExternal(lastLensUrl);
        window.loopSearch.showToast('Opened results in default browser', 'success');
      } else if (activeEngine === 'googleLens' && lensRes && lensRes.ok) {
        navigateWebview(lensRes.url);
      } else if (ocrText) {
        navigateWebview(buildSearchUrl(activeEngine, ocrText));
      } else {
        navigateWebview(lastLensUrl);
      }

      await window.loopSearch.addHistoryItem({
        mode: sel.kind,
        query: followUpInput.value || '',
        ocrText: ocrText || '',
        lensUrl: lastLensUrl,
        thumbnailDataUrl: cropped.pngDataUrl
      });
      await window.loopSearch.recordSearchSuccess();
    } catch {
      loaderStatusText.textContent = 'Visual upload failed — use browser or Ask AI';
    } finally {
      isSearching = false;
    }
  }

  async function runExplainAi(customPrompt = null) {
    const prompt =
      customPrompt ||
      (followUpInput.value.trim()
        ? followUpInput.value.trim()
        : 'Explain clearly what is shown in this captured region.');

    if (settings.hasGeminiApiKey) {
      aiAnswerCard.style.display = 'flex';
      aiAnswerText.textContent = 'Thinking with Gemini 2.5 Flash...';
      const res = await window.loopSearch.callGemini({
        imageBase64: lastCropJpegBase64,
        prompt
      });
      aiAnswerText.textContent = res.ok ? res.answer : `AI Error: ${res.error}`;
      return;
    }

    const q = lastOcrText ? `${prompt}: ${lastOcrText}` : prompt;
    navigateWebview(buildSearchUrl('aiExplain', q));
  }

  function pinCurrentCapture() {
    if (!lastCropPngBase64) return;
    window.loopSearch.pinCapture({
      pngBase64: lastCropPngBase64,
      width: lastCropW,
      height: lastCropH,
      title: lastOcrText ? lastOcrText.slice(0, 32) : 'Pinned Capture'
    });
  }

  // WebView theming + navigation hooks
  async function syncWebviewTheme() {
    if (!currentWebUrl || !shouldApplyWebDarkCss(currentWebUrl)) return;
    try {
      const script = await window.loopSearch.getLensThemeScript(webDarkMode);
      await webview.executeJavaScript(script, false);
    } catch {}
  }

  webview.addEventListener('dom-ready', syncWebviewTheme);
  webview.addEventListener('did-navigate', (e) => {
    currentWebUrl = e.url;
    syncWebviewTheme();
  });
  webview.addEventListener('did-stop-loading', () => {
    if (!isMockDemo) wvLoader.classList.add('hidden');
  });

  // Capsule & Sheet UI buttons
  document.querySelectorAll('.mode-pill').forEach((btn) => {
    btn.onclick = () => setMode(btn.dataset.mode);
  });
  document.getElementById('cap-close-btn').onclick = () => window.loopSearch.closeOverlay();
  document.getElementById('cap-studio-btn').onclick = () => window.loopSearch.openWindow('settings');
  document.getElementById('cap-history-btn').onclick = async () => {
    historyPopover.classList.toggle('open');
    if (historyPopover.classList.contains('open')) {
      const items = await window.loopSearch.getHistory();
      renderHistoryList(items);
    }
  };
  document.getElementById('clear-hist-btn').onclick = async () => {
    await window.loopSearch.clearHistory();
    renderHistoryList([]);
  };

  function renderHistoryList(items) {
    histList.innerHTML = '';
    if (!items || items.length === 0) {
      histList.innerHTML = `<div style="font-size:12px;color:var(--text-secondary);padding:12px;text-align:center;">No captures yet. Draw a selection to start!</div>`;
      return;
    }
    for (const item of items) {
      const row = document.createElement('div');
      row.className = 'hist-item';
      row.innerHTML = `
        <img class="hist-thumb" src="${item.thumbnailDataUrl || ''}" />
        <div style="min-width:0;flex:1;">
          <div style="font-size:12px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${
            item.query || item.ocrText || `${item.mode || 'Box'} capture`
          }</div>
          <div style="font-size:10.5px;color:var(--text-muted);">${new Date(item.createdAt).toLocaleTimeString()}</div>
        </div>`;
      row.onclick = () => {
        historyPopover.classList.remove('open');
        if (item.thumbnailDataUrl) cropThumb.src = item.thumbnailDataUrl;
        resultsSheet.classList.add('open');
        placeResultsSheet({ x: 80, y: 120, w: 280, h: 200 });
        if (item.lensUrl) navigateWebview(item.lensUrl);
      };
      histList.appendChild(row);
    }
  }

  document.getElementById('sheet-back-btn').onclick = () => {
    if (webview.canGoBack()) webview.goBack();
  };
  document.getElementById('engine-cycle-btn').onclick = () => {
    const nextIdx = (ENGINE_ORDER.indexOf(activeEngine) + 1) % ENGINE_ORDER.length;
    activeEngine = ENGINE_ORDER[nextIdx];
    document.getElementById('engine-cycle-btn').textContent = `${ENGINE_LABELS[activeEngine]} ▾`;
    if (followUpInput.value.trim()) {
      navigateWebview(buildSearchUrl(activeEngine, followUpInput.value));
    } else if (activeEngine === 'googleLens' && lastLensUrl) {
      navigateWebview(lastLensUrl);
    } else if (lastOcrText) {
      navigateWebview(buildSearchUrl(activeEngine, lastOcrText));
    }
  };
  document.getElementById('sheet-dark-btn').onclick = () => {
    webDarkMode = !webDarkMode;
    document.getElementById('sheet-dark-btn').innerHTML = webDarkMode ? Icons.moon(13) : Icons.sun(13);
    syncWebviewTheme();
  };
  document.getElementById('sheet-pin-btn').onclick = pinCurrentCapture;
  document.getElementById('sheet-ext-btn').onclick = () => {
    window.loopSearch.openExternal(currentWebUrl || lastLensUrl || 'https://lens.google.com/');
  };
  document.getElementById('sheet-expand-btn').onclick = () => {
    sheetExpanded = !sheetExpanded;
    resultsSheet.style.width = sheetExpanded ? '540px' : '416px';
    resultsSheet.style.height = sheetExpanded ? `${Math.min(720, screenH - 120)}px` : '580px';
  };
  document.getElementById('sheet-close-btn').onclick = () => {
    resultsSheet.classList.remove('open');
    settledSelection = null;
    selectionRect = null;
  };

  followUpInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      submitFollowUp();
    }
  });
  document.getElementById('follow-up-send').onclick = submitFollowUp;

  function submitFollowUp() {
    const q = followUpInput.value.trim();
    if (!q) return;
    if (settings.hasGeminiApiKey && activeEngine === 'aiExplain') {
      runExplainAi(q);
      return;
    }
    const combined = lastOcrText ? `${q} ${lastOcrText.slice(0, 120)}` : q;
    navigateWebview(buildSearchUrl(activeEngine === 'googleLens' ? 'google' : activeEngine, combined));
  }

  document.getElementById('copy-ai-btn').onclick = async () => {
    await window.loopSearch.copyText(aiAnswerText.textContent || '');
    window.loopSearch.showToast('AI answer copied', 'success');
  };
  document.getElementById('close-ai-btn').onclick = () => {
    aiAnswerCard.style.display = 'none';
  };

  // Drag Results Sheet by header + resize corner + drag Capsule
  makeElementDraggable(resultsSheet, document.getElementById('sheet-header'));
  makeElementDraggable(promptCapsule, document.getElementById('capsule-drag'), () => {
    promptCapsule.style.transform = 'none';
    promptCapsule.style.bottom = 'auto';
  });

  const resizeHandle = document.getElementById('sheet-resize-handle');
  resizeHandle.addEventListener('pointerdown', (e) => {
    e.stopPropagation();
    const startX = e.clientX;
    const startY = e.clientY;
    const startW = resultsSheet.offsetWidth;
    const startH = resultsSheet.offsetHeight;
    const onMove = (ev) => {
      resultsSheet.style.width = `${Math.max(340, Math.min(screenW - 40, startW + ev.clientX - startX))}px`;
      resultsSheet.style.height = `${Math.max(360, Math.min(screenH - 80, startH + ev.clientY - startY))}px`;
    };
    const onUp = () => {
      window.removeEventListener('pointermove', onMove);
      window.removeEventListener('pointerup', onUp);
    };
    window.addEventListener('pointermove', onMove);
    window.addEventListener('pointerup', onUp);
  });

  function makeElementDraggable(targetEl, handleEl, onFirstDrag = null) {
    handleEl.addEventListener('pointerdown', (e) => {
      if (e.target.closest('button')) return;
      e.preventDefault();
      if (onFirstDrag) onFirstDrag();
      const rect = targetEl.getBoundingClientRect();
      targetEl.style.left = `${rect.left}px`;
      targetEl.style.top = `${rect.top}px`;
      const ox = e.clientX - rect.left;
      const oy = e.clientY - rect.top;
      const onMove = (ev) => {
        const nx = Math.max(6, Math.min(screenW - rect.width - 6, ev.clientX - ox));
        const ny = Math.max(6, Math.min(screenH - rect.height - 6, ev.clientY - oy));
        targetEl.style.left = `${nx}px`;
        targetEl.style.top = `${ny}px`;
      };
      const onUp = () => {
        window.removeEventListener('pointermove', onMove);
        window.removeEventListener('pointerup', onUp);
      };
      window.addEventListener('pointermove', onMove);
      window.addEventListener('pointerup', onUp);
    });
  }

  // Global keyboard shortcuts inside overlay
  window.addEventListener('keydown', async (e) => {
    if (document.activeElement === followUpInput) {
      if (e.key === 'Escape') followUpInput.blur();
      return;
    }
    if (e.key === 'Escape') {
      window.loopSearch.closeOverlay();
    } else if (e.key === '1') {
      setMode('box');
    } else if (e.key === '2') {
      setMode('freehand');
    } else if (e.key === '3') {
      setMode('tap');
    } else if (e.key === '4') {
      setMode('text');
    } else if ((e.key === 'p' || e.key === 'P') && lastCropPngBase64) {
      pinCurrentCapture();
    } else if ((e.key === 's' || e.key === 'S') && lastCropPngBase64) {
      window.loopSearch.saveCapturePng(lastCropPngBase64);
    } else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'c' && lastCropDataUrl) {
      await window.loopSearch.copyImageDataUrl(lastCropDataUrl);
      window.loopSearch.showToast('Selection image copied', 'success');
    }
  });

  // Boot from Main Process payload
  window.loopSearch.onOverlayInit((payload) => {
    initData = payload;
    settings = payload.settings || {};
    safeInsets = payload.safeInsets || { top: 0, left: 0, right: 0, bottom: 0 };
    screenW = payload.screenWidth || window.innerWidth;
    screenH = payload.screenHeight || window.innerHeight;
    activeEngine = settings.searchEngine || 'googleLens';
    webDarkMode = (settings.effectiveTheme || 'dark') === 'dark';
    isMockDemo = Boolean(payload.mockSelection);

    applyGlassAppearance(settings);
    document.getElementById('engine-cycle-btn').textContent = `${ENGINE_LABELS[activeEngine] || 'Google Lens'} ▾`;
    document.getElementById('sheet-dark-btn').innerHTML = webDarkMode ? Icons.moon(13) : Icons.sun(13);
    promptCapsule.style.bottom = `${Math.max(18, (safeInsets.bottom || 0) + 18)}px`;

    setupCanvasSizes();
    setMode(payload.mode || settings.defaultMode || 'box');

    const img = new Image();
    img.onload = () => {
      sourceImg = img;
      overlayOpenedAt = performance.now();
      drawFrozenScreen();
      requestAnimationFrame(renderFxFrame);

      if (payload.mockSelection) {
        settledSelection = {
          kind: 'box',
          rect: payload.mockSelection,
          points: null,
          settledAt: performance.now()
        };
        emitParticles(
          payload.mockSelection.x + payload.mockSelection.w / 2,
          payload.mockSelection.y + payload.mockSelection.h / 2,
          20,
          150
        );
        runSelectionSearch(settledSelection);
      } else if (payload.clipboardImageDataUrl && payload._clipRect) {
        settledSelection = {
          kind: 'box',
          rect: payload._clipRect,
          points: null,
          settledAt: performance.now()
        };
        runSelectionSearch(settledSelection);
      }
    };
    img.src = payload.clipboardImageDataUrl || payload.screenshotDataUrl;
  });

  window.loopSearch.onSettingsChanged((nextSettings) => {
    settings = nextSettings;
    applyGlassAppearance(settings);
  });
})();
