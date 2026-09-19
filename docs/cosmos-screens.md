# COSMOS screen/widget definition language

This covers the one major piece of the COSMOS v4 stack the other three docs don't: the
**Telemetry Viewer** screen definition language. It's the most directly relevant reference for
Solaris's eventual raylib UI (the commented-out block at the bottom of `src/main.odin`), since
it's COSMOS's answer to "how do you declaratively describe a telemetry dashboard." Everything
below is v4 (sources at the bottom).

## File structure

A screen is one `.txt` file per screen, under `config/targets/TARGET/screens/`, referenced from
`config/tools/tlm_viewer/tlm_viewer.txt`. It opens with `SCREEN` and every layout container it
opens must be closed with a matching `END`.

**`SCREEN <width> <height> <polling-period> [FIXED]`**
`width`/`height` are pixels or `AUTO` (size to content). `polling-period` is seconds between
redraws (screens poll the server, they aren't pushed to — see "Lessons" doc for why this
matters). `FIXED` disables user resizing.

```
SCREEN AUTO AUTO 1.0 FIXED
VERTICAL
  LABEL "Battery status"
  LABELVALUE INST HEALTH_STATUS TEMP1 WITH_UNITS
  LIMITSBAR INST HEALTH_STATUS TEMP1
END
```

## Telemetry binding

Any telemetry-bound widget takes a `TARGET PACKET ITEM` mnemonic, plus an optional value-type
suffix that picks which stage of the read pipeline to display:

| Suffix | Meaning |
|---|---|
| `RAW` | unconverted bytes-as-number, pre-`READ_CONVERSION` |
| `CONVERTED` (default) | after `POLY_READ_CONVERSION`/`GENERIC_READ_CONVERSION`/etc. |
| `FORMATTED` | after `FORMAT_STRING` |
| `WITH_UNITS` | formatted + `UNITS` suffix appended |

This is a direct, visible expression of the `docs/cosmos-config-format.md` read pipeline —
raw → converted → formatted → with-units is the same ladder a widget picks a rung on.

## Layout containers

All close with `END`; they nest arbitrarily.

| Widget | Purpose |
|---|---|
| `VERTICAL` / `HORIZONTAL` | stack children, no border |
| `VERTICALBOX` / `HORIZONTALBOX` | same, with a titled border |
| `MATRIXBYCOLUMNS` | grid layout, fixed column count |
| `SCROLLWINDOW` | scrollable viewport around its child |
| `TABBOOK` / `TABITEM` | tabbed grouping |

## Value/telemetry widgets

| Widget | Purpose |
|---|---|
| `VALUE` | bare numeric/string display, colored by current limits state |
| `FORMATVALUE` | like `VALUE` but with an explicit printf-style format override |
| `LABELVALUE` / `LABELVALUEDESC` | label + value (+ description) pair |
| `LIMITSBAR` / `LIMITSCOLUMN` | horizontal/vertical red-yellow-green range gauge |
| `LABELVALUELIMITSBAR` / `VALUELIMITSBAR` | composite label+value+gauge |
| `TRENDBAR` / `LABELTRENDLIMITSBAR` | gauge plus recent-history marker |
| `RANGEBAR` / `RANGECOLUMN` | gauge with caller-supplied (non-limits) min/max |
| `PROGRESSBAR` / `LABELPROGRESSBAR` | percentage bar |
| `LIMITSCOLOR` | plain stoplight-style colored dot |
| `LINEGRAPH` | value vs. sample index | 
| `TIMEGRAPH` | value vs. wall-clock time |
| `ARRAY` | formatted display of an `ARRAY_ITEM` |
| `BLOCK` | raw hex dump of a `BLOCK`-typed item |

Everything in this table is a live, polling-driven read of one telemetry item's current value —
this is the direct analogue of the `Item`/`Packet` structures Solaris's parser needs to produce
so a future rendering loop has something to bind widgets to.

## Decoration and input widgets

Non-bound: `LABEL`, `TITLE`, `SECTIONHEADER`, `HORIZONTALLINE`, `SPACER`.

Input, which invoke inline Ruby (not telemetry-bound):

| Widget | Example |
|---|---|
| `BUTTON` | `BUTTON 'Start' 'cmd("INST COLLECT with TYPE NORMAL")'` |
| `TEXTFIELD` | width-in-characters, optional default text |
| `CHECKBUTTON` / `RADIOBUTTON` | boolean/exclusive-choice input |
| `COMBOBOX` | dropdown |
| `SCREENSHOTBUTTON` | dumps the screen to an image file |

`NAMED_WIDGET NAME WIDGET_TYPE ...params` tags any widget so later Ruby (e.g. inside a
`BUTTON`'s snippet) can reach it via `get_named_widget("NAME")` — this is COSMOS's escape hatch
for cross-widget interaction that the declarative layer alone can't express.

## Canvas (freeform positioning)

`CANVAS <width> <height>` ... `END` opens a pixel-positioned drawing surface, an alternative to
the box-layout model above, with widgets like `CANVASLABEL`, `CANVASLABELVALUE`, `CANVASLINE`,
`CANVASLINEVALUE` (line color driven by a telemetry item's limits state), `CANVASIMAGE`,
`CANVASIMAGEVALUE` (swap images based on a value), `CANVASDOT`. State-conditional canvas widgets
take comparisons (`VALUE_EQ`, `VALUE_GT`, `VALUE_GTEQ`, `VALUE_LT`, `VALUE_LTEQ`) and boolean
combinators (`TLM_AND`, `TLM_OR`) directly in their definition line, so simple
value-dependent visuals don't need a Ruby callback.

## Styling

- `SETTING <name> <value...>` / `SUBSETTING <index> <name> <value...>` — apply to one widget (or
  one sub-widget of a composite, addressed by index).
- `GLOBAL_SETTING WIDGET_CLASS <name> <value...>` / `GLOBAL_SUBSETTING WIDGET_CLASS <index> <name> <value...>`
  — apply to every widget of a class in the screen, so you don't repeat `SETTING` on each one.
- Common settings: `BACKCOLOR`, `TEXTCOLOR`, `BORDERCOLOR`, `WIDTH`, `HEIGHT`. Colors are either
  a name (`"red"`) or an `r g b` triplet (0-255 each).
- Value-widget-specific: `COLORBLIND` (pattern-based limits indication instead of color-only,
  an actual accessibility feature worth keeping), `ENABLE_AGING`/`GRAY_RATE`/`GRAY_TOLERANCE`/
  `MIN_GRAY` (gray out a value that hasn't changed recently — a cheap, effective "is this feed
  even alive" signal), `TREND_SECONDS` (history window for trend widgets).

## Tool-level config

Separate from any one screen: `config/tools/tlm_viewer/tlm_viewer.txt` controls what the
Telemetry Viewer app shows on launch — `AUTO_TARGETS`/`AUTO_TARGET` (auto-discover screens per
target), explicit `TARGET`/`SCREEN filename.txt [x y]` placement, `GROUP`/`GROUP_SCREEN` for
custom groupings that don't match the target/dir structure, `SHOW_ON_STARTUP`/
`ADD_SHOW_ON_STARTUP` for auto-opened screens, `NEW_COLUMN` for launch layout.

## Relevance to Solaris

The commented-out raylib loop in `src/main.odin` sketches exactly one thing this language
formalizes: a labeled value readout. The full language above suggests the shape a Solaris
"screen" concept could eventually take — a small set of composable primitives (containers +
bound value widgets + limits-driven coloring) driven by data, not hand-written per-panel Go/Odin
code. Two design choices worth *not* copying wholesale (see `cosmos-lessons.md` for the reasoning):
- Polling-period-per-screen (`SCREEN ... 1.0`) rather than push-on-change, which wastes CPU on
  static values and adds latency on fast-changing ones.
- Free-floating Ruby snippets embedded directly in `BUTTON`/canvas conditionals, which makes a
  screen file un-parseable without an embedded scripting language.

## Sources

- [Telemetry Screens (v4 docs)](https://ballaerospace.github.io/cosmos-website/docs/v4/screens)
- [Telemetry Viewer (v4 docs)](https://ballaerospace.github.io/cosmos-website/docs/v4/tlm-viewer)
