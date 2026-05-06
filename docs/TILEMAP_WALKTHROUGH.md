# TileMap Walkthrough — Wiring the curated tiles into the in-engine painter

Companion to `TILEMAP_MIGRATION.md`. Phases 1-3 are done programmatically. This is the manual-in-Godot half: opening the placeholder scene, dragging atlases into the TileSet, painting tiles, drawing collision once per wall.

After this you can paint a level inside Godot, save the scene, and have collision + tagging working with no code.

---

## What's already on disk

```
assets/curated_tiles/
  ground/         (5 tiles)
  ground_edges/   (8 tiles)
  walls/          (15 tiles)
  flora/          (15 tiles)
  elevation/      (22 tiles)
  water/          (11 tiles)
scenes/
  world_tileset.tres   ← empty TileSet, iso 256×128, physics + custom data layers configured
  world_painted.tscn   ← empty Node2D + 4 TileMapLayer children + spawns/player_start
```

`world_tileset.tres` already has:
- Iso shape, stacked layout, tile size 256×128
- Physics layer 0 (mask=1) for wall collision
- Custom data layer "tile_role" (string)
- Custom data layer "lift" (int)

---

## Step 1 — Open the project in Godot, let it import

Reload the project. Godot will scan `assets/curated_tiles/`, see the 76 PNGs + their `.import` sidecars, and cache them. Wait for the FileSystem dock progress bar to finish (~30 seconds first time).

---

## Step 2 — Wire atlas sources into the TileSet

1. Double-click `scenes/world_tileset.tres` in the FileSystem dock. The bottom panel switches to the **TileSet** editor.
2. You'll see "Sources" on the left. Click the `+` button → **Atlas**.
3. In the file picker, navigate to `assets/curated_tiles/ground/` and pick **any one** PNG (e.g. `ground_a1_e.png`).
4. Godot adds it as Atlas Source 0. **In the right inspector**, scroll to **Texture Region Size** and set it to `256 × 256` (the source PNG dimensions). Then click **"Setup"** → Godot autocreates one tile per PNG-sized region.

**Faster way:** in the Atlas source inspector, instead of one PNG, you can drop the **whole folder** by clicking the texture field and selecting a multi-image atlas — but Godot 4 wants a single texture per atlas source, so the per-folder workflow is:

   - One **Atlas Source per PNG** if each tile is its own file (current setup).
   - Use the **`+`** button repeatedly, picking a tile from each folder. Click the source, give it a name like "ground" / "walls" / etc.

A tighter workflow: use Godot's **"Scan source folder"** if available (Godot 4.3+). Right-click in the Sources panel → "Add atlas source from folder". Pick `assets/curated_tiles/ground/`. Godot bulk-creates one source per file.

> **Tip**: rename each Atlas Source as you add it (right-click → "Rename") so the source dropdown reads `ground_a1_e`, `wall_a1_n`, etc. Saves time when picking tiles later.

---

## Step 3 — Add Terrains (autotile)

For grass/dirt/water/walls, you want **terrains** so painting blends edges automatically.

1. In the TileSet editor's bottom panel, click **"Terrain Sets"** tab.
2. Click `+` → adds Terrain Set 0. Set its **Mode** to "Match Sides".
3. Inside that set, click `+` → adds Terrain 0. Name it "grass". Pick a green color.
4. Repeat for Terrain 1 = "dirt" (brown), Terrain 2 = "water" (blue), Terrain 3 = "walls" (grey).
5. Switch to the **"Tiles"** tab and select a grass tile. In the inspector, find **Terrains → Terrain Set / Terrain** and set both to grass. Then for each cell-edge of the tile (NE / N / NW / E / W / SE / S / SW), check whether that edge is grass-bordered or not.

This is tedious for 76 tiles. **Skip it for the first pass** — paint with raw tiles first, add terrains later when you decide which tiles matter most.

---

## Step 4 — Draw collision on walls

1. In the TileSet editor → **"Tiles"** tab.
2. Click any wall atlas source (e.g. `wall_a1_n`).
3. Click the tile's region.
4. Switch the right inspector to **"Physics"** → "Layer 0".
5. Click `+` to add a polygon. Draw a tight quad over the wall's footprint (the diamond at the bottom of the 256×256 canvas, not the full canvas).
6. Repeat for every wall + Stone tile. Once done, painting that tile in the world automatically gets collision.

Walls + Stone = 15 tiles total. ~30 seconds each. Budget 10 min for the first pass.

---

## Step 5 — Paint a starter area

1. Open `scenes/world_painted.tscn`.
2. Click the **`ground`** TileMapLayer node.
3. Bottom dock → **TileMap** tab → **"Tiles"** sub-tab.
4. Pick a `grass` or `dirt` tile from the atlas list. Click + drag in the viewport to paint a floor area.
5. Switch to the **`walls`** layer node. Pick a `wall_a1_n` tile, paint a row.
6. Repeat for `flora` (tall_grass, trees) and `ground_decor` (flowers, tufts).
7. Move the **`player_start` Marker2D** under `spawns/` to the cell you want the player to spawn at.
8. **Save the scene.** The painted layout is now part of `world_painted.tscn`.

You can F6 the scene to test it standalone — no player or HUD will load, but you can verify the tiles render and collision feels right.

---

## Step 6 — Hook into main.gd (when ready)

Don't do this until the painted scene reads correctly on its own.

When ready, I add ~20 lines to `main.gd`:

```gdscript
const PAINTED_WORLD := preload("res://scenes/world_painted.tscn")
const USE_PAINTED_WORLD := true

# inside _ready, before the chunk-streaming setup:
if USE_PAINTED_WORLD:
    var painted := PAINTED_WORLD.instantiate()
    world.add_child(painted)
    var spawn := painted.get_node_or_null("spawns/player_start")
    if spawn and player:
        player.position = (spawn as Marker2D).position
    return  # skip the procedural chunk streamer entirely
```

Setting `USE_PAINTED_WORLD := false` falls back to the existing chunk streamer. Feature-flagged so we can A/B during testing.

---

## Common gotchas

- **Tiles don't render after import** — Godot needs to reimport once. Close and reopen the project, or right-click `assets/curated_tiles/` → "Reimport".
- **Bilinear blur on zoom** — Project Settings → Rendering → Textures → Canvas Textures → Default Texture Filter = `Nearest`. Already set in your project.godot, but verify.
- **Tiles are offset half a cell** — iso shape uses the **center** of the diamond as the tile origin. If your art has the diamond at the bottom of a 256×256 canvas, set "Texture Origin" in the atlas inspector to `Vector2(0, 64)` to shift it up.
- **Terrain bitmask doesn't paint correctly** — terrain edges only match other tiles in the same terrain set. Make sure all "grass" tiles are tagged with the same terrain id.
- **"player_start not found" at runtime** — `world_painted.tscn` ships with one. Make sure you didn't delete it. Adding more (`portal_a`, `portal_b`) is fine for future routing.

---

## What's next after painting

When the starter area paints OK and reads in-game with collision:

1. Wire `main.gd` per Step 6.
2. Switch `dungeon.gd` to the same TileMapLayer pipeline (separate scene `scenes/dungeon_painted.tscn`).
3. Migrate `editor.gd`'s tile-paint UI off — it's superseded.
4. Decide on the chunk streamer's fate (keep behind flag, or retire).

Each is independent and reversible.
