# Iso Interior Generator — PoC Notes

Godot 4.6 proof of concept. Procedurally generates explorable isometric
interiors and drops a controllable character into them.

## Files

| File | Purpose |
| --- | --- |
| `project.godot` | Engine config, WASD + R input map, window size 1280x720, `default_texture_filter=Nearest`. |
| `main.tscn` | Root scene. `Main (Node2D)` → `World (Node2D, y_sort_enabled)` + `HUD (CanvasLayer)` with a status `Label`. |
| `main.gd` | Asset scanning, BSP room layout, floor / wall / door / furniture placement, player spawn, regenerate on `R`. |
| `player.tscn` | `Player (Node2D, y_sort_enabled)` → `Sprite2D` + `Camera2D` (`zoom 0.55`). |
| `player.gd` | 8-direction sprite-sheet animation (region_rect), iso movement, wall sliding. |

## Iso math

Tile art: 128×256 PNG. The diamond floor footprint is the bottom **128×80**
(per the asset's alpha bbox). All sprites are placed with `centered = true`
and `offset = (0, -96)` so the diamond center aligns with the node's
position.

```
TILE_W = 128
TILE_H = 64
grid_to_screen(g) = ((g.x - g.y) * 64, (g.x + g.y) * 32)
```

Inverse (used for player wall collision):

```
gx = (sx / 64 + sy / 32) / 2
gy = (sy / 32 - sx / 64) / 2
```

Grid axis convention: `+gx` heads bottom-right, `+gy` heads bottom-left. So
the four diamond edges of cell `(gx, gy)` map to wall directions:

| Cell edge on screen | Direction key | Borders neighbor |
| --- | --- | --- |
| top-right | `N` | `(gx, gy-1)` |
| top-left  | `W` | `(gx-1, gy)` |
| bottom-right | `E` | `(gx+1, gy)` |
| bottom-left | `S` | `(gx, gy+1)` |

Outer-perimeter wall placement uses this mapping:

- row `gy = y0` → `_N` walls
- row `gy = y1` → `_S` walls
- col `gx = x0` → `_W` walls
- col `gx = x1` → `_E` walls

Internal walls between two BSP rooms run along the shared edge with one
random door cell punched out.

## Generation pipeline (`_generate`)

1. **Clear** all `World` children except the player; reset `blocked` /
   `floor_cells` dicts.
2. **Pick a texture set** for the building so styles never mix:
   - `cur_floor`: a single random `Ground *_E` texture.
   - `cur_wall_dir`: pick one wall *family* (e.g. `Wall A1`) that has all
     four directional variants. Restricted to `GOOD_WALL_FAMILIES`.
   - `cur_door_dir`: same, for doors.
3. **BSP split** an outer rect (`16-22` × `14-18`) into 1–4 rectangular
   rooms (`_bsp_rooms`, depth 2). Each room is tagged with a random theme
   (`bedroom`, `living`, `kitchen`, `bathroom`).
4. **Floor** under everything (so walls sit on a floor cell, not an empty
   one). Floor sprites use `z_index = -1` to ensure the player and props
   are never overdrawn by an SE-neighbor floor diamond.
5. **Outer perimeter walls** placed inward (no double-stack at corners —
   `_place_wall` early-returns if the cell is already blocked).
6. **Internal walls** between adjacent room pairs (`_wall_between`) with
   one door opening per shared edge.
7. **Outer entrance**: one random outer-perimeter cell is replaced by a
   door.
8. **Furniture** scattered per-room, drawn from prefix buckets keyed by
   room theme: bedroom→`Bed/Shelf`, living→`Couch/Chair/Table`,
   kitchen→`KitchenObject/Table/Chair`, bathroom→`Toilet/Trash`. Avoids
   the player spawn cell and any already-blocked cell.
9. **Player** instantiated once and reused across regenerations. Each
   regen just moves `player.position` to `grid_to_screen(spawn_cell)`.

## Asset bucketing (`_load_textures` / `_bucket`)

Walks `res://2D HD Zombie interior tiles/.../Tiles/`, sorts each PNG by
filename:

- `Ground *_E.png` → `floor_textures`
- `Wall <fam>_<dir>.png` → `wall_families[fam][dir]` (dict-of-dicts)
- `Door <n>_<dir>.png` → `door_families[fam][dir]`
- Anything matching a furniture prefix and ending `_E.png` →
  `furniture_by_prefix[prefix]`

`_pick_complete_family` only considers families with all four `N/S/E/W`
variants and prefers the whitelist. The whitelist excludes:

- **Wall D / Wall F** — these have `_E`/`_W` drawn on the *opposite* canvas
  side compared to A/B/C/E. Mixing them creates pillar-looking gaps.
- **Wall A5 / A6 / E5** — half-wall and window variants that don't form
  continuous walls.

## Player (`player.gd`)

- Sprite sheet: `Idle_Shadowless.png` / `Walk_Shadowless.png`, both
  `1920×1024`, laid out as **15 columns × 8 rows of 128×128 frames**.
- Rows = directions. Assumed clockwise from north:
  `0:N, 1:NE, 2:E, 3:SE, 4:S, 5:SW, 6:W, 7:NW`. Direction is computed
  from the input vector via `_vec_to_dir` (8 sectors of 45°, 0 = north).
- Animation drives a `Sprite2D.region_rect` updated each `_process` —
  no `AnimatedSprite2D`, no separate atlas resources.
- Sprite `offset = (0, -34)` puts the character's feet on the diamond
  center (frame is 128×128 with ~33px of empty space below the feet).
- Movement is screen-space at `SPEED = 320 px/s`. Before applying a step,
  `_cell_blocked` converts the target screen position to a grid cell and
  checks `main.is_blocked`. If blocked, axis-by-axis fallback gives wall
  sliding.
- `Camera2D` is on the player at `zoom (0.55, 0.55)` and calls
  `make_current()` in `_ready`.

## Render ordering

Two layers:

- **z = -1**: floor tiles (drawn first, never covers anything).
- **z = 0**: walls, doors, furniture, player. Y-sorted by node position
  inside the `World` container so SE objects correctly occlude NW ones.

This avoids the classic iso bug where the south-west neighbor floor's
diamond extends back into the player's lower-left body and overdraws.

## Controls

| Key | Action |
| --- | --- |
| `WASD` | Move |
| `R` | Regenerate the building |

HUD label shows the current player position so movement can be verified
at a glance.

## Known gotchas

- The 8-direction row order in the spritesheet is *assumed* — if the
  character faces wrong relative to input, edit the row mapping in
  `_vec_to_dir` or swap `direction` indices.
- BSP depth is hard-coded to 2 → at most 4 rooms. Bump depth in
  `_generate` if you want more.
- Furniture placement is purely random within the room interior with
  one cell per piece. There's no rotation logic and no clearance for
  multi-tile objects — every furniture tile uses the `_E` variant.
- The outer-door punch frees any wall sprite at the chosen cell by
  iterating `world.get_children()` — fine for PoC sizes, O(n) per
  regenerate.
- Project.godot was regenerated by Godot 4.6 (added `"location": 0` to
  input events, listed `4.6` in features). Re-saving from any 4.x editor
  will adjust the format string but is otherwise harmless.

## Swapping in new art

Things that will need to change when assets are replaced:

1. **`TILES_DIR`** path constant in `main.gd`.
2. **Filename conventions** in `_bucket` — the current code keys off
   prefixes (`Ground `, `Wall `, `Door`, furniture buckets) and
   directional suffixes (`_N/_S/_E/_W`). New art will likely use a
   different scheme (e.g. autotile sets, or wall-edge sprites instead of
   wall-tile sprites).
3. **Tile dimensions** (`TILE_W`, `TILE_H`, `SPRITE_Y_OFFSET`) and
   per-sprite offset math if the new art uses a different diamond size
   or anchor.
4. **`GOOD_WALL_FAMILIES`** whitelist — drop entirely if the new art
   doesn't have the same family/direction issues.
5. **Player sprite-sheet constants** in `player.gd` (`FRAME_W`,
   `FRAME_H`, `COLS`, `ROWS`, paths) and the `offset.y` value that pins
   feet to the diamond.

Architecture (BSP layout, blocked-cell dict, z_index split, region_rect
animation, wall-sliding) is asset-agnostic and should carry over
unchanged.
