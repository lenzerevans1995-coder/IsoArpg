# TileMap Migration Plan — Godot Built-in Editor

Switching from the custom paint editor (`editor.gd` + `editor_overlay.gd` + `flora_at` cell dict) to Godot 4's `TileMapLayer` + `TileSet` resources for the world layout. Goal: better collision, cleaner save/load, native Godot tooling. **Cost: the chunk-streamed procedural generator (`_update_chunks`, `_load_chunk`, etc.) becomes unused; tracked, not deleted.**

This is a plan, not an execution. Read it, push back where you disagree, and we'll work in phases.

---

## Phase 1 — Inventory the tiles actually in use

We don't migrate everything. Only tiles the running game/editor references should make it into the curated `TileSet`. Audit checklist:

| Source | What to extract |
|--------|-----------------|
| `data/tile_roles.json` | Currently tagged tiles — `corner_NW`, etc. Master list of tiles already named. |
| `editor.gd` (palette categories — Water/Edges/Ground/Decor/Ripples) | The dropdown buckets. Each bucket lists actual file paths. |
| `tile_rules.gd` | Tile taxonomy by suffix (Ground/Water/Wall/Decor/Prop). |
| `terrain_lift.gd` | Tile-role / lift / storey rules (G1–G7 hill semantics, A1 dirt etc.). |
| `dungeon.gd` | Wall A1/A2 + Stone variants used inside dungeons (`_N`, `_E`, `_S`, `_W` suffixes). |
| `main.gd::TILE_POOLS` (path-edge & flora pools) | Edges/Corners/Single suffixes for path autotile. |
| `user://drafts/draft_*.json` and `user://arena.json` | Painted templates — what the user actively places. Their referenced PNG paths are the canonical "in-use" set. |

**Output of phase 1:** a flat list (~50–150 PNG paths) of "tiles I actually paint with."

I can produce this list as a script — `tools/audit_tiles_in_use.py` — that walks all of the above and prints unique tile paths. Doesn't move anything.

---

## Phase 2 — Curated folder layout (proposed)

Once we have the list, copy (don't move yet) the in-use tiles into a clean folder:

```
assets/curated_tiles/
  ground/
    grass.png            (was Ground A1_S, etc.)
    dirt.png
    mud.png
    stone_floor.png
  ground_edges/          ← grass→dirt corners, A3 family
    grass_to_dirt_NW.png
    ...
  walls/                 ← Wall A1, A2, Stone 9
    wall_n.png
    wall_e.png
    wall_corner_ne.png
  flora/
    tree_oak.png
    tree_pine.png
    bush.png
    tall_grass.png       ← destructible
    flower.png
  water/
    water_animated_0.png
    water_animated_1.png
    ...
  props/
    portal.png
    spike_trap.png
```

Why a copy first, not a move:
- Original `assets/forest/` and `assets/tilesets/` paths stay valid for the procedural generator (in case we want to fall back).
- The new `TileSet` resource indexes the **curated** copies only.
- Once the new layout is shipping and good, the original folders can be retired in a separate cleanup pass.

**Naming convention recommendation:** flatten the cryptic `Ground A1_S` style to descriptive lowercase. Pure ergonomic — easier to find tiles in Godot's TileSet inspector.

---

## Phase 3 — TileSet resource design

One `world_tileset.tres` Resource. Setup inside it (Godot's TileSet editor handles this UI-first; no code):

| Knob | Value | Why |
|------|-------|-----|
| **Tile Shape** | `Isometric` | Matches your projection. |
| **Tile Layout** | `Stacked` | Standard for D2-style iso. |
| **Tile Size** | `128 × 64` (verify) | Your existing iso cell — need to confirm against your art. |
| **Sources** | One `TileSetAtlasSource` per curated subfolder | Lets Godot auto-pack and you can drag whole folders in. |
| **Physics Layers** | 1 layer: `walls_collision` | Walls + obstacle props get a polygon on this layer. |
| **Custom Data Layers** | `tile_role` (string), `lift` (int) | Replaces `tile_roles.json` and `terrain_lift.gd` lookups — data lives on the tile itself. |
| **Terrains** | 1 terrain per "blendable" group: grass, dirt, water, walls | Enables Godot's autotile painting (you click + drag a region of grass and it picks the right edges/corners automatically). |

You set this up once via Godot's UI. I write a short doc on which custom data values to use for which roles.

---

## Phase 4 — Scene structure (avoid the monolith)

`main.gd` is already big. New world-paint flow goes in **its own scene**, not in `main.tscn`:

```
scenes/world_painted.tscn
  Node2D (root)              ← entry point for the painted world
  ├─ TileMapLayer "ground"   ← floor (iso layer)
  ├─ TileMapLayer "walls"    ← occluders + collision
  ├─ TileMapLayer "decor"    ← non-blocking flora
  └─ Node "spawns"           ← marker children for player_start, portals, etc.
```

`main.gd` gains a single `const PAINTED_WORLD := preload("res://scenes/world_painted.tscn")` and a `_load_painted_world()` helper that instances it under the existing `World` Node2D. The chunk streamer is **commented out**, not deleted, with a `# DISABLED: superseded by world_painted.tscn` note.

This way:
- `main.gd` doesn't bloat — adds maybe 20 lines.
- The procedural generator code stays in place for rollback.
- The new scene is self-contained: player can be tested standalone in `world_painted.tscn` (F6).

---

## Phase 5 — Import setup

Godot's default import for PNGs uses linear filtering. For pixel art:

| Setting | Value |
|---------|-------|
| `Filter` | `Nearest` |
| `Mipmaps` | Off |
| `Fix Alpha Border` | On |
| `Compress Mode` | `Lossless` |

Apply via `Editor → Editor Settings → Import → Default Texture Filter = Nearest` (project-wide), OR per-folder via a `.gdimport` snippet. I'll write a one-shot script that bulk-applies the right `.import` config to every PNG in `assets/curated_tiles/` so you don't have to click 100 times.

---

## Phase 6 — Walkthrough: using the in-engine TileMap painter

Once the curated tiles + TileSet exist:

1. **Open `scenes/world_painted.tscn`** in Godot.
2. **Click the `TileMapLayer "ground"` node.** The bottom dock switches to the **TileMap** tab.
3. **In the TileMap tab → "Tiles" sub-tab**, the right panel shows your atlas — every tile from `assets/curated_tiles/ground/`.
4. **Click a tile, click in the viewport** to paint. Drag for area painting. Right-click to erase.
5. **Switch sub-tab to "Terrains"** for autotile painting:
   - Pick the "grass" terrain at the bottom.
   - Hold and drag a brush across cells — Godot auto-picks edge/corner tiles for you. No more manually choosing `Ground A3_S` for north-west grass corners.
6. **Walls layer**: select `TileMapLayer "walls"`, pick a wall tile, paint. The TileSet's physics polygon comes along automatically — collision works without you wiring anything.
7. **Save the scene** (`Ctrl+S`). The painted layout is part of the scene file; no JSON drafts needed.
8. **Spawns**: drag a `Marker2D` into the `spawns` group, name it `player_start` or `portal_a`. `main.gd` reads these on load.

Optional: bind the player position to the painted scene by dropping a `Marker2D` named `player_start` in the world_painted scene; `main.gd` looks for it on load and teleports the player there.

---

## Phase 7 — Collision (the actual reason for the migration)

Godot's TileSet handles per-tile collision via a polygon you draw once per tile in the TileSet inspector:

1. Open `world_tileset.tres`.
2. Pick the `walls` atlas source.
3. Click any wall tile in the source preview.
4. Switch to the "Physics" sub-tab.
5. Draw the collision polygon (usually a tight rectangle for walls, half-tile for half-walls).
6. Tile picks up that polygon every time it's painted.

**Player + skeleton collision wiring:** they'll need a `CollisionShape2D` and to interact with the wall layer. Probably means switching `player_layered.gd` from script-driven movement to `CharacterBody2D` with `move_and_slide`. That's a follow-up phase, not this brief.

---

## Phase 8 — Migration phases (non-destructive)

| Phase | What | Reversible? |
|-------|------|-------------|
| 0 | This doc | ✓ |
| 1 | Audit script — list tiles in use | ✓ — read-only |
| 2 | **Copy** in-use tiles to `assets/curated_tiles/` | ✓ — originals untouched |
| 3 | Bulk-set `.import` to NEAREST on the copies | ✓ — only affects new files |
| 4 | Build `world_tileset.tres` (you, in editor; I write a setup checklist) | ✓ — only the .tres is new |
| 5 | Build `scenes/world_painted.tscn` with empty TileMapLayers | ✓ |
| 6 | Paint a starting area into the scene | ✓ — just data |
| 7 | `main.gd` loads `world_painted.tscn` instead of running the chunk streamer (toggle behind `const USE_PAINTED_WORLD := true` so you can flip it off) | ✓ — flag flip |
| 8 | Verify in-game: walk around, hit walls, spawn skeletons, drop loot | — |
| 9 | (Optional, separate task) move skeleton/player to CharacterBody2D for proper Godot collision | — |
| 10 | (Optional, far future) retire `editor.gd` / chunk streamer / `flora_at` dict | — |

We can stop after Phase 8 — that's a fully painted, walkable world with collision. The cleanup of old code is its own separate decision.

---

## What breaks (acknowledged)

- **Procedural overworld generator** — `_load_chunk`, `_make_grass_chunk`, the noise-driven flora placement. Stays in code, not invoked. Can be re-enabled by flipping `USE_PAINTED_WORLD` if needed.
- **Custom paint editor (`editor.gd` + `editor.tscn`)** — replaced by the built-in Godot one. F1 toggle becomes redundant. Don't delete yet; lives alongside until we're sure.
- **`draft_*.json` save format** — replaced by `.tscn` scene saves. Old drafts are dead data.
- **Anything else that reads `flora_at` cell dict at runtime** — needs a re-read pass to migrate to `TileMapLayer.get_used_cells()` + `tile_get_custom_data("tile_role")`.

---

## What I need from you to start Phase 1

Just say "go phase 1" and I'll write `tools/audit_tiles_in_use.py` — a read-only script that walks the project, parses `tile_roles.json`, drafts under `user://`, and prints a single deduped list of tile PNG paths actively used. You eyeball it, point at extras to drop, and that becomes the seed list for `assets/curated_tiles/`.

Nothing gets moved or imported until you greenlight phase 2.
