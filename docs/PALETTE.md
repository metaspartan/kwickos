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
`#FF9500` (255, 149, 0) in the light one. The colours AppKit derives from the accent are derived the same way for orange:

| Role | Dark | Light | KwickOS use |
|---|---|---|---|
| `controlAccentColor` | `#FF9F0A` | `#FF9500` | KDE `AccentColor`, DecorationFocus and DecorationHover (focus rings, hover, Control Center toggles), ForegroundActive (sidebar glyphs through `ColorScheme-ActiveText`), Qt menu highlight, GTK `accent_bg_color`, Settings switches and buttons, App Store, Spotlight, installer |
| `selectedContentBackgroundColor` | `#D06F00` (208, 111, 0) | `#E17B00` (225, 123, 0) | KDE Selection (list and text selection, white text), GTK 3 `theme_selected_bg_color`, Settings sidebar selection |
| `selectedTextBackgroundColor` | `#896B42` (137, 107, 66) | `#FFDFB3` (255, 223, 179) | foot selection, GtkSourceView selection |
| accent as text | `#FF9F0A` | `#AD6500` | GTK `accent_color` (accent labels, focus rings); the light value is darkened to 4.5:1 on white |
| `linkColor` | `#419CFF` | `#0068DA` | links stay blue, as macOS keeps `linkColor` blue with every accent |

Apple has not published the orange variants of `selectedContentBackgroundColor` and `selectedTextBackgroundColor`, so they
are derived from the published blue pair. With the blue accent `selectedContentBackgroundColor` is the accent at full saturation
with the brightness scaled to 0.816 (dark) and 0.882 (light) and the hue moved 4.5 and 2.3 degrees deeper; the orange values
apply the same scaling and move the hue towards red. `selectedTextBackgroundColor` is 30 % of the accent over `#565559` (dark)
or white (light), which reproduces `#3F638B` and `#B3D7FF` for blue. White text on the accent measures 2.1:1 and on the
selection 3.5:1 (dark) and 3.0:1 (light); Apple draws white text on orange, so KwickOS does too.

Settings > Appearance can pick blue, purple, pink, red, orange, yellow, green or graphite (Apple's dark and light system
colours). The choice is stored in `~/.config/kwick/accent` (`kwick-layout accent NAME`, `default` to follow the layout) and
applies to every layout and desktop; without a choice the macOS layout uses orange and the Windows and Linux layouts keep
`#0078D4` and the Tokyo Night blue.

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
