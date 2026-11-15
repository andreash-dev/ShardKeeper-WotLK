# Changelog

## 1.1.0 — 2026-11-15

- Redesigned the settings window with a live shard count, target field and progress bar.
- Added automatic ElvUI styling alongside the standard WoW interface.
- Added target presets for 5, 10, 20 and 32 shards; typed targets save on Enter or closing the window.
- Added pause/resume controls that preserve the target and clean up existing excess when resumed.
- Added active/paused minimap icons and support for square minimaps.
- Limited new target settings to 0–32 to match the normal WotLK shard limit.
- Fixed excess deletions caused by overlapping loot and bag updates.
- Fixed cleanup stopping early when multiple shards arrive in quick succession.
- Added inventory confirmation, cursor and locked-slot safeguards.
- Updated installation instructions and provided a ready-to-install ZIP.

Tested in-game on Warmane during development, including rapid shard gains and pause/resume. Lua regression checks cover inventory timing, settings and minimap placement.

## 1.0.3

- Previous release: automatic shard cleanup, settings window and minimap controls.
