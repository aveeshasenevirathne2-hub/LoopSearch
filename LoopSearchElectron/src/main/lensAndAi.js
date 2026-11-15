'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { execFile } = require('child_process');
const { promisify } = require('util');

const execFileAsync = promisify(execFile);

const MOBILE_SAFARI_UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';

const GITHUB_URLS = {
  repo: 'https://github.com/aveeshasenevirathne2-hub/LoopSearch',
  issuesNew: 'https://github.com/aveeshasenevirathne2-hub/LoopSearch/issues/new',
  releasesLatestApi: 'https://api.github.com/repos/aveeshasenevirathne2-hub/LoopSearch/releases/latest',
  xProfile: 'https://x.com/AveeshaSen',
  geminiKeyPortal: 'https://aistudio.google.com/apikey'
};

function buildMultipartLensBody(jpegBuffer) {
  const boundary = '----LoopSearchLensBoundary' + crypto.randomBytes(10).toString('hex');
  const head = Buffer.from(
    `--${boundary}\r\nContent-Disposition: form-data; name="encoded_image"; filename="search.jpg"\r\nContent-Type: image/jpeg\r\n\r\n`,
    'utf8'
  );
  const tail = Buffer.from(`\r\n--${boundary}--\r\n`, 'utf8');
  return {
    boundary,
    body: Buffer.concat([head, jpegBuffer, tail])
  };
}

/**
 * Uploads JPEG image to Google Lens using Chromium's Electron net stack + persistent cookie jar
 * whenever available so TLS/HTTP2 & cookies match the embedded <webview>.
 */
async function uploadToGoogleLens(jpegBuffer, lensSession = null) {
  const { boundary, body } = buildMultipartLensBody(jpegBuffer);

  if (lensSession) {
    try {
      const { net } = require('electron');
      const result = await new Promise((resolve, reject) => {
        const req = net.request({
          method: 'POST',
          url: 'https://lens.google.com/v3/upload',
          session: lensSession,
          useSessionCookies: true,
          redirect: 'manual'
        });
        req.setHeader('User-Agent', MOBILE_SAFARI_UA);
        req.setHeader('Origin', 'https://lens.google.com');
        req.setHeader('Referer', 'https://lens.google.com/');
        req.setHeader('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
        req.setHeader('Accept-Language', 'en-US,en;q=0.9');
        req.setHeader('Content-Type', `multipart/form-data; boundary=${boundary}`);

        let settled = false;
        const done = (val, isErr = false) => {
          if (settled) return;
          settled = true;
          clearTimeout(timer);
          if (isErr) reject(val);
          else resolve(val);
        };

        const timer = setTimeout(() => {
          try { req.abort(); } catch {}
          done(new Error('Google Lens upload timed out'), true);
        }, 18000);

        req.on('redirect', (statusCode, _method, redirectUrl) => {
          const finalUrl = redirectUrl.startsWith('http')
            ? redirectUrl
            : `https://lens.google.com${redirectUrl}`;
          try { req.abort(); } catch {}
          done({ ok: true, status: statusCode, url: finalUrl });
        });

        req.on('response', (response) => {
          const chunks = [];
          const loc = response.headers.location;
          const locHeader = Array.isArray(loc) ? loc[0] : loc;
          if (response.statusCode >= 300 && response.statusCode < 400 && locHeader) {
            const finalUrl = locHeader.startsWith('http')
              ? locHeader
              : `https://lens.google.com${locHeader}`;
            done({ ok: true, status: response.statusCode, url: finalUrl });
            return;
          }
          response.on('data', (c) => chunks.push(c));
          response.on('end', () => {
            const html = Buffer.concat(chunks).toString('utf8');
            const extracted = extractLensResultUrlFromHtml(html);
            if (extracted) {
              done({ ok: true, status: response.statusCode, url: extracted });
            } else {
              done({
                ok: false,
                status: response.statusCode,
                url: 'https://lens.google.com/',
                diagnostic: `Unexpected Lens response status ${response.statusCode}`
              });
            }
          });
        });

        req.on('error', (err) => done(err, true));
        req.write(body);
        req.end();
      });

      return result;
    } catch (err) {
      return {
        ok: false,
        status: 0,
        url: 'https://lens.google.com/',
        diagnostic: err.message
      };
    }
  }

  // Standard fetch fallback (for Node tests or non-Electron context)
  const resp = await fetch('https://lens.google.com/v3/upload', {
    method: 'POST',
    redirect: 'manual',
    headers: {
      'User-Agent': MOBILE_SAFARI_UA,
      Origin: 'https://lens.google.com',
      Referer: 'https://lens.google.com/',
      'Content-Type': `multipart/form-data; boundary=${boundary}`
    },
    body
  });
  const location = resp.headers.get('location');
  if (location) {
    return {
      ok: true,
      status: resp.status,
      url: location.startsWith('http') ? location : `https://lens.google.com${location}`
    };
  }
  const html = await resp.text();
  const extracted = extractLensResultUrlFromHtml(html);
  return {
    ok: Boolean(extracted),
    status: resp.status,
    url: extracted || 'https://lens.google.com/',
    diagnostic: extracted ? undefined : `Lens HTTP ${resp.status}`
  };
}

function extractLensResultUrlFromHtml(html) {
  if (!html) return null;
  const metaRefresh = html.match(/url=(https:\/\/(?:lens|www)\.google\.com[^"'\s>]+)/i);
  if (metaRefresh) return metaRefresh[1];
  const direct = html.match(/https:\/\/(?:lens|www)\.google\.com\/search\?[^"'\s<]+/);
  return direct ? direct[0].replace(/&amp;/g, '&') : null;
}

/**
 * Injects obsidian dark theme CSS into non-CAPTCHA webview pages with live MutationObserver.
 */
function buildLensDarkThemeInjectionScript(enableDark) {
  const darkCss = `
    :root { color-scheme: dark !important; }
    html, body {
      background: #0b0e18 !important;
      color: #e8ecf6 !important;
    }
    header, nav, footer, [role="navigation"], [role="main"], [role="region"], [role="dialog"],
    .g, .MjjYud, .ULSxyf, .kp-blk, .osrp-blk, .G19kLd, .c2xzTb, .xpdopen, .TbwUpd {
      background-color: transparent !important;
      color: #e8ecf6 !important;
      border-color: rgba(255,255,255,0.10) !important;
    }
    input, textarea, [role="search"], .RNNXgb {
      background: #14192a !important;
      color: #f8fafc !important;
      border-color: rgba(148,163,184,0.28) !important;
    }
    a, a:link { color: #70b7ff !important; }
    a:visited { color: #a78bfa !important; }
    span, p, div, h1, h2, h3, h4, li { color: inherit; }
    img, picture, video, canvas, svg { filter: none !important; }
    ::-webkit-scrollbar { width: 6px; height: 6px; }
    ::-webkit-scrollbar-thumb { background: rgba(148,163,184,0.35); border-radius: 3px; }
  `.replace(/\s+/g, ' ');

  if (!enableDark) {
    return `(function(){
      var el = document.getElementById('__loopsearch_dark_css');
      if (el) el.remove();
      if (window.__loopsearchDarkObs) { window.__loopsearchDarkObs.disconnect(); window.__loopsearchDarkObs = null; }
    })();`;
  }

  return `(function(){
    var u = location.href.toLowerCase();
    if (u.includes('/sorry') || u.includes('recaptcha') || u.includes('accounts.google.') || u.includes('consent.google.')) {
      var prev = document.getElementById('__loopsearch_dark_css');
      if (prev) prev.remove();
      return;
    }
    function ensureStyle(){
      if (!document.head && !document.documentElement) return;
      var style = document.getElementById('__loopsearch_dark_css');
      if (!style) {
        style = document.createElement('style');
        style.id = '__loopsearch_dark_css';
        style.textContent = ${JSON.stringify(darkCss)};
        (document.head || document.documentElement).appendChild(style);
      }
    }
    ensureStyle();
    if (!window.__loopsearchDarkObs && document.documentElement) {
      window.__loopsearchDarkObs = new MutationObserver(ensureStyle);
      window.__loopsearchDarkObs.observe(document.documentElement, { childList: true });
    }
  })();`;
}

/**
 * Offline Windows 10/11 OCR powered by Windows.Media.Ocr (no network, no heavy binary).
 * Returns normalized [0..1] top-left bounding boxes matching VisionAnalyzer.swift.
 */
async function runWindowsOcr(pngBuffer) {
  if (process.platform !== 'win32' || !pngBuffer || pngBuffer.length === 0) {
    return { text: '', lines: [], engine: 'unavailable' };
  }

  const tmpPng = path.join(os.tmpdir(), `loopsearch-ocr-${crypto.randomUUID()}.png`);
  try {
    fs.writeFileSync(tmpPng, pngBuffer);
    const escapedPath = tmpPng.replace(/'/g, "''");
    const psScript = `
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType=WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType=WindowsRuntime]
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation\`1' })[0]
function Await($WinRtTask, $ResultType) {
  $netTask = $asTaskGeneric.MakeGenericMethod($ResultType).Invoke($null, @($WinRtTask))
  $netTask.Wait(-1) | Out-Null
  $netTask.Result
}
$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync('${escapedPath}')) ([Windows.Storage.StorageFile])
$stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
$bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
if ($null -eq $engine) { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new('en-US')) }
$result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
$w = [double]$bitmap.PixelWidth
$h = [double]$bitmap.PixelHeight
$linesOut = @()
foreach ($line in $result.Lines) {
  $wordsOut = @()
  $minX = 1.0; $minY = 1.0; $maxX = 0.0; $maxY = 0.0
  foreach ($word in $line.Words) {
    $r = $word.BoundingRect
    $nx = $r.X / $w; $ny = $r.Y / $h; $nw = $r.Width / $w; $nh = $r.Height / $h
    if ($nx -lt $minX) { $minX = $nx }
    if ($ny -lt $minY) { $minY = $ny }
    if (($nx + $nw) -gt $maxX) { $maxX = $nx + $nw }
    if (($ny + $nh) -gt $maxY) { $maxY = $ny + $nh }
    $wordsOut += [PSCustomObject]@{ text = $word.Text; x = $nx; y = $ny; w = $nw; h = $nh }
  }
  if ($wordsOut.Count -gt 0) {
    $linesOut += [PSCustomObject]@{
      text = $line.Text; x = $minX; y = $minY; w = ($maxX - $minX); h = ($maxY - $minY); words = $wordsOut
    }
  }
}
$stream.Dispose()
[PSCustomObject]@{ text = $result.Text; lines = $linesOut } | ConvertTo-Json -Depth 5 -Compress
`.trim();

    const encoded = Buffer.from(psScript, 'utf16le').toString('base64');
    const { stdout } = await execFileAsync(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', encoded],
      { timeout: 9000, windowsHide: true }
    );
    const parsed = JSON.parse((stdout || '{}').trim() || '{}');
    const lines = Array.isArray(parsed.lines) ? parsed.lines : [];
    return {
      text: parsed.text || lines.map((l) => l.text).join('\n'),
      lines,
      engine: 'winrt'
    };
  } catch (err) {
    return { text: '', lines: [], engine: 'winrt-error', error: err.message };
  } finally {
    try {
      if (fs.existsSync(tmpPng)) fs.unlinkSync(tmpPng);
    } catch {}
  }
}

async function callGeminiVision({ apiKey, imageBase64, mimeType = 'image/jpeg', prompt }) {
  if (!apiKey || !apiKey.trim()) {
    throw new Error('No Gemini API key configured. Add your key in LoopSearch Studio -> AI & Account.');
  }
  const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${encodeURIComponent(
    apiKey.trim()
  )}`;
  const parts = [
    {
      text:
        prompt && prompt.trim()
          ? prompt.trim()
          : 'Identify and explain what is shown in this screen region clearly and concisely.'
    }
  ];
  if (imageBase64) {
    parts.push({
      inline_data: {
        mime_type: mimeType,
        data: imageBase64
      }
    });
  }

  const resp = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [{ parts }],
      generationConfig: {
        temperature: 0.4,
        maxOutputTokens: 1024
      }
    })
  });
  const data = await resp.json();
  if (!resp.ok) {
    throw new Error(data?.error?.message || `Gemini API returned HTTP ${resp.status}`);
  }
  const text =
    data?.candidates?.[0]?.content?.parts
      ?.map((p) => p.text)
      .filter(Boolean)
      .join('\n') || '';
  if (!text) {
    throw new Error('Gemini returned an empty response.');
  }
  return text.trim();
}

function compareSemver(a, b) {
  const pa = String(a || '0.0.0').replace(/^v/i, '').split('.').map(Number);
  const pb = String(b || '0.0.0').replace(/^v/i, '').split('.').map(Number);
  for (let i = 0; i < 3; i++) {
    const da = pa[i] || 0;
    const db = pb[i] || 0;
    if (da > db) return 1;
    if (da < db) return -1;
  }
  return 0;
}

async function checkForUpdates(currentVersion) {
  const resp = await fetch(GITHUB_URLS.releasesLatestApi, {
    headers: {
      Accept: 'application/vnd.github+json',
      'User-Agent': `LoopSearch-Windows/${currentVersion}`
    }
  });
  if (!resp.ok) {
    throw new Error(`GitHub check failed (${resp.status})`);
  }
  const data = await resp.json();
  const latestTag = String(data.tag_name || '').replace(/^v/i, '');
  const updateAvailable = latestTag ? compareSemver(latestTag, currentVersion) > 0 : false;
  return {
    currentVersion,
    latestVersion: latestTag || currentVersion,
    updateAvailable,
    releaseUrl: data.html_url || `${GITHUB_URLS.repo}/releases`,
    releaseNotes: data.body || ''
  };
}

function buildFeedbackIssueUrl({ rating, category, notes, appVersion, osVersion }) {
  const safeRating = Math.max(1, Math.min(5, Number(rating) || 5));
  const stars = '★'.repeat(safeRating) + '☆'.repeat(5 - safeRating);
  const title = `[Windows ${category || 'Feedback'}] ${stars} — LoopSearch v${appVersion}`;
  const body = [
    `**Platform:** ${osVersion}`,
    `**App Version:** v${appVersion}`,
    `**Category:** ${category || 'Feedback'}`,
    `**Rating:** ${stars} (${safeRating}/5)`,
    '',
    '### Details',
    (notes || '').trim() || '_No additional notes provided._'
  ].join('\n');

  const params = new URLSearchParams({ title, body });
  return `${GITHUB_URLS.issuesNew}?${params.toString()}`;
}

module.exports = {
  MOBILE_SAFARI_UA,
  GITHUB_URLS,
  buildMultipartLensBody,
  uploadToGoogleLens,
  extractLensResultUrlFromHtml,
  buildLensDarkThemeInjectionScript,
  runWindowsOcr,
  callGeminiVision,
  compareSemver,
  checkForUpdates,
  buildFeedbackIssueUrl
};
