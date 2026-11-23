# Palette

The macOS and Windows 11 layouts use the dark colours of the systems they imitate, taken from published values rather than
eyeballed. The Linux layout keeps its own Tokyo Night palette. This page lists every value, where it comes from, and where
KwickOS uses it.

`over(a, bg)` below means white at alpha `a` composited on a grey background `bg`, rounded: `round(255 * a + bg * (1 - a))`.
KDE colour schemes only take opaque colours, so Apple's translucent label colours are pre-composited on the surface they sit on.

## macOS dark (NSColor, Monterey through Sonoma)

| NSColor (dark appearance) | Value | KwickOS use |
|---|---|---|
| `windowBackgroundColor` | `#323232` (50, 50, 50) | KDE Window, Header (toolbars), Tooltip; KwickGlass title bar (active); GTK `window_bg_color`, `headerbar_bg_color`, popovers and dialogs; menus |
| `underPageBackgroundColor` | `#282828` (40, 40, 40) | KwickGlass title bar and KDE Header when inactive; GTK `headerbar_backdrop_color`; sidebars (stands in for sidebar vibrancy); Settings sidebar |
| `controlBackgroundColor` | `#1E1E1E` (30, 30, 30) | KDE View (file lists, editors); GTK `view_bg_color`; Settings and installer page background; Terminal background |
| `textBackgroundColor` | `#1E1E1E` (30, 30, 30) | same surfaces as above |
| `alternatingContentBackgroundColors[1]` | white at 0.047 | KDE View alternate row `over(0.047, 30)` = `#292929`; Settings cards; GTK `card_bg_color` |
| `labelColor` | white at 0.847 | text: `over(0.847, 50)` = `#E0E0E0` on windows, `over(0.847, 30)` = `#DDDDDD` on views; `#D8FFFFFF` in QML; GTK fg colours |
| `secondaryLabelColor` | white at 0.549 | inactive text: `#A3A3A3` on windows, `#9A9A9A` on views; `#8CFFFFFF` in QML |
| `tertiaryLabelColor` | white at 0.247 | inactive title text `over(0.247, 40)` = `#5D5D5D`; faint text `#3FFFFFFF` |
| `quaternaryLabelColor` | white at 0.098 | hover fills in Settings |
| `separatorColor` | white at 0.098 | borders and separators (`#19FFFFFF`), GTK `borders` |
| `gridColor` | `#1A1A1A` (Monterey dump) | not used |
| `controlColor` | white at 0.247 | buttons: KDE Button `over(0.247, 50)` = `#656565`; Settings buttons `#3FFFFFFF` |
| `selectedContentBackgroundColor` | `#0058D0` (0, 88, 208) with the blue accent | KwickOS uses the orange equivalent, see [Accent](#accent) |
| `unemphasizedSelectedContentBackgroundColor` | `#464646` (70, 70, 70) | Settings switch and slider tracks; GTK3 unfocused selection |
| `selectedTextBackgroundColor` | `#3F638B` (63, 99, 139) with the blue accent | KwickOS uses the orange equivalent, see [Accent](#accent) |
| `linkColor` | `#419CFF` (65, 156, 255) | KDE ForegroundLink; GTK links. It stays blue whatever the accent, as on macOS |
| `controlAccentColor` | the chosen accent | the accent, `systemOrange` by default, see [Accent](#accent) |

| System colour (dark) | Value | KwickOS use |
|---|---|---|
| `systemBlue` | `#0A84FF` | blue accent when chosen in Settings |
| `systemGray` | `#98989D` | "graphite" accent, neutral title buttons |
| `systemRed` | `#FF453A` | negative text, errors, Settings `bad` |
| `systemOrange` | `#FF9F0A` | default accent (KDE AccentColor, focus, active text, sidebar glyphs), menu highlight, Settings accent; neutral text, warnings, attention dot in the dock |
| `systemYellow` | `#FFD60A` | yellow accent |
| `systemGreen` | `#32D74B` (Monterey dump) | positive text, Settings `good` |
| `systemPurple` | `#BF5AF2` | visited links, purple accent |
| `systemPink` | `#FF375F` | pink accent |
| `systemIndigo` | `#5E5CE6` | Settings icon tint |

Window controls: close `#FF5F57`, minimise `#FEBC2E`, zoom `#28C840`.

### Accent

The macOS layout's default accent is Apple's orange, `systemOrange`: `#FF9F0A` (255, 159, 10) in the dark appearance and
`#FF9500` (255, 149, 0) in the light one. `kwick-layout` derives every other accent colour from the chosen accent with one
formula (`DERIVE` in `kwick-layout`, printed by `kwick-layout colors`), so the eight Apple colours, the deeper ones and a custom
colour all get the same treatment. For orange:

| Role | Dark | Light | How it is derived | KwickOS use |
|---|---|---|---|---|
| `controlAccentColor` | `#FF9F0A` | `#FF9500` | the swatch | KDE `AccentColor`, DecorationFocus and DecorationHover (focus rings, hover, Control Center toggles), Settings switches and sliders, App Store, Spotlight, installer |
| fill | `#D28308` | `#D97F00` | the accent with its brightness lowered until white text on it reaches 3:1 | GTK `accent_bg_color` (suggested buttons, menu highlight), Settings and App Store filled buttons, fuzzel selection |
| hover, pressed | `#C17907`, `#B06E07` | `#C87500`, `#B66B00` | the fill at 92 % and 84 % brightness, so white text stays above 3:1 | Settings buttons |
| accent as text | `#FF9F0A` | `#9C5B00` | the accent brightened (dark) or darkened (light) until it reaches 4.5:1 on the window colour `#323232` or `#ECECEC` | GTK `accent_color`, Settings and App Store accent text, accent sidebar icons |
| `selectedContentBackgroundColor` | `#D06F00` (208, 111, 0) | `#E07A00` (224, 122, 0) | the highlight colour at 1.15 times its saturation, brightness 0.816 (dark) or 0.882 (light), hue moved 4.5 or 2.3 degrees towards the nearest of red, green and blue; then darkened until white text reaches 3:1 | KDE Selection (list and text selection, white text), GTK 3 `theme_selected_bg_color` |
| `selectedTextBackgroundColor` | `#896B42` (137, 107, 66) | `#FFDFB3` (255, 223, 179) | 30 % of the highlight colour over `#565559` (dark) or white (light) | foot selection, GTK text selection, Settings text fields |
| `linkColor` | `#419CFF` | `#0068DA` | fixed | links stay blue, as macOS keeps `linkColor` blue with every accent |

The selection formula reproduces Apple's published blue pair: `#0058D0` and `#3F638B` for `#0A84FF`, `#B3D7FF` for `#007AFF`.
White text measures at least 3:1 on every fill, hover, pressed and selection colour, and the accent used as text measures at
least 4.5:1 on the window colour, for every accent in both appearances. The Apple swatches themselves are kept as Apple ships
them for the non-text uses (orange, yellow and green measure 2.2:1, 1.5:1 and 2.2:1 on white, as on macOS).

#### Accent colours

Settings > Appearance shows Apple's eight accents in the first row and nine deeper ones in the second, followed by a custom
colour picker. `kwick-layout accent list` prints them; `kwick-layout accent NAME` or `kwick-layout accent '#RRGGBB'` picks one.

| Name | Accent, dark / light | Fill | Accent as text | Selection |
|---|---|---|---|---|
| blue | `#0A84FF` / `#007AFF` | `#0A84FF` / `#007AFF` | `#3B9DFF` / `#0067D7` | `#0058D0` / `#0063E1` |
| purple | `#BF5AF2` / `#AF52DE` | `#BF5AF2` / `#AF52DE` | `#CF71FF` / `#9646BE` | `#8B37C5` / `#8F36C4` |
| pink | `#FF375F` / `#FF2D55` | `#FF375F` / `#FF2D55` | `#FF6584` / `#CD2444` | `#D0142C` / `#E10C2C` |
| red | `#FF453A` / `#FF3B30` | `#FF453A` / `#FF3B30` | `#FF685F` / `#C92F26` | `#D01717` / `#E1120F` |
| orange | `#FF9F0A` / `#FF9500` | `#D28308` / `#D97F00` | `#FF9F0A` / `#9C5B00` | `#D06F00` / `#E07A00` |
| yellow | `#FFD60A` / `#FFCC00` | `#AF9307` / `#B49000` | `#FFD60A` / `#826800` | `#BA8E00` / `#BB8E00` |
| green | `#30D158` / `#34C759` | `#27A947` / `#2CAA4C` | `#30D158` / `#207A37` | `#13AB2E` / `#19AB38` |
| graphite | `#98989D` / `#8E8E93` | `#949499` / `#8E8E93` | `#99999E` / `#6A6A6E` | `#7B7B80` / `#7D7D82` |
| deepblue | `#4070FF` / `#0040DD` | `#4070FF` / `#0040DD` | `#7295FF` / `#0040DD` | `#1D3CD0` / `#0031C3` |
| indigo | `#5E5CE6` / `#5856D6` | `#5E5CE6` / `#5856D6` | `#8F8EFE` / `#5856D6` | `#3A3ABC` / `#3B3BBD` |
| teal | `#30B0C7` / `#008299` | `#2CA2B8` / `#008299` | `#30B0C7` / `#00758A` | `#1582A2` / `#006D87` |
| forest | `#40AA68` / `#1E7A3C` | `#3FA766` / `#1E7A3C` | `#41AD6A` / `#1E7A3C` | `#278B45` / `#0E6C29` |
| crimson | `#EC405A` / `#B3122E` | `#EC405A` / `#B3122E` | `#FE667D` / `#B3122E` | `#C11F2B` / `#9E0015` |
| burntorange | `#EE6C2E` / `#C2410C` | `#EE6C2E` / `#C2410C` | `#F87130` / `#BE400C` | `#C23B0E` / `#AB2B00` |
| plum | `#BA68C8` / `#7E3A9E` | `#BA68C8` / `#7E3A9E` | `#D275E2` / `#7E3A9E` | `#8F49A3` / `#67268B` |
| brown | `#AC8E68` / `#8A6A45` | `#AC8E68` / `#8A6A45` | `#B4946D` / `#846542` | `#8C6B4D` / `#7A5734` |
| slate | `#8494A8` / `#5B6B7F` | `#8494A8` / `#5B6B7F` | `#8A9BB0` / `#5B6B7F` | `#677489` / `#4B5A70` |

A custom colour is used as picked, except that it is brightened in the dark appearance until it reaches 2.5:1 on `#1E1E1E`
and darkened in the light one until it reaches 1.5:1 on white, so a near-black or near-white pick stays visible. GNOME Shell
only knows nine named accents, so for the deeper and custom colours `kwick-layout` sets the nearest one (`accent-color`) while
GTK 4 apps get the exact colour from `~/.config/gtk-4.0/gtk.css`.

The choice is stored in `~/.config/kwick/accent` (`default` follows the layout) and applies to every layout and desktop;
without a choice the macOS layout uses orange and the Windows and Linux layouts keep `#0078D4` and the Tokyo Night blue.

#### Highlight colour

Like macOS's separate Highlight color, `kwick-layout highlight accent|graphite|NAME|#RRGGBB` (`~/.config/kwick/highlight`,
`accent` by default) picks the colour of list and text selection independently of the accent:

* `accent` follows the accent, as in the table above.
* `graphite` is neutral: `unemphasizedSelectedContentBackgroundColor` `#464646` with white text in the dark appearance,
  `#DCDCDC` with dark text (`#262626`) in the light one, for list and text selection alike.
* any accent name or colour derives the selection and text selection colours from that colour with the formula above.

It applies to the KDE Selection colours, GTK 3 `theme_selected_bg_color` and `theme_selected_fg_color`, GTK text selection,
foot and Settings text fields. Sidebars do not follow it in the macOS layout: as in Finder and System Settings, the selected
sidebar row is a subtle translucent grey (white at 0.1 in the dark appearance, black at 0.08 in the light one, rounded, with
normal text), in Dolphin and KDE file dialogs (the KwickMac style draws `KFilePlacesView` rows), GTK 3 and GTK 4 sidebars,
Settings and the App Store. The Windows and Linux layouts keep sidebar selection in the highlight colour.

#### Sidebar icons

Sidebar glyphs of the three KwickOS icon themes use `ColorScheme-ActiveText`, and `kwick-layout sidebar neutral|accent`
(`~/.config/kwick/sidebar`) sets KDE's ForegroundActive to the text colour or to the accent as text. Neutral, the default in
the macOS and Windows layouts, draws them white (dark) or dark grey (light); accent, the Linux layout's default and what macOS
itself does, draws them in the accent. GTK sidebars (`@SIDEBAR_ICON@`), Settings and the App Store follow the same choice.

#### Wallpaper tinting

`kwick-layout tint on|off|default` (`~/.config/kwick/tint`) is macOS's "Allow wallpaper tinting in windows":

* Plasma: `kwick-layout` writes `WallpaperTint=true` to `[KwickOS]` in `kdeglobals`. The KwickMac style then makes the main
  windows of the apps in `TintApps` (`dolphin` by default, comma separated) translucent: it paints the window colour at 0.82
  (dark) or 0.84 (light) opacity, clears the base colour of the Places sidebar and asks KWin to blur behind the window. The
  toolbar and sidebar show a blurred tint of the wallpaper while the file view stays opaque. Breeze 6.3 itself has no
  translucent windows (only `MenuOpacity`), and an alpha in the colour scheme would darken every other Qt window, so the colour
  scheme stays opaque. Open Files windows are reopened when the switch changes.
* Settings: the sidebar becomes translucent at the same opacity and `kwick-settings-app` asks KWin for blur behind the window.
* Hyprland: file managers, Settings, System Settings and the App Store get `opacity 0.94 0.9` (`~/.config/hypr/kwick-tint.conf`),
  which Hyprland's blur fills in.
* GNOME Shell and sway have no blur behind application windows, so tinting does nothing there.

It is on by default in the macOS layout while KWin's blur effect is on, and off in the Windows and Linux layouts. Blur behind
one window is a single blur pass in KWin's existing blur effect, the same work it already does for every menu and the dock, so
it costs nothing noticeable with a GPU; `kwick-effects` turns blur off on software rendering, and the next `kwick-layout` run turns tinting off with it.

### Materials

AppKit materials (menu, popover, sidebar, title bar, HUD) are blurred and tinted live, so they have no single published value.
KwickOS approximates them with the documented solid colour of the same surface plus blur where the desktop supports it:

| Material | Approximation |
|---|---|
| Menu bar | `#1E1E1E` at 0.6 over blur (GNOME panel, Hyprland waybar); KwickGlass Plasma theme `#323232` at 0.55 over blur, no border |
| Dock | `#323232` at 0.55 over blur, 1 px white 0.15 border, 18 px radius, white dot at 0.55 under running apps |
| Menus and popovers | `windowBackgroundColor` `#323232`, separator border, accent (`systemOrange`) highlight |
| Sidebar | `underPageBackgroundColor` `#282828` (GTK) or the window colour (KDE, which has no separate sidebar role) |
| Title bar | `windowBackgroundColor` active, `underPageBackgroundColor` inactive, title in `labelColor`, bold |

### Terminal.app, Basic profile in dark mode

| Role | Value |
|---|---|
| Background | `#1E1E1E` (`textBackgroundColor`) |
| Text | `#FFFFFF` (`textColor`) |
| Selection | `#896B42` (`selectedTextBackgroundColor` for the orange accent, see [Accent](#accent)) |
| Cursor | `#929292`, block (approximation, see below) |
| ANSI 0 to 7 | `#000000` `#990000` `#00A600` `#999900` `#0000B2` `#B200B2` `#00A6B2` `#BFBFBF` |
| ANSI 8 to 15 | `#666666` `#E60000` `#00D900` `#E6E600` `#0000FF` `#E600E6` `#00E6E6` `#E6E6E6` |

### Typography

macOS uses SF Pro at 13 pt for body text and bold 13 pt for window titles. KwickOS uses Inter at 10 pt (13.3 px at 96 dpi) for the
UI and Inter weight 700 for KDE window titles, Inter Bold for GNOME title bars, 13 px in waybar and the GNOME menu bar.

## Windows 11 dark (WinUI 2 theme resources)

| Resource (Default/dark dictionary) | Value | KwickOS use |
|---|---|---|
| `SolidBackgroundFillColorBase` | `#202020` | KDE Window, Header, KwickFluent title bar (active and inactive, as Mica falls back to it); GTK window, headerbar; GNOME taskbar |
| `SolidBackgroundFillColorSecondary` | `#1C1C1C` | KDE View (Explorer-like content); GTK view |
| `SolidBackgroundFillColorTertiary` | `#282828` | not used |
| `SolidBackgroundFillColorQuarternary` | `#2C2C2C` | not used |
| `CardBackgroundFillColorDefault` | `#0DFFFFFF` | KDE Window alternate `over(0.051, 32)` = `#2B2B2B`; GTK cards |
| `CardBackgroundFillColorSecondary` | `#08FFFFFF` | KDE View alternate `#232323` |
| `ControlFillColorDefault` | `#0FFFFFFF` | KDE Button `over(0.059, 32)` = `#2D2D2D` |
| `ControlFillColorSecondary` | `#15FFFFFF` | KDE Button alternate `#323232`; focused taskbar button in waybar |
| `SubtleFillColorSecondary` | `#0FFFFFFF` | hover in waybar, fuzzel, caption buttons, Plasma taskbar |
| `SubtleFillColorTertiary` | `#0AFFFFFF` | pressed caption buttons |
| `TextFillColorPrimary` | `#FFFFFF` | text |
| `TextFillColorSecondary` | `#C5FFFFFF` | inactive text `over(0.773, 32)` = `#CCCCCC` |
| `TextFillColorTertiary` | `#87FFFFFF` | inactive title text `over(0.529, 32)` = `#969696` |
| `TextFillColorDisabled` | `#5DFFFFFF` | inactive caption glyphs `#717171` |
| `DividerStrokeColorDefault` | `#15FFFFFF` | borders in GTK |
| `ControlStrokeColorDefault` | `#12FFFFFF` | not used |
| `SurfaceStrokeColorDefault` | `#66757575` | fuzzel, mako and tooltip borders |
| `SystemFillColorSuccess` / `Caution` / `Critical` | `#6CCB5F` / `#FCE100` / `#FF99A4` | positive, neutral, negative text |
| `SystemFillColorSolidNeutral` | `#9D9D9D` | running-app indicator in the taskbar |
| `AcrylicBackgroundFillColorDefault` | tint `#2C2C2C` at 0.15, fallback `#2C2C2C` | tooltips, fuzzel, notifications, GTK popovers |
| `AcrylicBackgroundFillColorBase` | tint `#202020` at 0.5, fallback `#1C1C1C` | taskbar (`#202020` at 0.85 over blur) |
| Mica (`MicaController`) | dark tint `#202020` at 0.8 | window and title bar colour |
| `SystemAccentColor` (default blue) | `#0078D4` | accent, selection |
| `AccentFillColorDefault` (`SystemAccentColorLight2`) | `#60CDFF` | focus, active text, focused-app pill in the taskbar |
| `AccentTextFillColorPrimary` (`SystemAccentColorLight3`) | `#99EBFF` | links |

Caption buttons: hover white at 0.0588, pressed white at 0.0392, close hover `#C42B1C`.

### Windows Terminal, Campbell (default scheme)

Background `#0C0C0C`, text `#CCCCCC`, cursor `#FFFFFF`.
ANSI 0 to 7: `#0C0C0C` `#C50F1F` `#13A10E` `#C19C00` `#0037DA` `#881798` `#3A96DD` `#CCCCCC`.
ANSI 8 to 15: `#767676` `#E74856` `#16C60C` `#F9F1A5` `#3B78FF` `#B4009E` `#61D6D6` `#F2F2F2`.

## Where the values live

| Surface | macOS layout | Windows layout |
|---|---|---|
| KDE colour scheme | `KwickGlass.colors` | `KwickFluent.colors` |
| Window decoration | Aurorae `KwickGlass` | Aurorae `KwickFluent` |
| Plasma panels | desktop theme `kwick-glass` | desktop theme `kwick-fluent` |
| Konsole | `KwickGlass.colorscheme`, `KwickOS.profile` | `KwickFluent.colorscheme`, `KwickFluent.profile` |
| GTK 3 and 4 | `kwick/gtk/macos/*.css` | `kwick/gtk/windows/*.css` |
| GNOME Shell | `kwick/gnome/macos.settings`, `kwick-menubar` stylesheet | `kwick/gnome/windows.settings` |
| GNOME Terminal | `kwick-layout` (`gnometerm`) | `kwick-layout` (`gnometerm`) |
| Hyprland and sway | `kwick/tiling/macos/*` | `kwick/tiling/windows/*` |
| KwickOS Settings, installer | `Theme.qml` (one theme, macOS palette) | same |

Colour schemes, decorations, Plasma themes and Konsole schemes are generated by `desktop/gen-theme.py`; the constants `MAC` and
`FLU` at the top of that script hold the values above.

## Sources

macOS:

- Andrej Jilderda, NSColor dump for macOS Monterey 12.0.1 and Big Sur 11.2.3 in light and dark appearance:
  <https://gist.github.com/andrejilderda/8677c565cddc969e6aae7df48622d47c>. Source of every NSColor value above.
- Felix Foertsch, macOS dark appearance colours: <https://gist.github.com/felixfoertsch/52904ab569521158dd8494024c0a5d77>.
  Agrees on `windowBackgroundColor` 50, `underPageBackgroundColor` 40, `controlBackgroundColor` and `textBackgroundColor` 30,
  `selectedContentBackgroundColor` `#0058D0`, `unemphasizedSelectedContentBackgroundColor` 70 and `systemGray` `#98989D`
  (it rounds the label alphas to 0.8, 0.5, 0.2 and 0.1).
- Apple Human Interface Guidelines, Color: <https://developer.apple.com/design/human-interface-guidelines/color>, for the
  system colour names and the note that colours behind translucent materials change.
- Apple, NSColor `controlBackgroundColor` and `windowBackgroundColor` reference pages for the role of each colour.
- Terminal.app ANSI palette: the Terminal.app column of the colour table in
  <https://en.wikipedia.org/wiki/ANSI_escape_code>. Basic in dark mode draws on `textBackgroundColor` with `textColor`.

Windows 11:

- `dev/CommonStyles/Common_themeresources_any.xaml` in microsoft/microsoft-ui-xaml (branch `winui2/main`), Default (dark)
  dictionary: every `*FillColor*`, `*StrokeColor*` and `SolidBackgroundFillColor*` value above.
- `dev/Materials/Acrylic/AcrylicBrush_19h1_themeresources.xaml`, same repository: acrylic tints and fallbacks.
- `dev/Materials/Backdrop/MicaController.h`, same repository: `sc_darkThemeColor` 32, 32, 32 and tint opacity 0.8.
- Windows Terminal `defaults.json`, Campbell scheme, for the terminal colours.

A third published dump (fltk-theme's `aqua/dark.rs`) gives different numbers (for example `systemBlue` 16, 106, 254); it was read in
Display P3 or a device colour space, not sRGB, so it is not used.

## Not verified

- macOS Tahoe (26) redraws windows with Liquid Glass; its dark colours have not been dumped publicly, so the Sonoma values are used.
- The Terminal.app Basic cursor colour (`#929292`) and the menu, dock and menu bar materials are approximations, not published values.
- The Breeze widget style draws Qt menus in a mix of the Window and View colours, so KDE menus measure `#2C2C2C` in the macOS
  layout and `#1F1F1F` in the Windows layout instead of `#323232` and `#202020`. GNOME menus and popovers use the exact values.
- The orange `selectedContentBackgroundColor` and `selectedTextBackgroundColor` are derived from the blue values (see
  [Accent](#accent)), not dumped from a Mac set to orange.
- With an accent chosen in Settings, KDE's own accent code colours the selection (the accent at 70 % over the view) and the
  links (the accent, lightened or darkened for contrast), as it did before the default became orange.
