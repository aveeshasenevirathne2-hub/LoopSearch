# LoopSearch Design System (`DESIGN.md`)

Exact visual, spatial, and motion tokens extracted directly from the macOS implementation (`Sources/LiquidGlass.swift`, `Sources/OverlayWindow.swift`, `Sources/SettingsWindow.swift`).

---

## 1. Color Tokens

### Obsidian Liquid Glass Surfaces (Dark Mode)
| Token | Hex / Value | Opacity / Usage |
| :--- | :--- | :--- |
| `--obsidian-base` | `#030409` | `0.94`–`0.985` base fill (`NSColor(red: 0.012, green: 0.016, blue: 0.034)`) |
| `--card-surface` | `#141D36` | `0.78` card background, `0.88` hover |
| `--web-underpage-dark` | `#121212` | `1.0` (`NSColor(white: 0.07)`) |
| `--web-underpage-light` | `#FAFAFA` | `1.0` (`NSColor(white: 0.98)`) |
| `--border-subtle-dark` | `#FFFFFF` | `0.08`–`0.16` inner & outer rim |
| `--border-subtle-light` | `#000000` | `0.08`–`0.14` |

### Horizon Luminous Well & Specular Rim
| Token | Hex | Alpha |
| :--- | :--- | :--- |
| `--horizon-core` | `#E0FAFF` | `0.86` |
| `--horizon-cyan` | `#24C2FF` | `0.76` |
| `--horizon-blue` | `#0580FA` | `0.60` |
| `--horizon-indigo` | `#29368F` | `0.38` |
| `--horizon-deep` | `#0A1A4D` | `0.18` |
| `--rim-top` | `#E0E8F5` | `0.78` |
| `--rim-mid` | `#3857A8` | `0.30` |
| `--rim-low-cyan` | `#1FBDFF` | `0.85` |
| `--rim-bottom-peak` | `#E6FAFF` | `0.95` |

### Selection Glow & Loader Orb (`BlueSearchOpticalOrbView`)
| Token | Hex | Usage |
| :--- | :--- | :--- |
| `--glow-apple-1` | `#38BDF8` | Primary Apple Blue cyan glow |
| `--glow-apple-2` | `#2563EB` | Deep Cobalt secondary glow |
| `--glow-apple-3` | `#60A5FA` | Soft Azure highlight |
| `--glow-apple-4` | `#818CF8` | Indigo gradient stop |
| `--glow-apple-5` | `#A5F3FC` | Specular white-cyan hairline |
| `--orb-core-bg` | `#040816` | `44pt` center obsidian-navy sphere (`alpha 0.94`) |
| `--orb-core-rim` | `#3DBDFF` | `1pt` luminous core border |
| `--orb-icon` | `#FFFFFF` | Crisp centered `18pt` magnifying glass |

### Text & Semantic Colors
| Token | Value | Usage |
| :--- | :--- | :--- |
| `--text-primary` | `#F4F7FF` (`.labelColor`) | Headings, active labels, Answer card body |
| `--text-secondary` | `rgba(214, 226, 248, 0.78)` | Subtitles, OCR snippet, secondary buttons |
| `--text-muted` | `rgba(154, 174, 208, 0.64)` | Placeholders, timestamps |

---

## 2. Corner Radii & Geometry

All macOS surfaces use continuous curvature (`.continuous`).

| Element | Radius |
| :--- | :--- |
| Results Sheet Outer Shell (`SheetBackdropView`) | `24 pt` |
| Dialog / Studio Window Outer Shell | `22 pt` |
| Inner Cards (`aiAnswerCard`, `errorStateCard`, `webClipView`, `webView`) | `14 pt` |
| Selection Box Rounded Rect | `16 pt` |
| Capture Thumbnail (`cropThumb`) | `10 pt` |
| Pills, Action Chips, Search Bar, Segmented Control, Circle Buttons | `999 pt` (`height / 2`) |

---

## 3. Spacing & Dimensions

| Element | Dimensions / Spacing |
| :--- | :--- |
| **Results Sheet Default Size** | **`760 × 620 pt`** (min width `520 pt`, min height `420 pt`, resizable) |
| Results Sheet Inner Padding | `10 pt` horizontal, `8 pt` top, `10 pt` bottom |
| Results Sheet Vertical Stack Spacing | `8 pt` |
| Top Header Bar Height | `26 pt` |
| Header Circle Icon Buttons | `26 × 26 pt` (`spacing: 4 pt`) |
| Segmented Header (`Answer \| Lens`) | `26 pt` height, capsule radius |
| Thumbnail + Search Field Row | Thumbnail `38 × 38 pt`, Search pill `34 pt` height |
| Action Chips Row | `27 pt` height, `6 pt` horizontal gap |
| Optical Loader Orb | `44 pt` core, `50 pt` inner ring, `58 pt` comet ring (`2 pt` stroke), `76 pt` outer halo |

---

## 4. Typography (`SF Pro` / System Font)

| Role | Size | Weight |
| :--- | :--- | :--- |
| Studio / Dialog Main Title | `16.5 pt` | `.bold` (`700`) |
| Segmented Control / Sheet Header | `11 pt` | `.semibold` (`600`) |
| Search Input / Follow-up Input | `12.5 pt` | `.regular` (`400`) |
| Action Chips | `11 pt` | `.semibold` (`600`) |
| Answer Card Body | `12 pt` | `.medium` (`500`) |
| OCR Snippet Preview | `11.2 pt` | `.regular` (`400`) |
| Section Eyebrows | `10.5 pt` | `.semibold` (`600`, uppercase) |

---

## 5. Blur & Shadows

- **Results Sheet Shadow (Resting)**: `opacity: 0.42`, `radius: 26 pt`, `offset: (0, -8)`
- **Results Sheet Shadow (Grabbed)**: `opacity: 0.54`, `radius: 32 pt`, `offset: (0, -12)`
- **Surface Material**: `NSVisualEffectView` (`.hudWindow` / `.popover`) layered behind obsidian `LiquidGlassSurfaceView` with `0.75–1.0 pt` specular border.

---

## 6. Motion & Animation Curves (`AppleMotion`)

| Token | Value | Usage |
| :--- | :--- | :--- |
| `--ease-out` | `cubic-bezier(0.22, 1.0, 0.36, 1.0)` | Opacity & fade-ins (`0.24s`–`0.34s`) |
| `--ease-in-out` | `cubic-bezier(0.65, 0.0, 0.35, 1.0)` | Smooth state transitions |
| `--ease-in` | `cubic-bezier(0.32, 0.0, 0.67, 0.0)` | Dismissals (`0.18s`–`0.24s`) |
| `--spring-snappy` | `dampingRatio: 0.82`, `response: 0.34s` | Panel pop-in, chip clicks, sheet grab/release |
| `--spring-reveal` | `dampingRatio: 0.80`, `response: 0.44s` | Card stagger reveal (`baseDelay: 0.03s`, `stepDelay: 0.04s`) |
| `--drag-inertia` | `decay = exp(-12.5 * dt)`, `maxSpeed: 1400 pt/s` | Sheet & capsule throw settling |
| `--reduce-motion` | Scales durations by `0.35`, disables `CASpringAnimation` bounce | `AppSettings.shared.effectiveReduceMotion` |
