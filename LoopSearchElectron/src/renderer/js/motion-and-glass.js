(function () {
  'use strict';

  let brandUid = 0;

  const Icons = {
    brandMark(size = 20) {
      const uid = `ls${++brandUid}`;
      return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" style="display:block;flex-shrink:0;">
        <defs>
          <linearGradient id="${uid}-dome" x1="12" y1="1" x2="12" y2="12.5" gradientUnits="userSpaceOnUse">
            <stop offset="0%" stop-color="#8f96a6" stop-opacity="0.68"/>
            <stop offset="42%" stop-color="#424757" stop-opacity="0.32"/>
            <stop offset="100%" stop-color="#030408" stop-opacity="0"/>
          </linearGradient>
          <linearGradient id="${uid}-horizon" x1="12" y1="23" x2="12" y2="10.2" gradientUnits="userSpaceOnUse">
            <stop offset="0%" stop-color="#f0fcff" stop-opacity="0.98"/>
            <stop offset="18%" stop-color="#24c7ff" stop-opacity="0.92"/>
            <stop offset="42%" stop-color="#0580fa" stop-opacity="0.72"/>
            <stop offset="70%" stop-color="#293894" stop-opacity="0.44"/>
            <stop offset="100%" stop-color="#030408" stop-opacity="0"/>
          </linearGradient>
          <radialGradient id="${uid}-core" cx="50%" cy="100%" r="58%">
            <stop offset="0%" stop-color="#faffff" stop-opacity="0.96"/>
            <stop offset="48%" stop-color="#2ed1ff" stop-opacity="0.68"/>
            <stop offset="100%" stop-color="#030408" stop-opacity="0"/>
          </radialGradient>
          <linearGradient id="${uid}-loop" x1="12" y1="6" x2="12" y2="18" gradientUnits="userSpaceOnUse">
            <stop offset="0%" stop-color="#c7dcf5" stop-opacity="0.92"/>
            <stop offset="48%" stop-color="#5cdbff" stop-opacity="0.96"/>
            <stop offset="100%" stop-color="#f5fcff" stop-opacity="0.98"/>
          </linearGradient>
          <linearGradient id="${uid}-rim" x1="12" y1="1" x2="12" y2="23" gradientUnits="userSpaceOnUse">
            <stop offset="0%" stop-color="#e0e8f5" stop-opacity="0.78"/>
            <stop offset="48%" stop-color="#4261ad" stop-opacity="0.30"/>
            <stop offset="82%" stop-color="#29c7ff" stop-opacity="0.88"/>
            <stop offset="100%" stop-color="#f2feff" stop-opacity="1"/>
          </linearGradient>
          <clipPath id="${uid}-clip">
            <rect x="1" y="1" width="22" height="22" rx="6"/>
          </clipPath>
        </defs>
        <g clip-path="url(#${uid}-clip)">
          <rect x="1" y="1" width="22" height="22" fill="#030408"/>
          <rect x="1" y="1" width="22" height="22" fill="url(#${uid}-dome)"/>
          <rect x="1" y="1" width="22" height="22" fill="url(#${uid}-horizon)"/>
          <ellipse cx="12" cy="23" rx="14" ry="9" fill="url(#${uid}-core)"/>
          <path d="M 8.9 15.56 C 6.93 13.59, 6.65 11.62, 7.21 9.93 C 8.2 7.26, 10.87 6.13, 13.41 6.69 C 16.22 7.4, 17.49 9.79, 16.79 12.47 C 15.94 14.72, 13.55 15.56, 11.3 15 C 9.47 14.44, 12.84 10.92, 15.1 8.81"
                stroke="#38bdf8" stroke-opacity="0.36" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/>
          <path d="M 8.9 15.56 C 6.93 13.59, 6.65 11.62, 7.21 9.93 C 8.2 7.26, 10.87 6.13, 13.41 6.69 C 16.22 7.4, 17.49 9.79, 16.79 12.47 C 15.94 14.72, 13.55 15.56, 11.3 15 C 9.47 14.44, 12.84 10.92, 15.1 8.81"
                stroke="url(#${uid}-loop)" stroke-width="1.95" stroke-linecap="round" stroke-linejoin="round"/>
          <circle cx="15.1" cy="8.81" r="1.85" fill="#59e0ff" fill-opacity="0.55"/>
          <circle cx="15.1" cy="8.81" r="1.05" fill="#ffffff"/>
        </g>
        <rect x="1.35" y="1.35" width="21.3" height="21.3" rx="5.7" stroke="url(#${uid}-rim)" stroke-width="0.95"/>
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
      el.style.setProperty('--stagger-tilt', `${idx % 2 === 0 ? -1.4 : 1.4}deg`);
      el.classList.add('stagger-animate');
    });
  }

  function springPop(el) {
    if (!el || !el.classList) return;
    el.classList.remove('spring-pop');
    void el.offsetWidth;
    el.classList.add('spring-pop');
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
      <svg class="orb-dial-arc" viewBox="0 0 100 100" fill="none">
        <circle cx="50" cy="50" r="44" stroke="rgba(125,211,252,0.22)" stroke-width="1" stroke-dasharray="3 5"/>
        <path d="M50 6 A44 44 0 0 1 94 50" stroke="rgba(186,230,253,0.65)" stroke-width="1.6" stroke-linecap="round"/>
      </svg>
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
    springPop,
    initSegmentedThumb,
    initDialogStars,
    renderOpticalOrbHtml
  };
})();
