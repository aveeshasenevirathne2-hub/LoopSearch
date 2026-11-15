(function () {
  'use strict';

  const Icons = {
    brandMark(size = 20) {
      return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none">
        <defs>
          <linearGradient id="ls-g" x1="3" y1="3" x2="21" y2="21" gradientUnits="userSpaceOnUse">
            <stop offset="0%" stop-color="#38bdf8"/>
            <stop offset="50%" stop-color="#60a5fa"/>
            <stop offset="100%" stop-color="#2563eb"/>
          </linearGradient>
        </defs>
        <path d="M11 3.5a7.5 7.5 0 1 0 5.3 12.8l3.6 3.6" stroke="url(#ls-g)" stroke-width="2.4" stroke-linecap="round"/>
        <circle cx="11" cy="11" r="3.1" fill="#e0f2fe" fill-opacity="0.9"/>
      </svg>`;
    },
    close(size = 13) {
      return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M18 6 6 18M6 6l12 12"/></svg>`;
    },
    sparkle(size = 14) {
      return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2l2.1 6.3L20.4 10l-6.3 2.1L12 18.4l-2.1-6.3L3.6 10l6.3-2.1L12 2zm7 12 1.1 3.1L23 18l-2.9.9L19 22l-1.1-3.1L15 18l2.9-.9L19 14z"/></svg>`;
    },
    box(size = 14) {
      return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2"/></svg>`;
    },
    lasso(size = 14) {
      return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M7 18c-3-1.4-4.5-4-4-6.8C3.7 7 8 4.5 13 5c4.7.5 8 3.6 7.5 7.4-.5 3.6-4.2 6.1-8.5 5.8-2.2-.2-3.8-1-4.8-2"/><circle cx="7" cy="18" r="2.2"/></svg>`;
    },
    tap(size = 14) {
      return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="2.5" fill="currentColor"/><circle cx="12" cy="12" r="6.2" stroke-opacity="0.75"/><circle cx="12" cy="12" r="9.5" stroke-dasharray="3 3" stroke-opacity="0.5"/></svg>`;
    },
    text(size = 14) {
      return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 6h16M12 6v13M8 19h8"/></svg>`;
    },
    history(size = 14) {
      return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5M12 7v5l3 2"/></svg>`;
    },
    gear(size = 14) {
      return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9c.26.6.85 1 1.51 1H21a2 2 0 0 1 0 4h-.09c-.66 0-1.25.4-1.51 1z"/></svg>`;
    },
    back(size = 14) {
      return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>`;
    },
    moon(size = 14) {
      return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M21 12.8A9 9 0 1 1 11.2 3 7 7 0 0 0 21 12.8z"/></svg>`;
    },
    sun(size = 14) {
      return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>`;
    },
    pin(size = 14) {
      return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m12 17v5M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z"/></svg>`;
    },
    external(size = 14) {
      return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 3h6v6M10 14 21 3M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/></svg>`;
    },
    expand(size = 14) {
      return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 3 6 0 0 6M9 21 3 21 3 15M21 3l-7 7M3 21l7-7"/></svg>`;
    },
    send(size = 14) {
      return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14M13 5l7 7-7 7"/></svg>`;
    },
    search(size = 13) {
      return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>`;
    },
    copy(size = 13) {
      return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>`;
    },
    translate(size = 13) {
      return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m5 8 6 6M4 14l6-6 2-3M2 5h12M7 2h1M22 22l-5-10-5 10M14 18h6"/></svg>`;
    },
    save(size = 13) {
      return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z"/><polyline points="17 21 17 13 7 13 7 21"/><polyline points="7 3 7 8 15 8"/></svg>`;
    },
    check(size = 14) {
      return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>`;
    },
    googleG(size = 15) {
      return `<svg width="${size}" height="${size}" viewBox="0 0 24 24"><path fill="#4285F4" d="M23.5 12.3c0-.8-.1-1.6-.2-2.3H12v4.5h6.5a5.5 5.5 0 0 1-2.4 3.6v3h3.9c2.3-2.1 3.5-5.2 3.5-8.8z"/><path fill="#34A853" d="M12 24c3.2 0 6-1.1 8-2.9l-3.9-3a7.2 7.2 0 0 1-10.7-3.8H1.4v3.1A12 12 0 0 0 12 24z"/><path fill="#FBBC05" d="M5.4 14.3a7.2 7.2 0 0 1 0-4.6V6.6H1.4a12 12 0 0 0 0 10.8l4-3.1z"/><path fill="#EA4335" d="M12 4.8c1.8 0 3.3.6 4.6 1.8l3.4-3.4C18 1.2 15.2 0 12 0A12 12 0 0 0 1.4 6.6l4 3.1A7.2 7.2 0 0 1 12 4.8z"/></svg>`;
    },
    star(size = 24, filled = true) {
      return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="${filled ? 'currentColor' : 'none'}" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/></svg>`;
    }
  };

  function applyGlassAppearance(settings) {
    if (!settings) return;
    const root = document.documentElement;
    root.dataset.theme = settings.effectiveTheme || (settings.theme === 'light' ? 'light' : 'dark');
    root.dataset.glow = settings.glowTheme || 'apple';
    root.dataset.intensity = settings.glowIntensity || 'balanced';
    root.dataset.style = settings.visualStylePreset || 'crystal';
    root.dataset.motion = settings.motionFeel || 'crisp';
  }

  function initHorizonLightWell(shellEl) {
    if (!shellEl) return;
    shellEl.addEventListener('pointermove', (e) => {
      const rect = shellEl.getBoundingClientRect();
      if (!rect.width) return;
      const pct = Math.max(12, Math.min(88, ((e.clientX - rect.left) / rect.width) * 100));
      shellEl.style.setProperty('--horizon-x', `${pct.toFixed(1)}%`);
    });
    shellEl.addEventListener('pointerleave', () => {
      shellEl.style.removeProperty('--horizon-x');
    });
  }

  function initSpecularInteractive(rootEl = document) {
    if (!rootEl || rootEl.__loopSpecularBound) return;
    rootEl.__loopSpecularBound = true;
    rootEl.addEventListener('pointermove', (e) => {
      const target = e.target.closest('.glass-card, .btn-primary, .btn-glass, .chip-btn, .smart-chip, .mode-pill, .google-btn');
      if (!target) return;
      const r = target.getBoundingClientRect();
      if (!r.width || !r.height) return;
      target.style.setProperty('--mx', `${(e.clientX - r.left).toFixed(1)}px`);
      target.style.setProperty('--my', `${(e.clientY - r.top).toFixed(1)}px`);
    });
  }

  function staggerReveal(selectorOrEls, baseDelayMs = 35, stepDelayMs = 44) {
    const els =
      typeof selectorOrEls === 'string'
        ? Array.from(document.querySelectorAll(selectorOrEls))
        : Array.from(selectorOrEls || []);
    els.forEach((el, idx) => {
      if (!el || !el.style) return;
      el.classList.remove('stagger-animate');
      void el.offsetWidth;
      el.style.setProperty('--stagger-delay', `${baseDelayMs + idx * stepDelayMs}ms`);
      el.classList.add('stagger-animate');
    });
  }

  function initSegmentedThumb(segmentedEl) {
    if (!segmentedEl) return null;
    let thumb = segmentedEl.querySelector('.segmented-thumb');
    if (!thumb) {
      thumb = document.createElement('div');
      thumb.className = 'segmented-thumb';
      segmentedEl.prepend(thumb);
    }
    const sync = () => {
      const active = segmentedEl.querySelector('button.active') || segmentedEl.querySelector('button');
      if (!active) return;
      const left = active.offsetLeft;
      thumb.style.width = `${active.offsetWidth}px`;
      thumb.style.transform = `translateX(${Math.max(0, left - 4)}px)`;
    };
    requestAnimationFrame(sync);
    window.addEventListener('resize', sync);
    return sync;
  }

  function initDialogStars(canvasEl, count = 20) {
    if (!canvasEl) return;
    const ctx = canvasEl.getContext('2d');
    const stars = Array.from({ length: count }, () => ({
      x: Math.random(),
      y: Math.random(),
      r: 2.0 + Math.random() * 2.8,
      phase: Math.random() * Math.PI * 2,
      speed: 1.1 + Math.random() * 1.4,
      vy: 0.008 + Math.random() * 0.014
    }));

    function resize() {
      const rect = canvasEl.getBoundingClientRect();
      const dpr = window.devicePixelRatio || 1;
      canvasEl.width = Math.max(1, Math.round(rect.width * dpr));
      canvasEl.height = Math.max(1, Math.round(rect.height * dpr));
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }
    resize();
    window.addEventListener('resize', resize);

    const start = performance.now();
    function tick(now) {
      const t = (now - start) / 1000;
      const rect = canvasEl.getBoundingClientRect();
      const w = rect.width;
      const h = rect.height;
      ctx.clearRect(0, 0, w, h);

      const isDark = (document.documentElement.dataset.theme || 'dark') === 'dark';
      for (const s of stars) {
        const sx = s.x * w;
        const sy = (((s.y - t * s.vy) % 1) + 1) % 1 * h;
        const a = (0.18 + 0.82 * (0.5 + 0.5 * Math.sin(t * s.speed + s.phase))) * (isDark ? 0.56 : 0.28);
        const r = s.r;
        ctx.save();
        ctx.globalAlpha = a;
        ctx.fillStyle = isDark ? '#bae6fd' : '#0284c7';
        ctx.shadowColor = isDark ? '#38bdf8' : 'transparent';
        ctx.shadowBlur = isDark ? 6 : 0;
        ctx.beginPath();
        ctx.moveTo(sx, sy - r);
        ctx.quadraticCurveTo(sx, sy, sx + r, sy);
        ctx.quadraticCurveTo(sx, sy, sx, sy + r);
        ctx.quadraticCurveTo(sx, sy, sx - r, sy);
        ctx.quadraticCurveTo(sx, sy, sx, sy - r);
        ctx.fill();
        ctx.restore();
      }
      requestAnimationFrame(tick);
    }
    requestAnimationFrame(tick);
  }

  function renderOpticalOrbHtml(compact = false) {
    return `<div class="optical-orb${compact ? ' compact' : ''}">
      <div class="orb-halo"></div>
      <div class="orb-ripple"></div>
      <div class="orb-ripple r2"></div>
      <div class="orb-ripple r3"></div>
      <div class="orb-ring-outer"></div>
      <div class="orb-ring-inner"></div>
      <div class="orb-core"></div>
      <div class="orb-spark"></div>
      <div class="orb-spark s2"></div>
    </div>`;
  }

  document.addEventListener('DOMContentLoaded', () => {
    initSpecularInteractive(document);
  });

  window.LoopUI = {
    Icons,
    applyGlassAppearance,
    initHorizonLightWell,
    initSpecularInteractive,
    staggerReveal,
    initSegmentedThumb,
    initDialogStars,
    renderOpticalOrbHtml
  };
})();
