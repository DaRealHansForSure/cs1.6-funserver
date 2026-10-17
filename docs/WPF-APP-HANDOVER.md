# Handover: CS 1.6 Server Control (WPF app with HelixToolkit)

This document is the complete and only specification for a Windows desktop
app that controls the CS 1.6 LAN fun server and shows the running game live
on a 3D wireframe of the map. It describes the app exactly as designed in the
approved mockups. Build it from this document alone.

> **Authority:** This spec wins over any existing code in the repository.
> Do not adapt it to an older GUI or reuse older code unless it already
> matches this spec exactly. If something here is impossible, stop and ask
> the owner instead of improvising a different design.

### Mockup screenshots

Screenshots of the mockups are in `docs/mockups/`. Look at them before
building each screen and compare the running app against them when done.
The text in sections 5 to 9 is the exact spec; the pictures show the
intended result.

| Screen | File |
| --- | --- |
| Live-Karte | `docs/mockups/1-wpf-live-karte.png` |
| Server | `docs/mockups/2-wpf-server.png` |
| Bots | `docs/mockups/3-wpf-bots.png` |
| Browser viewer (earlier idea, **not** part of this app) | `docs/mockups/4-web-viewer.png` |

Notes on the screenshots:

- They were rendered on Linux, where Segoe UI and Cascadia Mono do not
  exist, so the fonts are substitutes. Use the fonts from section 5.2.
- The 3D view in the mockup is a simple stand-in arena drawn with flat
  lines and buttons. The real app draws the actual `.bsp` geometry with
  HelixToolkit, and the ViewCube and axes are Helix's own controls.
- Names, numbers, console lines and bots are example data.

---

## 1. Goal and scope

One WPF window named **"CS 1.6 Server Control"** with a left navigation rail
and three working screens:

| Screen | Purpose |
| --- | --- |
| **Live-Karte** | HelixToolkit 3D wireframe of the current map with all players live on it, a player list, a player detail card and a kill feed. |
| **Server** | Start/stop the server, switch game mode, pick and change maps, server console with RCON command input. |
| **Bots** | All zBot settings, nav file status per map, list of active bots. |

Two more rail entries, **Maps** and **Optionen**, exist but are disabled
(future work).

Out of scope: anything not shown in the mockups, internet play, running the
app on a PC other than the server PC.

---

## 2. Hard rules

- **Owner preferences, always:**
  - Never use em dashes or en dashes anywhere (code, comments, UI, docs).
    Use a normal hyphen `-`.
  - Code reads like a careful human senior engineer wrote it: descriptive
    names, early returns, braces on every block (K&R), four-space indent,
    no nested ternaries, "why" comments only.
- **UI language is German**, exactly the strings given in this document,
  umlauts included (WPF handles Unicode). Code, comments and docs are English.
- **Windows only.** The app runs on the same PC as the server.
- **MVVM**: no logic in code-behind except pure view concerns (camera
  plumbing for Helix is allowed in a dedicated view helper).
- **Every visual value comes from the design tokens in section 5.** No
  hard-coded colors or sizes in views.

---

## 3. Architecture

```
 hlds.exe (ReHLDS + ReGameDLL + AMX Mod X)
   |  fun_livemap.amxx  --UDP 127.0.0.1:27090, 5x per second-->  LiveFeedListener
   |  -condebug writes cstrike\qconsole.log  ------------------>  ConsoleLogTail
   |  RCON over UDP 27015  <---------------------------------->  RconClient
   |
 server\cstrike\maps\*.bsp  -------------------------------->  BspWireframeLoader
 server\cstrike\maps\*.nav, mapcycle_*.txt, BotProfile.db  -->  file readers

 CS 1.6 Server Control (WPF, .NET, MVVM)
   Shell: title bar + nav rail + status bar
   Screens: LiveMapView (Helix Viewport3DX) | ServerView | BotsView
```

Data flow rules:

- **Live positions** only come from the UDP feed (section 10). If no packet
  arrived for 3 seconds, the Live-Karte shows the map without players and the
  status bar shows `Keine Live-Daten`.
- **Commands** (mode, map, kick, slay, bots) always go through RCON.
- **Console output** comes from tailing `qconsole.log`, because on Windows
  `hlds.exe -console` opens its own console window and its output cannot be
  captured through stdout.

---

## 4. Tech stack and project layout

- **.NET**: the newest LTS SDK installed on the PC (`net10.0-windows`,
  fall back to `net8.0-windows`), `<UseWPF>true</UseWPF>`, nullable enabled.
- **NuGet:**
  - `HelixToolkit.Wpf.SharpDX` (latest stable 2.x). DirectX 11 rendering;
    plain WPF `Viewport3D` is too slow for the tens of thousands of edges in
    a map.
  - `CommunityToolkit.Mvvm` for `ObservableObject`, `RelayCommand`.
  - Test project: xUnit.
- **Build output**: a single-file, self-contained `CsServerControl.exe`
  published to the repository root as `4_SERVER_CONTROL.exe`, via a script
  `tools\build-app.ps1`.

```
app\
  CsServerControl\
    CsServerControl.csproj
    App.xaml, App.xaml.cs
    Shell\        MainWindow.xaml(.cs), ShellViewModel.cs, NavRail.xaml
    Theme\        Tokens.xaml, Controls.xaml (button, card, input styles)
    LiveMap\      LiveMapView.xaml(.cs), LiveMapViewModel.cs,
                  WireframeScene.cs, PlayerSceneBuilder.cs, CameraRig.cs
    Server\       ServerView.xaml(.cs), ServerViewModel.cs
    Bots\         BotsView.xaml(.cs), BotsViewModel.cs
    Services\     RconClient.cs, ServerProcess.cs, ConsoleLogTail.cs,
                  LiveFeedListener.cs, LiveFeedParser.cs,
                  BspWireframeLoader.cs, MapCycleReader.cs,
                  NavFileScanner.cs, BotProfileReader.cs,
                  BotConfigWriter.cs, AppSettings.cs, PackagePaths.cs
  CsServerControl.Tests\
    LiveFeedParserTests.cs, RconResponseTests.cs, BspWireframeLoaderTests.cs,
    BotConfigWriterTests.cs, BotProfileReaderTests.cs
server-files\cstrike\addons\amxmodx\scripting\fun_livemap.sma   (new)
server-files\cstrike\addons\amxmodx\scripting\fun_hook.sma       (one native added)
tools\build-app.ps1                                               (new)
```

`PackagePaths` finds the package root by walking up from the exe until it
finds a folder that contains both `server\` and `tools\`.

---

## 5. Design system

Dark Windows 11 look with a teal accent. Put every value below into
`Theme\Tokens.xaml` as named resources and use only those.

### 5.1 Colors

| Token | Hex | Used for |
| --- | --- | --- |
| `WindowBackground` | `#1C1C1C` | window, title bar, page background |
| `RailBackground` | `#202020` | nav rail, status bar |
| `DividerSubtle` | `#2B2B2B` | title bar bottom border, status bar top border |
| `CardBackground` | `#2B2B2B` | cards, toolbar |
| `CardBorder` | `#3A3A3A` | card and toolbar border, list dividers |
| `ControlBackground` | `#323232` | secondary buttons, mode tiles (not picked) |
| `ControlBorder` | `#4A4A4A` | secondary buttons, inputs |
| `InputBackground` | `#1F1F1F` | text, number and select inputs, segmented control track |
| `SelectedRow` | `#3A3A3A` | selected player row, picked map row |
| `NavActive` | `#2D2D2D` | active rail item background |
| `ViewportBackground` | `#0F1316` | 3D viewport, console background |
| `ConsoleBorder` | `#333333` | console border, table row dividers |
| `TextPrimary` | `#F3F3F3` | main text |
| `TextSecondary` | `#C8C8C8` | rail labels, input labels, status bar |
| `TextTertiary` | `#A8A8A8` | hints, metadata, column headers |
| `TextDisabled` | `#8A8A8A` | disabled rail items |
| `Accent` | `#5ED3C0` | primary buttons, active toggles, rail pill, focus ring |
| `AccentHover` | `#9BE7DA` | accent hover |
| `OnAccent` | `#0F1316` | text on accent |
| `AccentTint` | `#23332F` | picked mode tile background |
| `TeamT` | `#E8A13A` | Terrorists |
| `TeamCT` | `#4EA3F0` | Counter-Terrorists |
| `Hook` | `#FF5BD1` | hook beam |
| `Warning` | `#F2C66B` | "Ungespeicherte Änderungen", "Humiliation!", missing nav, kill lines |
| `SuccessDot` | `#57AB5A` | running status dot |
| `SuccessPillBackground` | `#1E3323` | running status pill |
| `SuccessPillText` | `#A6E3AE` | running status pill text, "Vorhanden" |
| `DangerBorder` | `#8C3B3B` | Stoppen button |
| `DangerBackground` | `#3A2222` | Stoppen button |
| `DangerText` | `#FFB4B4` | Stoppen button |
| `WireGrid` | `#26403C` | floor grid lines |
| `WireLow` | `#3F7C72` | map edges at the lowest height |
| `WireHigh` | `#8FE0CF` | map edges at the highest height; plugin console lines |
| `DeadMarker` | `#8A949C` | × for dead players |
| `AxisX` / `AxisY` / `AxisZ` | `#E5534B` / `#57AB5A` / `#539BF5` | coordinate system |

### 5.2 Typography

- UI font: `Segoe UI Variable Text, Segoe UI`.
- Mono font: `Cascadia Mono, Consolas` (camera info, positions, map names,
  console, cvar names, quick commands).

| Style | Size | Weight |
| --- | --- | --- |
| Page title (`Server`, `Bots`) | 28 | SemiBold |
| Card title (Server, Bots screens) | 16 | SemiBold |
| Card title (Live-Karte side panel) | 14 | SemiBold |
| Map title in viewport | 18 | SemiBold |
| Body, buttons | 14 (toolbar buttons 13) | Regular |
| Small, status bar, labels | 12 | Regular |
| Caption, rail labels, 3D labels | 11 | Regular |

### 5.3 Shapes, spacing, components

- Corner radius: buttons and inputs 4, cards 8 (Live-Karte cards and
  viewport 6), rail items 6, pills 12, quick command chips 16.
- Spacing: Server and Bots pages padding 20 top/bottom, 24 left/right,
  gap 16 between cards, card padding 16. Live-Karte page padding 16/20,
  gap 12, side cards padding 12 to 14.
- **Primary button**: height 36, padding 0 16, `Accent` background,
  `OnAccent` text, SemiBold, no border.
- **Secondary button**: height 36, padding 0 16, `ControlBackground`,
  1px `ControlBorder`, `TextPrimary`.
- **Danger button** (Stoppen): `DangerBackground`, 1px `DangerBorder`,
  `DangerText`.
- **Toolbar button**: height 36, padding 0 12, transparent, 13px.
- **Toggle button**: on = `Accent` background with `OnAccent` text; off =
  transparent (toolbar) or `ControlBackground` (cards) with `TextPrimary`.
  Expose state as `IsChecked` for accessibility.
- **Text input**: height 36, `InputBackground`, 1px `ControlBorder`, the RCON
  field additionally has a 2px `Accent` bottom border.
- **Focus**: every focusable control shows a 2px `Accent` focus rectangle
  with 2px offset. Full keyboard navigation with Tab must work.
- Minimum window size 1100 × 700, default 1440 × 900.

---

## 6. App shell

### 6.1 Title bar (custom, `WindowChrome`)

- Height 36, `WindowBackground`, 1px `DividerSubtle` bottom border.
- Left, 14px padding: app icon (16px crosshair: circle r=8 plus four short
  lines, stroke `Accent`, 2px) then `CS 1.6 Server Control` in 12px
  `TextSecondary`, gap 10.
- Right: the three standard caption buttons (minimize, maximize/restore,
  close), each 46 wide, glyphs in `TextSecondary`. They must work and
  support Windows snap layouts.

### 6.2 Navigation rail

- Width 80, `RailBackground`, padding 8 vertical / 6 horizontal, gap 4.
- Items, top to bottom: **Live-Karte** (cube icon), **Server** (two stacked
  server boxes), **Bots** (robot head), **Maps** (stacked layers, disabled),
  spacer, **Optionen** (gear, disabled, pinned to the bottom).
- Each item: min height 56, radius 6, icon 20px (stroke icons, 1.6 stroke),
  label 11px below the icon, gap 4.
- States: active = `NavActive` background, `TextPrimary`, plus a 3 × 18
  accent pill (radius 2) on the left edge, vertically centered on the icon;
  inactive = transparent, `TextSecondary`; disabled = `TextDisabled`, not
  clickable, tooltip `Kommt später`.
- Start screen: **Live-Karte**.

### 6.3 Status bar

- Min height 28, `RailBackground`, 1px `DividerSubtle` top border, padding
  4 / 14, 12px `TextSecondary`, items separated by 18px gaps, a flexible
  spacer, then right-aligned items in `TextTertiary`.
- Content depends on the screen (see each screen). Always first:
  green 8px dot + `Server läuft`, or grey dot (`TextDisabled`) +
  `Server gestoppt`.

---

## 7. Screen: Live-Karte

Layout top to bottom: toolbar, then a row with the viewport (flexible,
min width 560) and the side panel (300 to 360 wide). Gap 12.

### 7.1 Toolbar

Card style (`CardBackground`, 1px `CardBorder`, radius 6, padding 6,
gap 6), buttons in this order:

1. `↺ Drehen` (rotate camera 15° left around the map center)
2. `Drehen ↻` (15° right)
3. `Steiler` (pitch +10°, max 90°)
4. `Flacher` (pitch -10°, min 10°)
5. `+` and `-` (zoom ±0.2, range 0.6 to 2.5 of the "fit" distance),
   accessible names `Hineinzoomen` / `Herauszoomen`
6. 1px × 22 divider
7. Toggle pair `3D` / `Draufsicht` (exactly one is on)
8. divider
9. Toggles `Namen` (default on) and `Laufwege` (default on)
10. flexible spacer, then the camera mode label in 12px `TextTertiary`:
    `Kamera: frei` or `Kamera folgt: <Name>`

Mouse in the viewport also works (Helix defaults: right drag rotate,
middle drag pan, wheel zoom). Toolbar actions animate the camera over
200 ms.

### 7.2 Viewport (Helix `Viewport3DX`)

- Container: `ViewportBackground`, 1px `CardBorder`, radius 6, height fills
  the available space (min 640).
- `EffectsManager = new DefaultEffectsManager()`, perspective camera,
  **Z is up** (`ModelUpDirection="0,0,1"`, camera `UpDirection` 0,0,1),
  because GoldSrc uses Z as up.
- **Default camera** ("3D"): looks at the map's bounding box center from
  yaw 35°, pitch 50°, at the distance that fits the whole map.
  **Draufsicht**: pitch 90°, yaw 0, look direction (0,0,-1), up direction
  (0,1,0) to avoid the gimbal flip.
- **Helix overlays:**
  - `ShowViewCube = true`, bottom right.
  - `ShowCoordinateSystem = true`, bottom left (X red, Y green, Z blue,
    the token colors).
  - Turn off Helix's own camera info and frame rate texts; draw the
    custom overlays below instead.
  - If the ViewCube faces can be relabelled, use `OBEN`, `VORNE`, `RECHTS`,
    and the other three `UNTEN`, `HINTEN`, `LINKS`. If Helix does not
    allow that, keep its defaults (an accepted deviation).
- **Custom WPF overlays** on top of the viewport:
  - Top left, 14/12 offset: map name 18px SemiBold (e.g. `fy_iceworld`),
    below it 12px `TextTertiary`:
    `<Modus> · Runde <m:ss> · <n> / <max> Spieler`
    (e.g. `Classic Fun · Runde 1:42 · 7 / 20 Spieler`; when the round has no
    time limit show `Runde -`).
  - Top right, 14/12 offset, right aligned, 11px mono `TextTertiary`:
    `Position x, y, z` · `Blick x, y, z` (two decimals) · `Oben 0, 0, 1` ·
    `60 FPS` (live frame rate, in `Accent`).

### 7.3 Map wireframe

Loaded with `BspWireframeLoader` (section 11) whenever the map changes.

- One `LineGeometryModel3D` for all map edges, thickness 1, per-vertex
  colors: lerp from `WireLow` at the map's lowest Z to `WireHigh` at the
  highest Z, so height reads in a pure wireframe.
- Distance fade: lines further from the camera get dimmer, from 100%
  opacity near to 35% far (use Helix fog or a per-frame alpha update,
  whichever performs at 60 FPS).
- One more `LineGeometryModel3D` for a floor grid on the lowest floor
  level: 256-unit spacing over the map bounds, `WireGrid`, 80% opacity.
- Show only world geometry (BSP model 0). Doors, lifts and breakables stay
  in their start position (known limitation).

### 7.4 Players in 3D

From the live feed (section 10). GoldSrc player origin is the center of the
hull: feet at `z - 36`, head marker at `z + 28` (standing).

- **Alive player:** sphere radius 10 units at the head position in the team
  color, with a soft glow (emissive material), plus:
  - a vertical line from feet to head, team color, 60% opacity, thickness 1;
  - a view direction line from the head, 140 units along the player's yaw,
    team color, thickness 2, 95% opacity;
  - **name label** (when `Namen` is on): `BillboardTextModel3D`, 11px,
    `TextPrimary` on a 80% `ViewportBackground` box, offset up-right of the
    marker.
- **Selected player:** additional white ring around the marker
  (a slightly larger white sphere at 35% opacity or a camera-facing circle).
- **Trails** (when `Laufwege` is on): the last 2 seconds of positions,
  sampled every 0.4 s, as a line strip in team color, thickness 2, 30%
  opacity.
- **Hook:** when a player hooks, a line from their head to the hook point in
  `Hook` color, thickness 2, plus a second line thickness 6 at 30% opacity
  for the glow.
- **Dead player:** a gray × (two crossing 24-unit lines, `DeadMarker`) at the
  feet position where they died, until they respawn or the round ends. No
  label.
- Positions are interpolated between packets (linear over 200 ms) so markers
  move smoothly.

### 7.5 Side panel

Three cards, gap 12.

**Card "Spieler"** (title 14px SemiBold):

- One row per player, all teams, Terrorists first, then CT, then
  spectators; within a team by score descending.
- Row: full-width button, height 34, radius 4, padding 0 8, grid columns
  `10px | * | 52px | 44px`, gap 8, 13px:
  team color dot (10px circle) · name plus ` BOT` tag in 11px
  `TextTertiary` · `<hp> HP` or `tot` (right aligned, `TextSecondary`) ·
  `<frags>/<deaths>` (right aligned, `TextTertiary`).
- Dead players at 55% opacity. Selected row background `SelectedRow`.
- Clicking a row selects the player (also highlights them in 3D). Clicking a
  marker in 3D selects too.

**Card: selected player** (padding 14, gap 10):

- Header row: name 16px SemiBold in team color, right side 12px
  `TextTertiary`: `Terroristen` or `Counter-Terroristen`, plus ` · Bot` for
  bots.
- HP bar: 6px high, radius 3, track `CardBorder`, fill team color, width =
  HP percent.
- Two-column grid, 12px, labels in `TextTertiary`:
  `Leben` → `<hp> HP`, `Waffe` → weapon display name (e.g. `AK-47`, `-` when
  dead), `Position` → `x, y, z` in mono.
- Buttons: toggle `Kamera folgen`, secondary `Slay`, secondary `Kick`.
  - Kamera folgen: camera keeps its current angle and distance and moves its
    target smoothly with the player. Any manual camera action or deselect
    turns it off.
  - Slay: RCON `amx_slay #<userid>`.
  - Kick: confirmation dialog `<Name> wirklich kicken?` then RCON
    `kick #<userid>`.
- Default selection: first alive human player; none if nobody is on the
  server (then the card shows `Kein Spieler ausgewählt`).

**Card "Killfeed"** (12px, gap 6): newest on top, last 6 kills, each fades
out after 30 s. Format:
`<Killer in team color> [<Waffe>] <Opfer in team color>`, with
`[<Waffe>, Headshot]` for headshots and ` Humiliation!` in `Warning` color
after knife kills.

### 7.6 Status bar for this screen

`Server läuft` · `192.168.1.50:27015` (the real LAN address) ·
`UDP <n> Pakete/s` (measured) · `Ohne Verzögerung, nur auf diesem PC` ·
spacer · `HelixToolkit.Wpf.SharpDX`.
When no feed: replace the UDP item with `Keine Live-Daten`.

---

## 8. Screen: Server

Header row, then two columns (left min 420, right min 460, gap 16).

### 8.1 Header

- Left: `Server` (28px SemiBold), then the status pill: 12px radius, padding
  4/12, 13px: running = `SuccessPillBackground` with green dot and
  `Läuft seit hh:mm:ss` in `SuccessPillText` (live uptime); stopped =
  `ControlBackground`, grey dot, `Gestoppt`.
- Right: secondary `Neu starten` (stop, wait for exit, start), then
  `Stoppen` (danger style) or, when stopped, `Starten` (primary style).

### 8.2 Card "Modus"

- Grid 2 × 2 of mode tiles, gap 10. Tile: min height 76, padding 12, radius 6,
  left aligned: title 15px SemiBold, description 12px `TextTertiary`.

| id | Title | Description |
| --- | --- | --- |
| `classic` | Classic Fun | Hook, Grab, Fallschirm, Bunnyhop |
| `gungame` | GunGame | 24 Waffenstufen, jeder gegen jeden |
| `zombie` | Zombie | Menschen gegen Zombies, Infektion |
| `deathmatch` | Deathmatch | Sofort-Respawn, zufällige Waffen |

- Picked tile: 1px `Accent` border, `AccentTint` background. Others:
  1px `CardBorder`, `ControlBackground`.
- The currently running mode shows a chip `Aktiv` next to its title (11px
  SemiBold, `Accent` background, `OnAccent` text, radius 10, padding 1/8).
- Picking a tile only changes the selection and the map list below.
- Below: primary `Modus wechseln` plus hint 12px `TextTertiary`:
  `Sendet amx_modus und wechselt nach 5 s auf eine passende Map.`
  Action: RCON `amx_modus <id>`, then append the echo lines to the console.

### 8.3 Card "Maps für <Modustitel>"

- Header: title left, right 12px `TextTertiary`:
  `Jetzt: <current map> · Nächste: <amx_nextmap value>`.
- Radio list, 2 columns, gap 4/12: each row min height 36, radius 4, radio
  (accent colored) + map name in 13px mono; picked row `SelectedRow`.
  Maps come from `server\cstrike\mapcycle_<picked mode>.txt`, in file order.
  When the picked mode changes, the first map is picked.
- Buttons (secondary): `Map jetzt wechseln` → RCON `changelevel <map>`;
  `Als nächste Map setzen` → RCON `amx_nextmap <map>`.

### 8.4 Card "Konsole"

- Header: `Konsole` left, right 12px `TextTertiary`:
  `hlds.exe · <ip>:<port>`.
- Log area: height 470 (grows with the window), `ViewportBackground`, 1px
  `ConsoleBorder`, radius 4, padding 10/12, 12px mono, line height 1.6,
  wraps long lines, auto-scrolls to the bottom unless the user scrolled up.
  Keeps the last 2000 lines.
- Line colors:
  - lines with `[` + plugin name `.amxx]` or starting with `[Fun]` → `WireHigh`;
  - lines containing `" killed "` → `Warning`;
  - commands sent by the app, shown as `] <command>` → `TextPrimary`;
  - everything else → `TextTertiary`.
- Below: label `RCON-Befehl` (12px `TextSecondary`), input with placeholder
  `z. B. amx_rocket Ulf`, primary `Senden`. Enter sends. After sending, the
  input clears, `] <command>` is appended, and the RCON reply lines follow.
  Up/Down arrows browse the command history.
- Quick command chips below (height 32, radius 16, mono 12px, secondary
  style): `amx_modus gungame`, `bot_kick`, `sv_restart 1`,
  `amx_glow @ALL pink`. Clicking sends the command.

### 8.5 Status bar for this screen

`Server läuft` · `<n> / <max> Spieler · <b> Bots` · `Fast-Download auf Port 27080`
· spacer · `RCON verbunden` (or `RCON getrennt`).

---

## 9. Screen: Bots

Header row, then two columns (left min 440, right min 420, gap 16).

### 9.1 Header

- Left: `Bots` (28px SemiBold), pill `zBot aus ReGameDLL`
  (`ControlBackground`, `TextSecondary`), then 13px `TextTertiary`:
  `<n> Bots aktiv · füllen auf <quota> Spieler auf`.
- Right: when there are unsaved changes, 12px `Warning` text
  `Ungespeicherte Änderungen`; secondary `Bots neu verbinden`; primary
  `Übernehmen`.

### 9.2 Left column cards

**Card "Schwierigkeit":** segmented control, 4 equal buttons in a track
(`InputBackground`, padding 4, gap 4, radius 6), each 40 high, 14px
SemiBold: `Leicht`, `Normal`, `Schwer`, `Experte` → `bot_difficulty`
0, 1, 2, 3. Picked = `Accent` background, `OnAccent` text. Below, 13px
`TextTertiary` hint for the picked level:

| Level | Hint |
| --- | --- |
| Leicht | Reagieren langsam, zielen ungenau. Gut für Einsteiger. |
| Normal | Solide Gegner, die aber Fehler machen. |
| Schwer | Treffen gut und spielen als Team. Für geübte Runden. |
| Experte | Sehr schnelle Reaktion und präzises Zielen. Nur für Profis. |

Default: Schwer.

**Card "Anzahl und Teams":** three inputs in a 3-column grid:

| Label | Control | cvar |
| --- | --- | --- |
| `Spieler auffüllen auf` | number 0 to 20, default 8 | `bot_quota` |
| `Verhalten` | select: `Auffüllen` (fill), `Feste Anzahl` (normal), `Pro Spieler` (match), default fill | `bot_quota_mode` |
| `Team der Bots` | select: `Beide Teams` (any), `Nur CT` (ct), `Nur T` (t), default any | `bot_join_team` |

Then three checkboxes (18px, accent), each with the cvar name in 12px mono
`TextTertiary` after the text:

| Text | cvar | Default |
| --- | --- | --- |
| Bots machen Platz für echte Spieler | `bot_auto_vacate` | on |
| Nur kämpfen, keine Bombe oder Geiseln | `bot_deathmatch` | off |
| Spieler übernehmen die Missionsziele | `bot_defer_to_human` | on |

**Card "Waffen der Bots":** 2-column checkbox grid:

| Text | cvar | Default |
| --- | --- | --- |
| Pistolen | `bot_allow_pistols` | on |
| Schrotflinten | `bot_allow_shotguns` | on |
| Maschinenpistolen | `bot_allow_sub_machine_guns` | on |
| Sturmgewehre | `bot_allow_rifles` | on |
| Scharfschützengewehre | `bot_allow_snipers` | off |
| Maschinengewehre | `bot_allow_machine_guns` | off |
| Granaten | `bot_allow_grenades` | on |
| Schild | `bot_allow_shield` | off |

Then `Funk und Chat` select (max width 260): `Normal (Sprachansagen)`
(normal), `Nur Funkbefehle` (radio), `Minimal` (minimal), `Aus` (off) →
`bot_chatter`.

All cvar names above are verified against ReGameDLL's source
(`regamedll/dlls/bot/cs_bot_init.cpp`).

### 9.3 Right column cards

**Card "Navigation pro Map":** header right: 12px `TextTertiary`
`zBot erzeugt fehlende Dateien beim ersten Laden`. Table columns
`Map | Status (150) | Aktion (120)`, header row 12px `TextTertiary` with a
1px `CardBorder` line; rows min height 40 with 1px `ConsoleBorder` lines.

- Rows: every map in all `mapcycle_*.txt` files, unique, sorted.
- Status (icon + text, never color alone):
  - `✓ Vorhanden` in `SuccessPillText` when `maps\<map>.nav` exists;
  - `! Fehlt` in `Warning` when it does not;
  - `◔ Wird erzeugt <p> %` in `WireHigh` with a 4px progress bar while the
    current map's nav is being generated. If no percentage can be read from
    the console log, show `◔ Wird erzeugt` with an indeterminate bar.
- Action button (secondary, height 32, 12px): `Neu erzeugen` (exists),
  `Erzeugen` (missing), `Läuft...` (disabled while building).
  - For the **current map**: RCON `bot_nav_analyze`.
  - For another map: confirmation `Dafür wird auf <map> gewechselt. Fortfahren?`,
    then RCON `changelevel <map>`; zBot generates the missing nav on load.
    For "Neu erzeugen" on another map, delete the `.nav` file first, then
    change level.
- Rescan the folder every 5 s and after map changes.

**Card "Aktive Bots":** rows min height 40, grid `10px | * | 90px | 70px`:
team dot · name + team name in 12px `TextTertiary` · `Skill <n>` (12px
`TextSecondary`, from `BotProfile.db`, `-` if unknown) · secondary `Kick`
(RCON `bot_kick "<name>"`). Empty state: `Keine Bots auf dem Server.`

### 9.4 Applying settings

- Any change marks the page dirty (`Ungespeicherte Änderungen`).
- `Übernehmen`:
  1. writes all bot cvars into a managed block in
     `server\cstrike\modes\base.cfg` **and** in
     `server-files\cstrike\modes\base.cfg` (so a reinstall keeps them),
     between the lines `// --- Bots (Server Control) ---` and
     `// --- Ende Bots ---`, replacing the old block or appending it;
  2. sends every cvar via RCON so it applies immediately;
  3. clears the dirty flag.
- `Bots neu verbinden`: RCON `bot_kick`, then `bot_quota <quota>`, so all bots
  rejoin with the new difficulty (`bot_difficulty` only affects new bots).
- Footer for this screen: `Server läuft` · `Schwierigkeit: <Stufe>` · spacer ·
  `Gespeichert in modes\base.cfg`.

---

## 10. Server side: live feed plugin

### 10.1 `fun_hook.sma`: expose the hook point

Add a native, registered in `plugin_natives()` with `register_library("fun_hook")`:

```
native bool:fun_hook_get_point(playerId, Float:point[3]);
```

Returns true and fills `point` while the player is hooking.

### 10.2 `fun_livemap.sma` (new plugin)

- Includes `amxmodx`, `fakemeta`, `sockets`. Add to `plugins.ini` after the
  other fun plugins. Use `fun_hook_get_point` through
  `#pragma reqlib fun_hook` / optional native filter so the plugin still
  works if the hook plugin is missing.
- Cvars: `fun_livemap_target "127.0.0.1"`, `fun_livemap_port "27090"`,
  `fun_livemap_interval "0.2"`.
- Opens one UDP socket at `plugin_cfg` (`socket_open(host, port, SOCKET_UDP, error)`)
  and sends one snapshot every interval with `socket_send2`.
- Sends a kill event immediately on `DeathMsg`.
- Tracks round start with `register_logevent(..., "1=Round_Start")` to
  compute the remaining round time from `mp_roundtime`; `-1` when
  `mp_round_infinite` is set or before the first round start.

### 10.3 Packet format (UTF-8 text, lines separated by `\n`)

Snapshot:

```
CSLIVE1|S|<map>|<mode>|<roundSecondsLeft>|<maxPlayers>
P|<userid>|<name>|<team>|<alive>|<bot>|<hp>|<x>|<y>|<z>|<yaw>|<frags>|<deaths>|<weapon>|<hooking>|<hx>|<hy>|<hz>
P|...
```

Kill event (separate packet):

```
CSLIVE1|K|<killerUserid>|<victimUserid>|<weapon>|<headshot>
```

- `team`: `T`, `CT` or `SPEC`. `alive`, `bot`, `hooking`, `headshot`: `0`/`1`.
- Coordinates as integers, `yaw` in degrees as integer.
- `weapon`: the internal name without `weapon_` (e.g. `ak47`, `knife`). The
  app maps names to display names (`ak47` → `AK-47`, `knife` → `Messer`,
  `awp` → `AWP`, `deagle` → `Desert Eagle`, `m4a1` → `M4A1`, `mp5navy` → `MP5`,
  `famas` → `Famas`, unknown → upper case).
- `mode`: the `fun_mode` localinfo value (`classic`, `gungame`, `zombie`,
  `deathmatch`).
- Names: replace `|` and newline with `/` before sending.
- Buffer: 4096 bytes is enough for 32 players.

`LiveFeedParser` must reject packets without the `CSLIVE1|` prefix and must
never throw on malformed lines (skip the line, count it).

---

## 11. BSP wireframe loader

GoldSrc maps are BSP version 30, little endian.

- Header: `int32 version` (must be 30), then 15 lumps as
  `(int32 offset, int32 length)`, in this order:
  0 entities, 1 planes, 2 textures, 3 vertices, 4 visibility, 5 nodes,
  6 texinfo, 7 faces, 8 lighting, 9 clipnodes, 10 leaves,
  11 marksurfaces, 12 edges, 13 surfedges, 14 models.
- Vertices: `float x, y, z` (12 bytes).
- Edges: `uint16 v0, uint16 v1` (4 bytes).
- Surfedges: `int32`; a negative value means edge `-value` reversed.
- Faces (20 bytes): `uint16 plane, uint16 side, int32 firstEdge,
  uint16 edgeCount, uint16 texInfo, byte styles[4], int32 lightOffset`.
- Texinfo (40 bytes): `float vecs[2][4]`, `int32 mipTex`, `int32 flags`.
- Textures lump: `int32 count`, then `count` × `int32 offset` (relative to
  the lump start, `-1` = missing), each miptex starts with `char name[16]`.
- Models (64 bytes): `float mins[3], maxs[3], origin[3], int32 headNodes[4],
  int32 visLeafs, int32 firstFace, int32 faceCount`. **Model 0 is the world.**

Algorithm:

1. Read the faces of model 0 only.
2. Skip faces whose texture name (lower case) is `sky`, starts with
   `aaatrigger`, `clip`, `origin`, `null` or `bevel`.
3. For each remaining face, walk its surfedges and collect the edge index
   (absolute value) in a `HashSet<int>`, so shared edges are drawn once.
4. Output: a list of line segments (two `Vector3` each), plus the bounding
   box and min/max Z for the height colors.
5. Load on a background thread; the viewport shows `Lade Map...` meanwhile.
   Cache results per map name and file timestamp.

Validate with `de_dust2.bsp` from `server\cstrike\maps`: version 30,
non-empty edge set, bounding box roughly `-2500..2000` in X and Y.

---

## 12. Server process, RCON, console

### 12.1 ServerProcess

- Starts the fast download server:
  `powershell -NoProfile -ExecutionPolicy Bypass -File tools\fastdl-server.ps1 -Root "<server\cstrike>" -Port 27080`
  (minimized), and stops it when the server stops.
- Starts `server\hlds.exe` (working directory `server\`, minimized) with:
  `-console -condebug -game cstrike -port 27015 +ip <lanIp> +maxplayers 20
  +sv_lan 1 +localinfo fun_mode <mode> +mapcyclefile mapcycle_<mode>.txt
  +sv_downloadurl "http://<lanIp>:27080/" +rcon_password <password>
  +map <first map of the mode>`
- `<lanIp>`: IPv4 of the adapter that has a default gateway and is up;
  fallback first non-loopback, non-169.254 address.
- `<password>`: generated once (24 random URL-safe characters) and stored in
  `%APPDATA%\CsServerControl\settings.json`. Never shown in the UI.
- Stop: RCON `quit`, wait up to 10 s, then kill the process.
- If the app starts while `hlds.exe` from this package is already running,
  it attaches (RCON with the stored password) instead of starting a second
  one.
- Windows Firewall: on first start, if not already present, ask once to add
  inbound rules for UDP/TCP 27015 and TCP 27080 (needs elevation; use
  `netsh` via `runas`). Never open UDP 27090; the live feed stays on
  localhost.

### 12.2 RconClient (GoldSrc RCON over UDP)

1. Send `\xFF\xFF\xFF\xFFchallenge rcon\n`.
2. Reply `\xFF\xFF\xFF\xFFchallenge rcon <number>\n` → remember `<number>`.
3. Send `\xFF\xFF\xFF\xFFrcon <number> "<password>" <command>`.
4. Replies start with `\xFF\xFF\xFF\xFF` followed by `l`; collect packets for
   150 ms (multi-packet replies) and return the joined text.
5. On `Bad challenge` request a new challenge once and retry; on
   `Bad rcon_password` raise a clear error.
6. Timeout 2 s, all calls async, one call at a time (SemaphoreSlim).

### 12.3 ConsoleLogTail

Tails `server\cstrike\qconsole.log` (written because of `-condebug`): open
with `FileShare.ReadWrite`, read new bytes every 250 ms, split into lines,
handle truncation on server restart by starting from 0 again.

---

## 13. Switch the bots to zBot

The package currently uses YaPB. As part of this work:

- Download `regamedll/extra/zBot/bot_profiles.zip` from the ReGameDLL
  GitHub repository (same version tag as the installed ReGameDLL) in
  `tools\install.ps1` and extract it into `server\cstrike` (contains
  `BotProfile.db`, `BotChatter.db` and the radio sounds).
- Write `bot_enable 1` into `server\cstrike\game_init.cfg` (create the file).
- Remove the YaPB line from `addons\metamod\plugins.ini` and the YaPB
  install step; remove `yb_*` cvars from the mode configs and use the bot
  block from section 9.4 instead (`bot_quota`, `bot_quota_mode fill`,
  `bot_difficulty 2`, ...). GunGame and Deathmatch mode files additionally set
  `bot_deathmatch 1`; `base.cfg` resets it to 0.
- `BotProfileReader` parses `BotProfile.db`: `Default`/`Template`/named
  profiles, `Skill = <0-100>` lines, inheritance via `Template` names,
  so a bot name can be mapped to its skill.

---

## 14. Settings and persistence

`%APPDATA%\CsServerControl\settings.json`: RCON password, window size and
position, last selected screen, Live-Karte toggles (`Namen`, `Laufwege`).
Read with defaults when missing or broken; never crash on a bad file.

---

## 15. Milestones and acceptance criteria

Do them in order. Each milestone ends with a build, tests green, and the
listed checks done by running the app.

**M1 Shell and theme**
- Window with custom title bar, rail, status bar, three empty screens,
  disabled `Maps`/`Optionen`.
- All tokens from section 5 exist and are the only source of colors and
  sizes. Snap layouts, minimize, maximize, close work. Tab order sensible.

**M2 Server control**
- `ServerProcess`, `RconClient`, `ConsoleLogTail`, Server screen complete.
- Check: start server from the app, uptime pill counts, console shows the
  log, `status` via the input returns player list, mode switch changes map
  within 5 s and the `Aktiv` chip moves, map change and next map work,
  quick chips work, stop works, restart works.

**M3 Live feed**
- `fun_livemap.sma` and the `fun_hook` native, compiled by the installer
  like the other fun plugins. `LiveFeedListener` + parser with tests.
- Check: with 2 bots on the server, the app receives 5 packets/s and the
  status bar shows `UDP 5 Pakete/s`.

**M4 Live-Karte 3D**
- BSP loader with tests, wireframe, grid, Helix overlays, custom overlays,
  toolbar actions, mouse camera, players, labels, trails, hook beam, dead ×,
  side panel cards, follow camera, Slay/Kick.
- Check on `de_dust2` and `fy_iceworld`: map is recognizable, 60 FPS on the
  server PC, markers move smoothly, selecting a row highlights the marker,
  `Draufsicht` gives a clean top-down view, killfeed shows a knife kill with
  `Humiliation!`.

**M5 zBot and Bots screen**
- Section 13 installer changes, Bots screen complete, managed cfg block.
- Check: change difficulty to Experte, `Übernehmen`, `Bots neu verbinden`,
  new bots join; nav table shows correct states and `Erzeugen` on the
  current map creates the `.nav` file; kick a single bot works.

**M6 Packaging**
- `tools\build-app.ps1` publishes the single-file exe as
  `4_SERVER_CONTROL.exe` in the repository root. README section in German
  explaining the app in a few lines.

---

## 16. Testing and verification

- Unit tests (xUnit): `LiveFeedParser` (valid, malformed, names with odd
  characters), RCON reply parsing, `BspWireframeLoader` against a real map
  file from `server\cstrike\maps` (skip the test if the file is missing),
  `BotConfigWriter` (insert block, replace block, keep other lines),
  `BotProfileReader` (template inheritance).
- Manual checks as listed per milestone. For each screen, compare against
  the mockup description in sections 6 to 9 line by line before calling it
  done: texts, colors, order of elements, states.

---

## 17. Known limits and open questions

- Brush entities (doors, lifts, breakable glass) are static in the
  wireframe.
- Whether the Helix ViewCube can show German labels depends on the Helix
  version (section 7.2 allows the default labels).
- zBot nav generation progress may not be readable from the console log;
  the indeterminate bar is the accepted fallback.
- The live feed is only for the server PC. Showing it on a beamer for all
  players works like a wallhack; that is the owner's call, not the app's.
