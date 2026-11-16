(function (root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory();
  } else {
    root.LoopVisionHelpers = factory();
  }
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  function extractPrimaryURL(text) {
    if (!text || typeof text !== 'string') return null;
    const explicitMatch = text.match(/\bhttps?:\/\/[^\s<>"'`]+/i);
    if (explicitMatch) {
      return cleanUrlTrailing(explicitMatch[0]);
    }
    const wwwMatch = text.match(/\bwww\.[a-z0-9-]+(\.[a-z0-9-]+)+([^\s<>"'`]*)?/i);
    if (wwwMatch) {
      return 'https://' + cleanUrlTrailing(wwwMatch[0]);
    }
    const domainMatch = text.match(
      /\b([a-z0-9-]+\.)+(com|org|net|io|dev|ai|app|co|edu|gov|gg|me|tv|uk|de|jp)(\/[^\s<>"'`]*)?\b/i
    );
    if (domainMatch) {
      return 'https://' + cleanUrlTrailing(domainMatch[0]);
    }
    return null;
  }

  function cleanUrlTrailing(raw) {
    return raw.replace(/[.,;:!?)'"\]]+$/, '');
  }

  function displayHostForUrl(url) {
    try {
      const u = new URL(url);
      return u.hostname.replace(/^www\./, '');
    } catch {
      return url;
    }
  }

  /**
   * Safe recursive-descent arithmetic parser for OCR expressions (no eval).
   */
  function evaluateMathExpression(text) {
    if (!text || typeof text !== 'string') return null;
    const firstLine = text.split(/\r?\n/)[0] || '';
    let expr = firstLine
      .replace(/×/g, '*')
      .replace(/÷/g, '/')
      .replace(/[−–—]/g, '-')
      .replace(/=\s*\??\s*$/, '')
      .replace(/,/g, '')
      .trim();

    if (!expr || expr.length > 64) return null;
    if (!/[+\-*/^%]/.test(expr)) return null;
    if (!/^[0-9+\-*/().%\s^]+$/.test(expr)) return null;
    // Avoid date/version/ratio strings like 2026-11-15 or 1.2.3
    if (/^\d{4}-\d{1,2}-\d{1,2}$/.test(expr)) return null;
    if (/\.\d*\./.test(expr)) return null;

    const tokens = tokenizeMath(expr);
    if (!tokens || tokens.length < 3) return null;

    let pos = 0;
    function peek() { return tokens[pos]; }
    function consume() { return tokens[pos++]; }

    function parseExpr() {
      let left = parseTerm();
      while (peek() === '+' || peek() === '-') {
        const op = consume();
        const right = parseTerm();
        left = op === '+' ? left + right : left - right;
      }
      return left;
    }

    function parseTerm() {
      let left = parsePower();
      while (peek() === '*' || peek() === '/' || peek() === '%') {
        const op = consume();
        const right = parsePower();
        if (op === '*') left *= right;
        else if (op === '/') {
          if (right === 0) throw new Error('div0');
          left /= right;
        } else {
          if (right === 0) throw new Error('mod0');
          left %= right;
        }
      }
      return left;
    }

    function parsePower() {
      let base = parseUnary();
      if (peek() === '^') {
        consume();
        const exp = parsePower();
        base = Math.pow(base, exp);
      }
      return base;
    }

    function parseUnary() {
      if (peek() === '-') {
        consume();
        return -parseUnary();
      }
      if (peek() === '+') {
        consume();
        return parseUnary();
      }
      return parsePrimary();
    }

    function parsePrimary() {
      const tok = consume();
      if (tok === '(') {
        const val = parseExpr();
        if (consume() !== ')') throw new Error('paren');
        return val;
      }
      if (typeof tok === 'number' && Number.isFinite(tok)) return tok;
      throw new Error('unexpected');
    }

    try {
      const value = parseExpr();
      if (pos !== tokens.length) return null;
      if (!Number.isFinite(value)) return null;
      const rounded = Math.abs(value - Math.round(value)) < 1e-9
        ? String(Math.round(value))
        : Number(value.toFixed(6)).toString();
      return { expression: expr, value, formatted: rounded };
    } catch {
      return null;
    }
  }

  function tokenizeMath(expr) {
    const tokens = [];
    let i = 0;
    while (i < expr.length) {
      const ch = expr[i];
      if (/\s/.test(ch)) {
        i++;
        continue;
      }
      if (/[0-9.]/.test(ch)) {
        let start = i;
        while (i < expr.length && /[0-9.]/.test(expr[i])) i++;
        const num = Number(expr.slice(start, i));
        if (!Number.isFinite(num)) return null;
        tokens.push(num);
        continue;
      }
      if ('+-*/^%()'.includes(ch)) {
        tokens.push(ch);
        i++;
        continue;
      }
      return null;
    }
    return tokens;
  }

  function rgbToHex(r, g, b) {
    const clamp = (n) => Math.max(0, Math.min(255, Math.round(n)));
    return (
      '#' +
      [clamp(r), clamp(g), clamp(b)]
        .map((v) => v.toString(16).toUpperCase().padStart(2, '0'))
        .join('')
    );
  }

  /**
   * Samples dominant vivid or representative color from RGBA pixel buffer.
   */
  function extractDominantColor(rgba, width, height) {
    if (!rgba || !rgba.length || width <= 0 || height <= 0) return null;
    const totalPixels = Math.floor(rgba.length / 4);
    const step = Math.max(1, Math.floor(totalPixels / 1800));
    const vividBuckets = new Map();
    const allBuckets = new Map();

    let sampledCount = 0;
    for (let p = 0; p < totalPixels; p += step) {
      const idx = p * 4;
      const a = rgba[idx + 3];
      if (a < 128) continue;
      sampledCount++;
      const r = rgba[idx];
      const g = rgba[idx + 1];
      const b = rgba[idx + 2];

      const max = Math.max(r, g, b);
      const min = Math.min(r, g, b);
      const sat = max === 0 ? 0 : (max - min) / max;
      const lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;

      const qR = r >> 4;
      const qG = g >> 4;
      const qB = b >> 4;
      const key = (qR << 8) | (qG << 4) | qB;

      const allEntry = allBuckets.get(key) || { count: 0, r: 0, g: 0, b: 0, satSum: 0 };
      allEntry.count++;
      allEntry.r += r;
      allEntry.g += g;
      allEntry.b += b;
      allEntry.satSum += sat;
      allBuckets.set(key, allEntry);

      if (sat > 0.22 && lum > 0.12 && lum < 0.90) {
        const vEntry = vividBuckets.get(key) || { count: 0, r: 0, g: 0, b: 0, satSum: 0 };
        vEntry.count++;
        vEntry.r += r;
        vEntry.g += g;
        vEntry.b += b;
        vEntry.satSum += sat;
        vividBuckets.set(key, vEntry);
      }
    }

    if (sampledCount === 0 || allBuckets.size === 0) return null;

    let best = null;
    for (const entry of allBuckets.values()) {
      if (!best || entry.count > best.count) best = entry;
    }
    const topRatio = best.count / sampledCount;
    const topAvgSat = best.satSum / best.count;
    // Only show a color chip when one single color genuinely dominates (swatch/logo), never on text or busy photos
    const isDominant = (topRatio >= 0.52 && topAvgSat > 0.24) || topRatio >= 0.72;
    if (!isDominant) return null;

    const r = Math.round(best.r / best.count);
    const g = Math.round(best.g / best.count);
    const b = Math.round(best.b / best.count);
    return {
      r,
      g,
      b,
      hex: rgbToHex(r, g, b)
    };
  }

  function formatOcrPreview(rawText, lines = null) {
    const lineArr = Array.isArray(lines) && lines.length > 0
      ? lines.map((l) => (typeof l === 'string' ? l : l && l.text ? l.text : '').trim()).filter(Boolean)
      : String(rawText || '').split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
    if (lineArr.length >= 6) {
      const totalWords = lineArr.reduce((acc, s) => acc + s.split(/\s+/).filter(Boolean).length, 0);
      const avgWords = totalWords / lineArr.length;
      const sentences = lineArr.filter((s) => /[.?!]$/.test(s)).length;
      if (avgWords <= 3.2 && sentences < 2) {
        return `Sidebar / menu (${lineArr.length} items)`;
      }
    }
    return lineArr.join('  ').replace(/\s+/g, ' ').trim();
  }

  /**
   * Matches macOS VisionAnalyzer low-information blank surface threshold:
   * edgeEnergy < 0.026 && luminanceStdDev < 0.042
   */
  function analyzeRegionDetail(rgba, width, height) {
    if (!rgba || width < 4 || height < 4) {
      return { luminanceStdDev: 0, edgeEnergy: 0, isLowInfo: true };
    }
    const strideX = Math.max(1, Math.floor(width / 48));
    const strideY = Math.max(1, Math.floor(height / 48));
    const samples = [];

    for (let y = 0; y < height; y += strideY) {
      const row = [];
      for (let x = 0; x < width; x += strideX) {
        const idx = (y * width + x) * 4;
        const lum = (0.2126 * rgba[idx] + 0.7152 * rgba[idx + 1] + 0.0722 * rgba[idx + 2]) / 255;
        row.push(lum);
      }
      samples.push(row);
    }

    let sum = 0;
    let count = 0;
    for (const row of samples) {
      for (const v of row) {
        sum += v;
        count++;
      }
    }
    if (count === 0) return { luminanceStdDev: 0, edgeEnergy: 0, isLowInfo: true };
    const mean = sum / count;

    let varSum = 0;
    let edgeSum = 0;
    let edgeCount = 0;
    for (let y = 0; y < samples.length; y++) {
      for (let x = 0; x < samples[y].length; x++) {
        const v = samples[y][x];
        varSum += (v - mean) * (v - mean);
        if (x + 1 < samples[y].length) {
          edgeSum += Math.abs(v - samples[y][x + 1]);
          edgeCount++;
        }
        if (y + 1 < samples.length) {
          edgeSum += Math.abs(v - samples[y + 1][x]);
          edgeCount++;
        }
      }
    }

    const luminanceStdDev = Math.sqrt(varSum / count);
    const edgeEnergy = edgeCount > 0 ? edgeSum / edgeCount : 0;
    return {
      luminanceStdDev,
      edgeEnergy,
      isLowInfo: edgeEnergy < 0.026 && luminanceStdDev < 0.042
    };
  }

  function shouldApplyWebDarkCss(urlString) {
    if (!urlString || typeof urlString !== 'string') return false;
    const lower = urlString.toLowerCase();
    if (lower === 'about:blank' || lower.startsWith('data:') || lower.startsWith('file:')) {
      return false;
    }
    if (
      lower.includes('/sorry') ||
      lower.includes('recaptcha') ||
      lower.includes('accounts.google.') ||
      lower.includes('consent.google.') ||
      lower.includes('challenge')
    ) {
      return false;
    }
    return true;
  }

  function buildSearchUrl(engine, query) {
    const q = encodeURIComponent((query || '').trim());
    switch (engine) {
      case 'perplexity':
        return `https://www.perplexity.ai/search?q=${q}`;
      case 'bing':
        return `https://www.bing.com/search?q=${q}`;
      case 'aiExplain':
        return `https://www.google.com/search?udm=50&q=${encodeURIComponent(
          'Explain this clearly and concisely: ' + (query || '').trim()
        )}`;
      case 'googleLens':
      case 'google':
      default:
        return `https://www.google.com/search?q=${q}`;
    }
  }

  return {
    extractPrimaryURL,
    displayHostForUrl,
    evaluateMathExpression,
    rgbToHex,
    extractDominantColor,
    formatOcrPreview,
    analyzeRegionDetail,
    shouldApplyWebDarkCss,
    buildSearchUrl
  };
});
