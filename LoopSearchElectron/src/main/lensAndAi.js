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
 * Injects obsidian dark theme CSS + Google Lens chrome cleanup (eliminates double input boxes,
 * cobalt link highlight blocks, empty top spacers, and right-edge thumbnail clipping).
 */
function buildLensDarkThemeInjectionScript(_enableDark) {
  const cleanCss = `
    header, #searchform,
    #sfcnt, #tophf,
    div[data-hveid] input[aria-label*="Add to your search"],
    div[jscontroller] > div > a[aria-label="Google"],
    div[aria-label="Add to your search"],
    hr, [role="separator"] {
      display: none !important;
    }
    html, body {
      width: 100% !important;
      max-width: 100% !important;
      padding-top: 10px !important;
      padding-bottom: 14px !important;
      margin-top: 0 !important;
      overflow-x: hidden !important;
      box-sizing: border-box !important;
    }
    main, [role="main"], c-wiz, form {
      max-width: 100% !important;
      min-width: 0 !important;
      box-sizing: border-box !important;
    }
    img, video, svg { max-width: 100% !important; }
    c-wiz img:not(a[href] img), [role="main"] img:not(a[href] img) {
      object-fit: contain !important;
    }
    div[data-attrid], div[data-hveid], section, c-wiz {
      margin-bottom: 4px !important;
    }
  `.replace(/\s+/g, ' ');

  const cleanJs = `
    function runCleanPass() {
      if (!document.body) return;
      var walker = document.querySelectorAll('input, span, div, form[action="/search"], [role="search"]');
      for (var i = 0; i < walker.length; i++) {
        var el = walker[i];
        if (el.getAttribute('data-cts-keep') === '1' || el.querySelector('textarea')) continue;
        if (el.tagName === 'FORM' || el.getAttribute('role') === 'search') {
          var fr = el.getBoundingClientRect();
          if (fr.top < 170 && fr.height < 130) el.style.setProperty('display', 'none', 'important');
          continue;
        }
        var txt = (el.getAttribute('placeholder') || el.getAttribute('aria-label') || '').toLowerCase();
        if (txt.indexOf('add to your search') !== -1) {
          var box = el.closest('form') || el.closest('[role="search"]') || el.parentElement;
          if (box && box.offsetHeight < 120 && !box.querySelector('textarea')) box.style.setProperty('display', 'none', 'important');
        }
      }
      var allDivs = document.querySelectorAll('div, section, nav');
      for (var j = 0; j < allDivs.length; j++) {
        var d = allDivs[j];
        if (d.getAttribute('data-cts-keep') === '1') continue;
        var dcs = window.getComputedStyle(d);
        if (dcs.position === 'fixed' || dcs.position === 'sticky' || dcs.overflowY === 'auto' || dcs.overflowY === 'scroll') continue;
        var rect = d.getBoundingClientRect();
        var textTrim = (d.innerText || '').trim();
        if (rect.top >= -12 && rect.top < 140 && rect.height >= 10 && rect.height <= 180) {
          var hasMedia = d.querySelector('img, svg, canvas, video, input, textarea, [role="tab"], [role="button"], button, a');
          if (textTrim.length === 0 && !hasMedia) {
            d.style.setProperty('display', 'none', 'important');
            d.style.setProperty('height', '0px', 'important');
            d.style.setProperty('margin', '0px', 'important');
            d.style.setProperty('padding', '0px', 'important');
          }
        }
      }
    }
  `.replace(/\s+/g, ' ');

  // Never override Google's colors/links via DOM CSS — let prefers-color-scheme handle Light/Dark cleanly.
  return `(function(){
    var u = location.href.toLowerCase();
    if (u.includes('/sorry') || u.includes('recaptcha') || u.includes('accounts.google.') || u.includes('consent.google.')) return;
    var oldDark = document.getElementById('__loopsearch_dark_css');
    if (oldDark) oldDark.remove();
    if (window.__loopsearchDarkObs) {
      window.__loopsearchDarkObs.disconnect();
      window.__loopsearchDarkObs = null;
    }
    var ce = document.getElementById('__loopsearch_clean_css');
    if (!ce && (document.head || document.documentElement)) {
      ce = document.createElement('style');
      ce.id = '__loopsearch_clean_css';
      ce.textContent = ${JSON.stringify(cleanCss)};
      (document.head || document.documentElement).appendChild(ce);
    }
    ${cleanJs}
    runCleanPass();
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
