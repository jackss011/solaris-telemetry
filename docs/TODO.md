# TODOs

## Custom title bar (nice-to-have)
VS Code-style custom title bar instead of the default OS one. Not blocking anything, revisit
if there's spare time.
- `rl.SetConfigFlags({.WINDOW_UNDECORATED})` before `InitWindow`, draw our own bar
- drag: mouse-down in bar region -> `rl.SetWindowPosition` each frame from the delta
- min/max/restore/close: `rl.MinimizeWindow`/`MaximizeWindow`/`RestoreWindow`/`IsWindowMaximized`,
  close = break the main loop ourselves
- icons: Windows' own system icon font has these for free, pixel-identical to native chrome —
  `C:/Windows/Fonts/SegoeIcons.ttf` ("Segoe Fluent Icons", Win11), codepoints U+E921 minimize,
  U+E922 maximize, U+E923 restore, U+E8BB close (verified by rendering them). Win10 equivalent is
  `segmdl2.ttf` ("Segoe MDL2 Assets") with the same codepoints — fall back to it if the first
  load fails. Caveat: this is a system font, not something we bundle, so it won't be in
  `dist/solaris.zip` the way `assets/fonts/ShareTech/ShareTech-Regular.ttf` is — fine on Windows, but not
  portable if this ever targets Linux/macOS.

## Telemetry Database
Based on [Cosmos Telemetry v4](https://ballaerospace.github.io/cosmos-website/docs/v4/telemetry)
telemtry packet arrives as []u8
- timestamp it
- map it to a tlm_id (opaque)
- notify tlm_id on event_bus
- from tlm_id, into:
  - name, other base def
  - enumerate tlm_items