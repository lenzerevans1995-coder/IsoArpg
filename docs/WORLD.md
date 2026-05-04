# World Generation & Editor

How the open-world chunked terrain is generated, painted, and tested.

## Files

| File | Purpose |
| --- | --- |
| `main.gd` | Central generator. Asset pool loading, biome/noise sources, chunk streaming, water/path picking, lighting, clouds, rain, beams. |
| `main.tscn` | Root scene: `Main (Node2D, y_sort_enabled)` → `World (Node2D)` + `HUD (CanvasLayer)`. |
| `editor.gd` / `editor.tscn` | In-engine paint editor (key `1` toggles). Three CanvasLayers: Backdrop / Paint / UI. |
| `water.gdshader` | Pixel-art water surface (mid-teal body + foam edges via `dFdx/dFdy` of the water mask). |
| `flora_wind.gdshader` | Horizontal sway for tall grass; per-instance `phase` uniform + HSV recolor. |
| `breathe.gdshader` | Vertical "breathing" UV displacement for trees/flora + HSV recolor. |
| `ripple_froth.gdshader` | Recolors stock cyan ripple frames to white foam. |
| `beams.gdshader` | Additive god-rays beam overlay. |

## Iso math

```
TILE_W = 128
TILE_H = 64
SPRITE_Y_OFFSET = -82       # canvas pivot at (0.5, 0.18) from bottom
grid_to_screen(g)  = ((g.x - g.y) * 64, (g.x + g.y) * 32)
screen_to_grid(p)  = floor(((p.x/64 + p.y/32) / 2,
                            (p.y/32 - p.x/64) / 2))
```

Y-sorting via `y_sort_enabled` on the World node; `move_child(player, last)` is
re-asserted after each chunk load so the player draws on top of overlapping
flora.

## Chunk streaming

```
CHUNK_SIZE = 16            # cells per chunk side
VIEW_RADIUS_CHUNKS = 2     # load chunks within this radius of the player
```

`_update_chunks()` runs every player move; loads new chunks within radius,
unloads anything outside `VIEW_RADIUS_CHUNKS + 1`. Chunks are dictionaries of
spawned `Sprite2D`/`AnimatedSprite2D` nodes keyed by world cell.

## Noise sources (FastNoiseLite, all Simplex)

| Noise | Frequency | Drives |
| --- | --- | --- |
| `biome_noise` | 0.003 | Continent-scale biome ID (forest, plains, maze, desert, etc.). |
| `forest_noise` | 0.012 | Tree density inside FOREST biome (clusters + clearings). |
| `tree_noise` | 0.06 | Per-cell jitter for tree placement. |
| `path_noise` | 0.018 | Carves dirt-path ribbons through grass. |
| `species_noise` | 0.002 | Which tree/flower family fills a forest pocket (single-species pockets). |
| `color_noise` | 0.0015 | Per-pocket HSV recolor offset (purple forests etc.). |
| `maze_noise` | 0.04 | Hedge-maze cell layout. |
| `ocean_noise` | 0.005 | Large noise-blob ocean bodies. |
| `river_noise` | 0.01 | Winding water ribbons. |

## Tile taxonomy (curated under `assets/forest/`)

| Folder | Contents |
| --- | --- |
| `ground/dirt` | Ground A1 family (base dirt). |
| `ground/grass` | A2 (light grass), A18 (dark grass). |
| `ground/water_bed` | C1/C2/C3 indented dirt where water fills. |
| `ground/mud_path` | I1–I10 light-indented paths. |
| `ground/sand` | F1/F3/F6. |
| `ground/wheat` | J1/J4–J8. |
| `ground/stone` | Stone B family. |
| `edges/grass_corner` | A3 corner pieces. |
| `edges/grass_single` | A4 single-edge pieces. |
| `decor/tufts` | A6 small clumps. |
| `decor/flowers` | A22/A23 + Flora A6 flower variants. |
| `decor/tall_grass` | Flora B1–B6 (walkable, sways). |
| `decor/scattered_stones` | Small rock decorations. |
| `decor/water_ripples/Ripple1..13` | 13 animated ripple variants. |
| `props/trees/{oak,pine,dead}` | Tree A1–A3 / D1–D3 / C1+E1+E3. |
| `props/{bushes,logs,saplings}` | Tree B1, E2/E4/E5, A4. |
| `structures/{cave,stairs,walls/*}` | Cave entrances, stairs, walls. |

## Path edge autotiling

Each non-grass cell adjacent to grass uses a 4-bit grass-neighbor mask (1=NE,
2=SE, 4=SW, 8=NW). Mask values map to:

```
mask 1/2/4/8       -> A4 single-edge tile (suffix from neighbor direction)
mask 3/6/9/12      -> A3 corner tile
mask 5/10          -> two-side stripe (A4 + opposite A4 stacked)
mask 7/11/13/14    -> A3 + A4 combined
mask 15            -> isolated grass island (A3 four corners)
```

Suffix mapping is direction-aware; `_C1_TO_A4_PAIR` swaps suffixes so a C1
water-bed cell pairs with the rotated-grass A4 it abuts.

## Water tile picking (`_pick_water_tile_info`)

Uses `_water_neighbor_mask` (same NE/SE/SW/NW bits as paths) plus interior/
boundary check on each neighbor:

```
mask 15                       -> C3 solid bed
mask 1 / 2 / 4 / 8            -> C1 single-cutoff tip
mask 3 / 6 / 9 / 12           -> if both neighbors interior  -> C2 corner
                                 if both boundary           -> C3
                                 mixed                       -> C1 toward interior
mask 5 / 7 / 10 / 11 / 13 / 14 -> C3 (water continues through)
else                          -> C3 fallback
```

Rationale lives in NOTES drafts 4–11; key rules:
- "water continues unless cutoff" (draft 8): 3-water cells use C3, not C2.
- 1-cell-wide strips use C1 pointing at the interior, never stacked C2.
- C2 only when both adjacent water neighbors are interior.

Surface uses `water.gdshader`: mid-teal `water_color`, `body_variation` flicks
~10% of pixels to `deep_color` per `foam_step_seconds` step, edges (detected by
`length(vec2(dFdx(water_amt), dFdy(water_amt)))`) become solid foam with a
sin-time shimmer.

## Per-pocket HSV recolor (`_color_shift_for(cell)`)

Reads `color_noise` and returns `Vector3(hue_shift, sat_mult, val_mult)`:

```
|n| < 0.20    (0.00, 1.00, 1.00)   default
n >  0.55     (0.50, 0.95, 1.00)   purple forest
n >  0.35     (-0.07, 1.15, 0.95)  red-orange
n >  0.20     (0.10, 1.15, 1.05)   golden yellow
n < -0.55     (0.40, 0.95, 0.90)   deep blue
n < -0.35     (0.30, 1.00, 0.95)   cyan
n < -0.20     (0.85, 1.00, 1.00)   bright pink
```

Applied via `_apply_breathe()`: phase + speed + the three HSV uniforms on a
per-instance `BREATHE_SHADER` `ShaderMaterial`. Trees, flora, flowers, and
grass all use it; tall grass uses the same uniforms on `flora_wind.gdshader`.

## Flower / species pockets

`flower_families` is built at load time by parsing `decor/flowers/`
filenames into directional sets. `_flower_pool_for_pocket(cell)` reads
`species_noise` and returns ONE family per pocket (so a flower field is all
the same flower type, not checkerboarded).

`tall_grass_density = 0.92` in forest biome (almost everywhere); tufts only
spawn under tall grass or in plains.

## Lighting / weather

Modes (`_set_lighting_mode(n)`, keys `F1`–`F4`): noon, sunset, dusk, night.
- Drifting `Cloud1.png` / `Cloud2.png` sprites at very low opacity (0.04–0.10);
  decoupled from camera (`z_as_relative = false`) so they stay in their world
  row as you walk.
- `KEY_5` toggles rain particles, `KEY_6` clouds, `KEY_7` god-ray beams.

Lantern: hand-built radial `Image.set_pixel` quadratic falloff (avoids
`GradientTexture2D.FILL_RADIAL` square-corner artifact).

## Editor (key `1`)

Three CanvasLayers:
- `BackdropLayer` (5) — grey grid behind paint.
- `PaintLayer` (10, `follow_viewport_enabled = true`) — painted sprites.
- `UILayer` (20) — category/family/variant dropdowns + preview.

State:
- `painted_base[cell]` — Array of `{tex, is_water, sprite}` (stacks: each
  paint appends with `z_index = current count`).
- `painted_ripples[cell]` — Array of `{tex, ripple_folder, sprite}` for
  animated ripple overlays.

Categories: Water (C3/C2/C1), Edges (A3/A4), Ground (A1/A2), Decor (A6/A22/B2),
Ripples (13 animated variants).

Save format (`user://drafts/draft_N.json`):
```json
{
  "bases":   [{"tex": "res://...", "is_water": false, "x": -16, "y": -24}, ...],
  "ripples": [{"tex": "res://...", "ripple_folder": "Ripple3", "x": ..., "y": ...}, ...]
}
```
Backwards-compat: legacy `cells` key still loads as `bases`.

Ripple sprites are offset via a centroid-based cache (`_ripple_centroid_offset`)
so they snap to the diamond's visual center.

Pan: hold `Ctrl` + LMB drag (moves the player position; camera follows).

## Key bindings (in-game)

| Key | Action |
| --- | --- |
| WASD / arrow keys | Move |
| LMB hold / click-to-walk | Move toward cursor |
| RMB | Attack |
| Space | Dodge (sidestep / RunBackwards) |
| Shift | Sprint (Walk → Run) |
| Wheel | Zoom |
| `1` | Editor toggle |
| `C` | Character creator |
| `I` | Inventory |
| `G` | Debug: grant random item |
| `F1`–`F4` | Lighting modes (noon/sunset/dusk/night) |
| `5` | Rain |
| `6` | Clouds |
| `7` | God-ray beams |

## Drafts referenced (in `user://drafts/`)

| Draft | Lesson |
| --- | --- |
| 4 | Proper dirt road + river with grass edges. |
| 5 | C2 placement rule: loss-side faces boundary neighbor. |
| 6 / 7 | Invalid placements (what NOT to do). |
| 8 | "Water continues unless cutoff" — 3-water cells use C3. |
| 9 vs 11 | 1-cell strip uses C1 toward interior, not stacked C2. |
| 12 | Single flower family per pocket; tall grass everywhere. |
