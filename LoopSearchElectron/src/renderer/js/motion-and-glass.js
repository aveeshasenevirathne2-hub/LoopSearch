(function (root) {
  'use strict';

  const LoopIcons = {
    brandMark: (size = 24) => `
      <svg width="${size}" height="${size}" viewBox="0 0 32 32" fill="none">
        <defs>
          <linearGradient id="lsRing" x1="4" y1="4" x2="28" y2="28" gradientUnits="userSpaceOnUse">
            <stop offset="0%" stop-color="#e0f2fe"/>
            <stop offset="45%" stop-color="#38bdf8"/>
            <stop offset="100%" stop-color="#60a5fa"/>
          </linearGradient>
        </defs>
        <circle cx="14.5" cy="14.5" r="8.2" stroke="url(#lsRing)" stroke-width="2.6" stroke-linecap="round" stroke-dasharray="40 12"/>
        <circle cx="14.5" cy="14.5" r="3.4" fill="#7dd3fc" fill-opacity="0.9"/>
        <path d="M20.8 20.8L26.5 26.5" stroke="url(#lsRing)" stroke-width="2.8" stroke-linecap="round"/>
      </svg>`,
    close: (size = 14) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M18 6L6 18M6 6l12 12"/></svg>`,
    back: (size = 14) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 18l-6-6 6-6"/></svg>`,
    search: (size = 15) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.1" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.35-4.35"/></svg>`,
    box: (size = 14) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 9V6a2 2 0 0 1 2-2h3M15 4h3a2 2 0 0 1 2 2v3M20 15v3a2 2 0 0 1-2 2h-3M9 20H6a2 2 0 0 1-2-2v-3"/><rect x="8" y="8" width="8" height="8" rx="1.5" stroke-dasharray="2 2"/></svg>`,
    lasso: (size = 14) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4c5 0 8.5 2.8 8.5 6.8 0 4-3.7 7.2-8.7 7.2-4.8 0-8.3-2.9-8.3-6.7C3.5 7.2 7.2 4 12 4z"/><path d="M9 18c0 1.8 1.5 2.8 3.2 2.8 1.8 0 2.6-1 2.2-2.6"/></svg>`,
    tap: (size = 14) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="3"/><circle cx="12" cy="12" r="7.5" stroke-dasharray="3 3"/></svg>`,
    text: (size = 14) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 7h16M4 12h12M4 17h9"/><rect x="15" y="13" width="6" height="6" rx="1"/></svg>`,
    sparkle: (size = 14) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3l1.9 5.6L19.5 10.5l-5.6 1.9L12 18l-1.9-5.6L4.5 10.5l5.6-1.9L12 3z"/><path d="M19 3v3M20.5 4.5h-3"/></svg>`,
    copy: (size = 14) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>`,
    pin: (size = 14) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 17v5"/><path d="M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z"/></svg>`,
    save: (size = 14) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>`,
    moon: (size = 14) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>`,
    sun: (size = 14) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41"/></svg>`,
    external: (size = 14) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/></svg>`,
    gear: (size = 14) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09a1.65 1.65 0 0 0 1.51-1 1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9c.26.6.77 1 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>`,
    history: (size = 14) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/><path d="M12 7v5l4 2"/></svg>`,
    expand: (size = 14) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 3 21 3 21 9"/><polyline points="9 21 3 21 3 15"/><line x1="21" y1="3" x2="14" y2="10"/><line x1="3" y1="21" x2="10" y2="14"/></svg>`,
    send: (size = 14) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14M13 5l7 7-7 7"/></svg>`,
    translate: (size = 13) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 8l6 6M4 14l6-6 2-3M2 5h12M7 2h1"/><path d="M22 22l-5-10-5 10M14 18h6"/></svg>`,
    check: (size = 14) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>`,
    star: (size = 18, filled = false) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="${filled ? 'currentColor' : 'none'}" stroke="currentColor" stroke-width="1.9" stroke-linejoin="round"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/></svg>`,
    googleG: (size = 15) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24"><path fill="#EA4335" d="M12 10.2v3.9h5.4c-.2 1.2-1.5 3.6-5.4 3.6-3.2 0-5.9-2.7-5.9-6s2.7-6 5.9-6c1.9 0 3.1.8 3.8 1.5l2.6-2.5C16.8 3.2 14.6 2.3 12 2.3 6.7 2.3 2.4 6.6 2.4 11.9S6.7 21.5 12 21.5c6.9 0 9.6-4.8 9.6-7.3 0-.5-.1-.9-.1-1.3H12z"/><path fill="#4285F4" d="M21.5 12.9c0-.5-.1-.9-.1-1.3H12v3.9h5.4c-.5 1.5-1.9 3.6-5.4 3.6v2.4c6.9 0 9.5-4.8 9.5-8.6z"/><path fill="#FBBC05" d="M6.1 13.7c-.2-.6-.4-1.2-.4-1.8s.1-1.2.4-1.8V7.4H3.6C2.8 8.8 2.4 10.3 2.4 11.9s.4 3.1 1.2 4.5l2.5-2.7z"/><path fill="#34A853" d="M12 17.9c-2.6 0-4.8-1.7-5.9-4.2l-2.5 2.7c1.6 3 4.8 5.1 8.4 5.1 3.4 0 6.2-1.2 8-3.2l-2.6-2.5c-1.4 1.3-3.2 2.1-5.4 2.1z"/></svg>`
  };

  function applyGlassAppearance(settings) {
    if (!settings) return;
    const rootEl = document.documentElement;
    rootEl.setAttribute('data-theme', settings.effectiveTheme || 'dark');
    rootEl.setAttribute('data-glow', settings.glowTheme || 'apple');
    rootEl.setAttribute('data-intensity', settings.glowIntensity || 'balanced');
    rootEl.setAttribute('data-style', settings.visualStylePreset || 'crystal');
    rootEl.setAttribute('data-motion', settings.motionFeel || 'crisp');
  }

  function initHorizonLightWell(containerEl) {
    if (!containerEl) return;
    let targetX = 50;
    let currentX = 50;
    let rafId = null;

    const tick = () => {
      currentX += (targetX - currentX) * 0.14;
      containerEl.style.setProperty('--hx', `${currentX.toFixed(2)}%`);
      if (Math.abs(targetX - currentX) > 0.08) {
        rafId = requestAnimationFrame(tick);
      } else {
        rafId = null;
      }
    };

    window.addEventListener('pointermove', (e) => {
      const rect = containerEl.getBoundingClientRect();
      if (rect.width <= 0) return;
      targetX = Math.max(15, Math.min(85, ((e.clientX - rect.left) / rect.width) * 100));
      if (!rafId) rafId = requestAnimationFrame(tick);
    });
  }

  function initDialogStars(canvasEl, count = 18) {
    if (!canvasEl) return;
    const ctx = canvasEl.getContext('2d');
    const stars = Array.from({ length: count }, (_, i) => ({
      x: Math.random(),
      y: Math.random(),
      r: 0.7 + (i % 3) * 0.45,
      phase: Math.random() * Math.PI * 2,
      speed: 0.8 + Math.random() * 1.1
    }));

    const resize = () => {
      const rect = canvasEl.getBoundingClientRect();
      const dpr = window.devicePixelRatio || 1;
      canvasEl.width = Math.max(1, Math.round(rect.width * dpr));
      canvasEl.height = Math.max(1, Math.round(rect.height * dpr));
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };
    resize();
    window.addEventListener('resize', resize);

    let start = performance.now();
    const draw = (now) => {
      const t = (now - start) / 1000;
      const rect = canvasEl.getBoundingClientRect();
      ctx.clearRect(0, 0, rect.width, rect.height);
      const isLight = document.documentElement.getAttribute('data-theme') === 'light';
      const baseAlpha = isLight ? 0.18 : 0.45;
      for (const s of stars) {
        const a = (0.3 + 0.7 * (0.5 + 0.5 * Math.sin(t * s.speed + s.phase))) * baseAlpha;
        ctx.fillStyle = isLight ? `rgba(14,165,233,${a})` : `rgba(186,230,253,${a})`;
        const px = s.x * rect.width;
        const py = s.y * rect.height;
        ctx.beginPath();
        ctx.arc(px, py, s.r, 0, Math.PI * 2);
        ctx.fill();
      }
      requestAnimationFrame(draw);
    };
    requestAnimationFrame(draw);
  }

  function renderOpticalOrbHtml(small = false) {
    return `
      <div class="optical-orb ${small ? 'sm' : ''}">
        <div class="optical-orb-halo"></div>
        <div class="optical-orb-inner"></div>
        <div class="optical-orb-core">${LoopIcons.search(small ? 14 : 20)}</div>
      </div>`;
  }

  root.LoopUI = {
    Icons: LoopIcons,
    applyGlassAppearance,
    initHorizonLightWell,
    initDialogStars,
    renderOpticalOrbHtml
  };
})(window);
