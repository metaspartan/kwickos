# Kwick Effects

Kwick Effects are native desktop effects. They run as KWin effects on KDE Plasma, GNOME Shell extensions on GNOME and
Hyprland animations on Hyprland. They need a GPU compositor. On a software compositor `kwick-effects` writes the config and
tells you so.

## Presets

```sh
kwick-effects off|subtle|fluid|full
```

| preset | what you get |
|---|---|
| off | no animations |
| subtle | scale open/close, blur, sliding popups, magic lamp |
| fluid | plus curvy wobbly windows, sheets and the 3D flip open/close |
| full | plus flame open/close, translucency, dimmed inactive windows, the lit 3D desktop cube and Cover Flow Alt+Tab |

Every layout starts with the subtle look: magic lamp minimize into the dock and the quick scale open/close of macOS and
Windows. On GNOME, fluid keeps GNOME's own scale and full uses Fire, since Flip and Flame are KWin effects.

## Open and close

One open/close animation is active at a time. Pick it with `kwick-effects open-close STYLE` or the Animation menu on the Effects
page of KwickOS Settings, which plays a preview window right away and offers a duration slider (and the flame and 3D styles
when those are picked). `kwick-effects open-close` prints the current style, `kwick-effects open-close list` prints every style
as `name|on|off|na|label|description`, and `kwick-effects param duration MS` sets the length of the current one (100 to 5000;
built-in KWin effects such as Scale and Glide follow the global speed instead and have no duration).

| style | KDE | GNOME | what it does |
|---|---|---|---|
| `none` | yes | no | windows appear and disappear at once |
| `scale` | yes | yes (GNOME's own) | windows zoom in and out, like macOS and Windows |
| `fade` | yes | no | windows fade in and out |
| `glide` | yes (KWin) | yes | windows tilt in and out in 3D |
| `flip` | yes | no | windows swing in and out in perspective with lighting (styles flip, door, tilt) |
| `flame` | yes | no | windows ignite and burn away, with tongues of fire licking just above the title bar |
| `dissolve` | yes | no | closing windows crumble into glowing dust, which drifts up and fades out close to the window |
| `fallapart` | yes | no | closing windows shatter into pieces |
| `aura-glow`, `doom`, `energize-a`, `energize-b`, `fire`, `focus`, `glitch`, `hexagon`, `incinerate`, `pixelate`, `pixel-wheel`, `pixel-wipe`, `portal`, `rgbwarp`, `team-rocket`, `tv`, `tv-glitch`, `wisps` | yes | yes | [Burn My Windows](https://github.com/Schneegans/Burn-My-Windows) effects |
| `apparition`, `broken-glass`, `matrix`, `mushroom`, `paint-brush`, `snap`, `trex` | no | yes | Burn My Windows effects that exist only for GNOME Shell |

Styles a backend does not have show as `na` in `kwick-effects status` and are left out of the Settings menu. Hyprland has no
per-window shaders, so it keeps its own open/close animation (the `flip` toggle there) and reports every style as `na`.
`kwick-effects set STYLE on` still works and picks that style; `set STYLE off` goes back to `scale`.

Burn My Windows 49 (GPL-3.0, Simon Schneegans) comes from its release page at image build time, pinned by sha256, through
`/usr/lib/kwick/fetch-effects` (`fetch-effects / kwin` for the KWin effects in `/usr/share/kwin/effects/kwin6_effect_*`,
`fetch-effects / burn` for the GNOME extension, `all` for everything). The license is in
`/usr/share/licenses/burn-my-windows/LICENSE`. Two changes are made to the KWin effects: their translations are left out, and
they no longer force blur and background contrast behind a window while it animates, which drew a square blur box under
translucent windows (the same fix as Dissolve). KWin's own config dialogs for them stay in System Settings. On GNOME,
`kwick-effects` writes a high-priority Burn My Windows profile, `~/.config/burn-my-windows/profiles/kwickos.conf`, with only the
chosen effect enabled and its duration, so profiles you make in the extension's own settings keep working for other cases.

Burn My Windows Fire and the KwickOS Flame are both kept, since they look nothing alike: Flame burns the window away from
the bottom up along a sharp, charred edge, with tongues that only lick just above the title bar at the end, and is the full
preset's choice; Fire is the classic wall of soft flames over the whole window, and the only fire on GNOME. On KDE, `glide` is
KWin's native Glide. Burn My Windows' Glide is the same motion, but as a scripted shader effect it shows a still picture of the
window while it opens, so its KWin version is not installed.

All scripted shader effects on KDE (the Burn My Windows effects, Flame and Dissolve) open with the picture KWin takes of the
window when it first appears: KWin draws that one picture for the whole animation, so content an app paints a moment later
(Dolphin's folder view, say) shows up when the animation ends, and an app that resizes itself right after it appears (KCalc)
is stretched for that moment. Closing always uses the last picture of the window, so it is never affected. Scale, Fade,
Glide, Fall Apart and 3D Flip draw the live window.

## Single effects

Switch effects one at a time with `kwick-effects set NAME on|off` (for example `kwick-effects set wobbly on`), or with the toggles
on the Effects page of KwickOS Settings.

| name | what it does |
|---|---|
| `wobbly` | windows stretch like jelly while you drag them |
| `lamp` | magic lamp minimize into the dock |
| `cube` | Meta+C shows the desktops as a cube; the desktop switch animation can be a cube too (`kwick-effects switch cube`, Meta+Ctrl+Left/Right) |
| `blur`, `transparency`, `sheet`, `dim`, `overview` | frosted glass, translucency, dropping dialogs, dimmed inactive windows, overview |
| `liquidglass` | Liquid Glass: the dock, menu bar, menus, popups, notifications and OSDs refract and frost what is behind them (see below) |

All Kwick effects follow the global animation speed (`AnimationDurationFactor`, the slider in System Settings). At
"Instant" the flip, flame and dissolve effects are skipped. The desktop cube does not follow the slider yet.

## Options

* `kwick-effects wobbly AMOUNT SWAY` takes two numbers from 1 to 10 (`kwick-effects param wobbly` prints them). Amount is how far
  the window stretches. Sway is how curvy and fluid it is (softer springs and a finer mesh). The defaults are 6 and 7. In Settings
  they are the "Wobble" and "Sway" sliders.
* `kwick-effects flame-style classic|inferno|ember|blue|legacy` and `kwick-effects flame-height 50-200`:
  * Classic: orange fire along the burn line, coloured by temperature (a black-body ramp from dull red tips to yellow-white
    roots), with drifting embers and a charred, glowing edge.
  * Inferno: denser, taller and more turbulent.
  * Ember: a subtle burn edge with drifting sparks.
  * Blue: a hot gas flame.
  * Legacy: a particle-system burn. Many additive flame particles along a line sweep up the window, yellow-white to orange to
    deep red, in about one second.

  The burn is bounded by the window frame: the window burns away exactly inside its own edges and the fire never spreads past
  its sides or below its bottom. Only the tips of the last tongues may rise above the title bar, by at most 8 percent of the
  window height (40 px at the default height of 100) and never further than the window's own shadow reaches, so the effect
  never covers more than the window and its shadow. The shadow fades out with the part of the window it belongs to.
  `flame-height` scales the flames inside the window (and that small overflow), so 200 gives taller flames.
* `kwick-effects param flip flip|door|tilt` picks the 3D open/close style. Opening swings in on a damped spring (about 4%
  overshoot, settled by the end), closing accelerates away. The window is lit by a key and a fill light (Blinn-Phong
  highlight, Schlick Fresnel sheen, rim), the lighting stays on the window body and never on its shadow, and the texture is
  mipmapped with anisotropic filtering so text does not shimmer at steep angles. While it turns, the decoration's own
  shadow fades out and a soft shadow computed from the projected window outline (a Gaussian falloff of its signed distance,
  in logical pixels, so it is the same size on HiDPI) takes over below it.
* `kwick-effects param depth 0-10` sets how far windows float off the cube faces while it turns (the "Window depth" slider; default 5).
* `kwick-effects switch slide|fade|cube|none` sets the desktop switch animation.
* `kwick-effects tabbox windows|cover|flip|grid` sets the Alt+Tab style.

## Liquid Glass

Liquid Glass is a native KWin effect (`kwick_liquidglass`, source in `src/kwin-liquidglass`) modelled on the material Apple
introduced with macOS 26 and iOS 26. It is drawn under the dock, the menu bar, menus and popups, applet popups, notifications,
tooltips and OSDs, and optionally under window title bars.

<img src="img/liquidglass.png" width="860" alt="Liquid Glass dock and menu bar">

<img src="img/effects-liquidglass.gif" width="560" alt="a window moving behind the Liquid Glass dock">

How it is drawn, per glass surface:

* The shape is the bounding box of the surface's blur region (the mask Plasma and Breeze already send to KWin), drawn as a
  rounded rectangle with a signed distance field. The dock is 0.36 of its height (26 px on the 72 px dock), menus 10.5 px,
  applet popups 16 px, notifications 20 px, OSDs and the dock's name labels are capsules, Search is a capsule that becomes a 26 px rounded panel with results; they scale a little with the window
  corner radius setting. A bar that spans the screen, like the menu bar, only gets a bevel on its free edge and a fainter rim.
* Menus, popups and tooltips use a neutral dark frost: the colours behind are almost fully desaturated and darkened toward a
  neutral grey, so a red or orange wallpaper does not turn the menu brown. Notification banners adapt to what is behind them:
  the shader takes the average luminance of the blurred backdrop, and above about 0.55 the card becomes a light, bright frost
  (a 40% white veil over the saturated backdrop, no darkening) with dark text; below it, a darker frost that keeps the hue (a
  faint veil, then a multiply that darkens without greying) with white text. The two blend smoothly across the threshold. The text
  colour is switched in the same composite pass, from the same luminance, so it can never disagree with the material or flicker:
  near-white text right of the icon becomes black at 85% for the title and 50% for the body and timestamp, while the icon and
  anything coloured are left alone. The dock keeps the more saturated, clearer look.
* Menus, popups, notifications, labels and OSDs are drawn offscreen and cut to that rounded shape with an anti-aliased mask, so
  the app's own square or small-radius background corners never show outside the glass.
* Floating surfaces get a soft shadow drawn by the same pass (a Gaussian about 5 px wide, offset 2 px down, at 24% plus a short
  contact term, and a one-pixel darker edge when the backdrop is light so the glass still reads over white), faded out when the
  window has no margin around the glass for it, so it is never cut off square at the window edge.
* Ordinary windows are rounded by the same offscreen pass (it replaces the rounded-corners effect while Liquid Glass is on): the
  window is cut to the corner radius from Settings (10 px by default in the macOS layout) with an analytic one-pixel coverage
  edge, gets exactly one device pixel of white hairline inside the shape (9% on the active window, 5% on others) and one pixel of
  dark contact line outside it, and a soft drop shadow computed from the same rounded-rectangle distance field (offset 14 px with
  a 17 px falloff on the active window, 8 and 12 px on others, plus a short ambient falloff), so it stays concentric with the
  corner at any radius and still shows on a dark wallpaper. The Aurorae edge and shadow are covered by this pass. The window
  corners are taken out of its opaque region so whatever is behind shows through. Windows with a blur region, like a translucent
  Konsole, get their blur from the glass pass, cut to the same shape. Client-side decorated windows (GTK and libadwaita apps) get
  the same corners and shadow in place of their own. While a window is scaled or rotated (open and close animations, minimize)
  the cut follows the transform; while another effect deforms it (wobbly windows, the flame), KWin draws it normally with the
  decoration's own shadow, whose corners are concentric with the same radius. Maximized and full-screen windows are left square.
* The screen behind the surface is copied once and blurred with a dual-Kawase pyramid (3 or 4 levels at half resolution and below).
* A fragment shader treats the rim as a convex glass bevel, as on macOS 26: the lensing stays in a narrow band at the edge and the
  middle is flat, clear glass. The SDF gives the edge normal and a height profile whose slope rises steeply only near the edge
  (capped at 3) gives the surface slope; `refract()` with an index of 1.5 bends the view inward, so the content behind is pulled
  and magnified along the edges. The band is 14 px on the dock (about a fifth of its height), 7 px on menus, 9 px on popups and
  10 px on notifications, and the largest shift is under a band width. Red and blue are refracted a little less and a little
  more than green for a slight chromatic fringe at the rim.
* The frosted (blurred) and sharp images are mixed: the dock is 90% frost from a light blur, so what is behind stays recognisable
  but soft; the outer edge is a little sharper. Saturation is boosted by about 30%.
* Adaptive tint, kept low: the average brightness behind the glass sets how dark it gets, up to 10% on the dock over white and
  none over dark content, plus a 5% white lift, so the dock reads as nearly clear glass.
* A one-pixel luminous rim runs round the edge, brightest where it faces a light at the top left, with a softer reflection on the
  opposite edge; it reflects the backdrop, so it is brighter over light content. A faint Fresnel brightening sits on the bevel.
* Moving the pointer over the glass swings the light toward it and adds a soft glow under the pointer.

Performance: the blurred backdrop is cached per surface and output and is only recomputed when something under the glass changes;
a repaint of the panel itself (a clock tick, hovering an icon) only re-runs the final pass inside the damaged region. In the virgl
lab VM, dragging a window behind the dock ran at 35 to 36 fps with Liquid Glass against 33 to 35 fps with the plain blur effect
(the VM tops out there), so the glass costs no measurable frame time over KWin's own blur. GPU timer queries are not usable under
virgl, so there is no per-pass GPU time from real hardware yet.

It needs GPU rendering. `kwick-effects auto` runs at login: it turns Liquid Glass on when KWin renders on a GPU (unless you
switched it off), and always off on llvmpipe or other software OpenGL. The plugin also refuses to load on a software renderer. The
fluid and full presets switch it on, off and subtle switch it off, and `kwick-effects set liquidglass on|off` or the Settings
toggle switch it by hand.

While it is on, `kwick-effects` switches Plasma to a small generated desktop theme, `kwick-liquidglass` in
`~/.local/share/plasma/desktoptheme`, that makes the panel, dialog and tooltip backgrounds nearly clear, falls back to your
previous Plasma theme for everything else and turns the background contrast filter off. It also draws the menu bar item
highlight as a translucent white rounded pill. Breeze menus get `MenuOpacity=25` so the glass shows through them, and the
translucency effect keeps menus opaque. Switching Liquid Glass off restores the previous theme and menu opacity.

Menus are drawn by `KwickMac`, a small Qt widget style (`src/kwick-macstyle`, built by `scripts/mkmacstylepkg.sh`) that the macOS
layout selects. It is a proxy over Breeze, so everything else keeps the Breeze look and the dark palette; it only replaces menu
items: 22 px rows, a 5 px rounded accent highlight inset 5 px from the menu edge with white text and icons, 1 px separators
inset 10 px at 12% white, right-aligned shortcuts in the secondary label colour, disabled items at 25%, 5 px top and bottom
padding, checkmarks and submenu chevrons drawn as thin strokes. The same plugin also provides `KwickFluent`, which the Windows
layout selects: 8 px panels at #2c2c2c (#f9f9f9 in light) with a 1 px border and a softer shadow, 32 px rows with a 4 px rounded
hover fill inset 4 px, text that stays in the normal colour, an icon column whenever any item has an icon, and shortcuts in Windows
notation. Kvantum was considered; a full Kvantum theme would restyle every
widget and fight the palette, while the proxy changes menus only.

Notification popups use a Tahoe-style card from `/usr/local/share/plasma/plasmoids/org.kde.plasma.notifications` (Plasma 6.3.6's
notifications applet with a new popup delegate): 344 px wide with a 20 px radius, a 32 px app icon on the left, the title in
semibold, the body at 80% (black at 50% on the light material) clamped to two lines, a "now" / "5m ago" timestamp at the top right, and a round
close button that appears over the icon's corner on hover.

Tuning lives in `kwinrc`, group `[Effect-kwick_liquidglass]`, values in percent: `Refraction` (60), `Blur` (50), `Dispersion` (35),
`Specular` (70), `Tint` (100), `Style` (0 adaptive dark, 1 light, 2 clear), `TitleBars` (false, glass under translucent title
bars), `Interactive` (true), `Windows` (true, round and shadow ordinary windows) and `Profile` (0; 1 logs the animated frame interval and the glass GPU time every 600 frames to the
KWin log, 2 does the same with the glass skipped so the plain blur effect draws instead, for a baseline). Apply
changes with `qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect kwick_liquidglass`.

## GNOME and Hyprland

On GNOME the presets drive the extensions that are installed (wobbly, lamp, burn, cube, blur), and the wobble sliders map to the
wobbly extension. On Hyprland they write bezier-curve animations,
blur and dimming. Durations scale with the preset like the KDE animation speed (0.7 subtle, 0.8 fluid, 1 full). With flip on,
windows pop in from 60% on a spring curve with the same small overshoot as the KDE flip and close with an ease-in that fades
late; the cube setting becomes a horizontal slide-fade on an overshooting curve. The layout keeps its own corner radius and
shadow size; the effects file only switches the shadow on or off. Window opacity belongs to the effects file alone: the layouts set
no inactive opacity, so windows are opaque unless transparency is on (0.97 active, 0.88 inactive). The defaults in `hyprland.conf` come before the
`source` lines, so the effects file overrides them.

## Gallery

All GIFs were captured in a KVM guest with a virgl GPU (KWin on OpenGL) on the macOS layout, see [VERIFICATION.md](VERIFICATION.md).
The window effects were slowed down so every frame is a real render, the cube is sampled at fixed points of its animation
(`Scrub`, `ScrubFrom` and `ScrubTo` in `[Effect-kwick_cubeslide]` hold it at one point, for capture only), and the frames are
played back at a steady rate, so the real effects run faster and smoother. Frame sheets are next to them in `docs/img`
(`effects-*-frames.png`, and `effects-cube-before-frames.png`, `effects-3dopen*-before-frames.png` and
`effects-dissolve-before-frames.png` for the previous look).

| Wobbly windows (6/7) | Dissolve close | 3D desktop cube |
|---|---|---|
| <img src="img/effects-wobbly.gif" width="280" alt="wobbly"> | <img src="img/effects-dissolve.gif" width="280" alt="dissolve"> | <img src="img/effects-cube.gif" width="280" alt="cube"> |

| 3D open/close: flip | door | tilt |
|---|---|---|
| <img src="img/effects-3dopen.gif" width="280" alt="flip"> | <img src="img/effects-3dopen-door.gif" width="280" alt="door"> | <img src="img/effects-3dopen-tilt.gif" width="280" alt="tilt"> |

| Flame: classic | Flame: inferno | Flame: ember |
|---|---|---|
| <img src="img/effects-flame.gif" width="280" alt="flame classic"> | <img src="img/effects-flame-inferno.gif" width="280" alt="flame inferno"> | <img src="img/effects-flame-ember.gif" width="280" alt="flame ember"> |

| Flame: blue | Flame: legacy | Magic lamp |
|---|---|---|
| <img src="img/effects-flame-blue.gif" width="280" alt="flame blue"> | <img src="img/effects-flame-legacy.gif" width="280" alt="flame legacy"> | <img src="img/effects-magiclamp.gif" width="280" alt="magic lamp"> |

Burn My Windows on KDE, closing a window (each at twice its normal length):

| Aura Glow | Doom | Energize A |
|---|---|---|
| <img src="img/effects-bmw-aura-glow.gif" width="280" alt="aura glow"> | <img src="img/effects-bmw-doom.gif" width="280" alt="doom"> | <img src="img/effects-bmw-energize-a.gif" width="280" alt="energize a"> |

| Energize B | Fire | Focus |
|---|---|---|
| <img src="img/effects-bmw-energize-b.gif" width="280" alt="energize b"> | <img src="img/effects-bmw-fire.gif" width="280" alt="fire"> | <img src="img/effects-bmw-focus.gif" width="280" alt="focus"> |

| Glitch | Hexagon | Incinerate |
|---|---|---|
| <img src="img/effects-bmw-glitch.gif" width="280" alt="glitch"> | <img src="img/effects-bmw-hexagon.gif" width="280" alt="hexagon"> | <img src="img/effects-bmw-incinerate.gif" width="280" alt="incinerate"> |

| Pixelate | Pixel Wheel | Pixel Wipe |
|---|---|---|
| <img src="img/effects-bmw-pixelate.gif" width="280" alt="pixelate"> | <img src="img/effects-bmw-pixel-wheel.gif" width="280" alt="pixel wheel"> | <img src="img/effects-bmw-pixel-wipe.gif" width="280" alt="pixel wipe"> |

| Portal | RGB Warp | Team Rocket |
|---|---|---|
| <img src="img/effects-bmw-portal.gif" width="280" alt="portal"> | <img src="img/effects-bmw-rgbwarp.gif" width="280" alt="rgb warp"> | <img src="img/effects-bmw-team-rocket.gif" width="280" alt="team rocket"> |

| TV | TV Glitch | Wisps |
|---|---|---|
| <img src="img/effects-bmw-tv.gif" width="280" alt="tv"> | <img src="img/effects-bmw-tv-glitch.gif" width="280" alt="tv glitch"> | <img src="img/effects-bmw-wisps.gif" width="280" alt="wisps"> |

The Terminal glass profile, with blur and translucency:

<img src="img/glass-blur.png" width="860" alt="Terminal glass profile">
