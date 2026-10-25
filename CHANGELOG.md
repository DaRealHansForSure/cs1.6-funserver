# Changelog

All notable changes to this project are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [2.1.0] - 2026-10-25

### Added

- Map market from GameBanana and map updates on the Maps screen.
- Weapon icons on the Live Map, map search on the Server screen.
- Game rules per mode, saved in `local_<mode>.cfg`.
- Deathrun gets its own mode tile.
- Open source README, changelog and MIT license.

### Changed

- Bot settings and game rules keep the package defaults; host changes go into
  `local*.cfg` files with a way back to the defaults.
- Bots may use the AWP by default, so the AWP fun round does not end in knife
  fights.
- Nav list sorted by state, then by name.
- Code style: K&R braces on every Pawn function, multi-line ternaries written
  as `if` statements.

### Fixed

- Leftover nav helper servers are stopped.
- Dropdowns open fast the first time.
- Publish works while the window or the server runs.
- Caret starts where the placeholder text starts.
- Console Follow stays off after a click, only a scroll changes it.

## [2.0.0] - 2026-10-17

### Added

- New Server Control app (WPF, .NET 10) with a live 3D map, zBot bots and
  right-click fun commands on players.
- Maps and Options screens, shot traces on the Live Map.
- Navigation meshes built in a hidden helper server on an invisible desktop.
- Test that every view loads.

### Changed

- **Breaking:** one exe replaces all PowerShell and batch scripts; install,
  start and map updates run from `4_SERVER_CONTROL.exe`.
- Bots on Normal difficulty by default.

### Fixed

- Failed nav builds, unloadable maps kept out of the rotation.
- The window not opening, the process ends when startup fails.
- Stop while a nav build runs.

## [1.1.0] - 2026-10-17

### Added

- The first Server Control window: mode switching, bots per mode, TV button,
  run times, map pictures and a Stats tab.
- Admin glow that stays across rounds.
- Random spawns all over the map in GunGame and Deathmatch.
- Juggernaut fun round and kill streak rewards.
- 14 community maps.

## [1.0.0] - 2026-10-16

### Added

- The LAN fun server package: installer, Classic, GunGame, Zombie and
  Deathmatch modes switchable by vote, hook, grab, parachute and the map pack.
- Fun menu, a random start map per mode.
- Fun rounds, Deathrun as a fifth mode, surf settings, Quake sounds and fast
  download.
- `local.cfg` with an RCON password for the Server Control window.

### Changed

- `amx_mode` renamed to `amx_funmode`, so it no longer clashes with the AMXX
  admin login cvar.

[2.1.0]: ../../compare/v2.0.0...v2.1.0
[2.0.0]: ../../compare/v1.1.0...v2.0.0
[1.1.0]: ../../compare/v1.0.0...v1.1.0
[1.0.0]: ../../releases/tag/v1.0.0
