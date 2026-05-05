# Game State Snapshot — 2026-05-04

A single-file map of where the project actually is. Pairs with `CHARACTER.md`, `WORLD.md`, `NOTES.md` (older topical docs) and `CLEANUP_PLAN.md` (reorg checklist).

---

## Engine / Project

- Godot 4.6.2 stable, GDScript, Windows.
- Entry scene: `main.tscn` (script `main.gd`).
- Pixel-art project, integer offsets, NEAREST texture filter pipeline; `pixelize` / `world_pixelate` shaders.
- `NO_GEN := true` kill-switch in main: procedural overworld generator does **not** populate on startup.
- Player start hard-coded to cell `(1, -36)`.
- **Accessibility disabled** in `project.godot` (`accessibility/general/accessibility_support = 2`) — works around a Godot 4.6.2 Windows render-thread bug that exhausted the RID pool with editor sub-windows.
- Repo: https://github.com/lenzerevans1995-coder/IsoArpg (main branch).
- Git ignores all images / audio / Effekseer / Stand-alone Character creator zip — repo is code + small data only.

---

## Folder layout

```
/                       — main.gd, main.tscn, player + enemy scripts, HUD, etc.
data/                   — small JSON + .tres item metadata
data/items/<slot>/      — per-item .tres files (one per catalog entry)
docs/                   — this file, CHARACTER.md, WORLD.md, NOTES.md, CLEANUP_PLAN.md
shaders/                — all .gdshader
loot/                   — full loot system (see "Loot system" section)
dev_scenes/             — bounds_editor / fx_test_scene / loot_beam_editor (standalone tools)
tools/                  — Python helpers (apply_item_names.py, etc.)
_archive/               — orphaned scripts kept for reference
assets/                 — gitignored, lives on disk only
```

---

## Overworld

- Iso tilemap with ground + decoration layers. Path tool retired; current path is a saved preset.
- Long grass / Flora B is the only destructible foliage.
- Clouds, fog, water, ripple_froth shaders running. Cloud drift + chunk updates suspended while in dungeon.
- Portal interaction: **Q** opens "Enter dungeon?" (`portal_dialog.gd`). Inside dungeon, **ESC** opens "Leave?".

## Dungeon (`dungeon.gd`)

- Procedural, fixed `FIXED_SEED = 1337` for repeatability.
- 7–11 rooms + 1 boss room, BSP-ish.
- `draft_Dungeon.json` round-trip persistence (floor cells, walls, transparent walls, spawn, props).
- Walls: A1 straight (`_N/_E/_S/_W`), A2 corners only at outer corners. Opaque (`_N/_W`) z=110, transparent (`_S/_E`) z=100.
- Skeletons get a darker tint when behind transparent walls.
- World tree set to `PROCESS_MODE_DISABLED` while dungeon active.

---

## Player

- `main.gd` owns the player directly (`player_layered.gd` instantiated at `main.gd:171`).
- LayeredCharacter (`layered_character.gd`) — 13-layer stack reading from `assets/charachters/Stand-alone Character creator - 2D Fantasy V1-0-3/.../StreamingAssets/spritesheets/`.
- Frame layout: 128×128, 15 cols × 8 rows.
- Sheet path: `<root>/<folder>/<anim>.png` where `<anim>` ∈ Idle, Run, Attack1-5, RideIdle, …

### CharacterStats (`character_stats.gd`)
- RefCounted. Per-class baseline. Str / Dex / Vit / Energy + level + xp.
- Polynomial XP curve. `add_xp()` cascades level-ups (+5 stat / +1 skill point each).
- `damage_bonus_pct()` defined but **not yet wired into damage** at the strike sites in main.gd (~3164 spider, ~3282 skeleton).

### Skill DB (`skill_db.gd`)
| Slot | Skill | Icon | CD |
|------|-------|------|----|
| RMB | warrior_basic | 03 | 0.4 |
| 1 | warrior_cleave | 21 | 3.0 |
| 2 | warrior_whirlwind | 06 | 6.0 |
| 3 | warrior_slam | 08 | 2.5 |
| 4 | warrior_berserk | 30 | 14.0 |
| 5 | warrior_execute | 28 | 8.0 |

Cooldown overlay implemented, **skill effects still stubbed** (only basic attack does damage).

---

## Enemies

### Skeletons (`skeleton.gd`)
- 9 kinds (Warrior, Archer, Wizard, Brute, Deathlord, Dark Knight, Berserker, Dark Archer, Necromancer).
- **Spritesheet-driven** (rewritten this session): reads `Spritesheets/With shadow/<class>/<anim>.png` and slices via `AtlasTexture`. 8 rows × N cols (clockwise from E).
- Per-frame folders deleted (~33k PNGs gone).
- BFS pathfinding, sleep at >1100 px from player.
- FPS matches player: 12 / 18 / 16 (idle / attack / run).

### Goblins (`goblin.gd`)
- Already spritesheet-driven (FRAME 128×128, 15×8).
- Active in BATTLE_WORLD spawns (currently commented out in main.gd).

### Other
- `enemy_db.gd` — XP rewards + level-gap multiplier.
- `arrow.gd` — arrow projectile.
- `monster.gd` — generic spider/wave-system renderer (used by `_spawn_spider`).

---

## Loot system (`loot/`)

All loot-related code lives in `loot/`. Full pipeline now:

| File | Purpose |
|------|---------|
| `loot/rarity_visuals.gd` | Maps each rarity → palette index in `data/swatch_palette.json` (81-swatch). `color_for(rarity)` is the only API. |
| `loot/loot_drop.gd` | Visual coin drop + rarity beam. Reads colors via `RarityVisuals`. Beam drawn in code (`_BeamNode` inner class). |
| `loot/item_metadata.gd` | Resource class — per-item `.tres` schema (item_id / slot / base_name / drop config / unique override). |
| `loot/item_affix.gd` | Resource class — rolled-affix instance (id / tier / value / prefix flag). |
| `loot/affix_db.gd` | 6 baseline affixes (3 prefix, 3 suffix), 5 tiers each, 5 word variants. `roll(id, tier, rng)` returns ItemAffix. |
| `loot/item_editor.gd` + `.tscn` | Naming / metadata editor with live LayeredCharacter preview, swatch grid, rotation, zoom, mount/wield toggles. |
| `loot/icon_baker.gd` | Bakes per-item PNGs into `assets/generated/icons/<id>.png` (S-facing inventory icon) and `assets/generated/ground/<id>.png` (death pose). |
| `loot/item_catalog_dump.gd` | `@tool` EditorScript — dumps the catalog grouped by slot for verification. |
| `loot/loot_beam_editor.gd` + dev_scenes/...tscn | Beam calibration tool. |

**Rarity colors** (indices into `data/swatch_palette.json`):
| Rarity | Idx | Hex | |
|--------|-----|-----|-|
| COMMON | 0 | `#f5f5f5` | white |
| MAGIC | 33 | `#1854a1` | blue |
| RARE | 55 | `#efd834` | yellow-gold |
| UNIQUE | 58 | `#dc740b` | orange |
| LEGENDARY | 49 | `#c60024` | red |

**Item naming pass complete:**
- 117 catalog entries across 13 slots (24 head, 19 chest, 9 legs, 5 shoes, 4 hands, 2 belt, 8 bag, 25 melee, 7 ranged, 5 mount, 2 offhand, 7 shield).
- 21 marked `is_unique = true` (Whisperveil, Wargaze, Skyrender, Brood Mother, etc.).
- 3 stubbed `can_drop = false` with TODO notes:
  - `melee_18` Pickaxe — pending mining system
  - `ranged_5` "Garden Tool" — pending; not actually a bow
  - 5 cosmetic-only hair/bald/skin entries
- `head_2` ("necklace") removed entirely (skipped in `items_db.SKIP_IDS`, `.tres` deleted).

**Magic mainhands removed** (`magic_1/2/3` were spell-cast hand animations, not items). `WeaponClass.MAGIC` enum kept for future spell-class items.

**Outstanding loot work**
- Inventory pickup not implemented — drops linger forever.
- `icon_baker.gd` button works; whether you've actually run a bake yet determines if `assets/generated/` exists.
- Inventory UI / panels_ui need to consume baked icons + apply material tint + rarity glow.

---

## UI / HUD

### Bottom HUD (live)
Granite + warm-grey "stage", brushed-bronze rim, gold pinstripe, dark cavity, white-spec corner rivets.

| File | Purpose |
|------|---------|
| `combat_hud.gd` + `.tscn` | Bottom chrome, orbs, slots, XP bar |
| `hud_center_bar.gd` | Reusable panel chrome |
| `hud_skill_square.gd` | 44px slot, cooldown overlay, atlas icon |
| `hud_orb.gd` | HP/MP globes |
| `hud_stamina_bar.gd` | XP bar (bound to `Root/Stamina`) |
| `hud_stone_button.gd` | Inset stone button |
| `hud_ui_buttons.gd` | C/I/K/M/Q/P/?/≡ button grid |
| `icon_atlas.gd` | CPU-side 64×64 icon slicer (sheet exceeds GPU max) |
| `panels_ui.gd` | I/C/K pop-up panels — known crash on character `_rebuild_character` |
| `inventory_ui.gd` | Modal grid (overlap with panels_ui — needs consolidation) |
| `stat_stepper_btn.gd` | +/- Lucide-style buttons |

`@tool` was stripped from `icon_atlas` / `hud_skill_square` / `hud_stone_button` / `stat_stepper_btn` — they were leaking GPU resources in the editor.

---

## Dev tools

| File | Toggle |
|------|--------|
| `editor.gd` + `editor.tscn` | F1 — tile painter |
| `bounds_editor.gd` (dev_scenes/) | standalone — collision tuning |
| `loot/loot_beam_editor.gd` (dev_scenes/) | standalone — beam calibration |
| `dev_scenes/fx_test_scene.tscn` | standalone — Effekseer test (mostly defunct now Effekseer is gone) |
| `monster_debug_panel.gd` | F9 — runtime monster inspector |
| `world_shader_panel.gd` | F6 — shader tweaker |
| `asset_placer.gd` | key-toggle — asset preview |
| `tools/apply_item_names.py` | one-shot rename script |
| `tools/bake_otherworlds_pieces.py` | legacy (otherworlds gone) |

---

## Performance state

- Asset count crashed from 85,824 → 14,768 PNGs (83% reduction): deleted `2D HD Character pack 1 V1.2/`, deleted Undead per-frame folders (replaced by sheet slicing), deleted Effekseer assets + addon, `.gdignore` on Stand-alone creator runtime files.
- `.godot/imported/` cache wiped; rebuilds fresh on next launch.
- Skeleton spritesheet refactor saves both disk PNG count and texture allocs.
- Accessibility subsystem disabled — was the actual cause of the editor crash spam.

---

## Outstanding (carry-over)

1. **Stats → damage scaling** — `stats.damage_bonus_pct()` still unused at strike sites (`main.gd:3164, 3282, etc.`).
2. **`_rebuild_character` crash** in `panels_ui.gd:540` — reparent error, not yet root-caused.
3. **Skill effects** — Cleave / Whirlwind / Slam / Berserk / Execute only animate cooldowns.
4. **Loot pickup** — drops accumulate forever; no inventory grant.
5. **Inventory UI consolidation** — `inventory_ui.gd` vs `panels_ui.gd` overlap.
6. **Spritesheet refactor for HD Character pack** — not started; `2D HD Character pack 1 V1.2/` was deleted instead since unused.
7. **Other classes** — only warrior is wired through SkillDB / CharacterStats baselines.

---

## File map (the ones that matter)

| Area | Files |
|------|-------|
| Core | `main.gd`, `main.tscn`, `terrain_lift.gd`, `tile_rules.gd` |
| Player | `player.gd`, `player_layered.gd`, `composite_character.gd` (wait — archived), `character_stats.gd`, `loadout.gd` |
| Enemies | `skeleton.gd`, `goblin.gd`, `monster.gd`, `enemy_db.gd`, `enemy_hp_bar.gd`, `boss_hp_bar.gd` |
| Combat FX | `arrow.gd`, `attack_effect.gd`, `hit_fx.gd`, `thunder_fx.gd`, `explosion_anim.gd` (chain_lightning_fx, ice_spike_fx, archer_shot_fx archived with Effekseer) |
| Dungeon | `dungeon.gd`, `portal_dialog.gd` |
| Loot | `loot/*.gd` (see Loot section) |
| Skills | `skill_db.gd` |
| HUD | `combat_hud.gd/.tscn`, `hud_center_bar.gd`, `hud_skill_square.gd`, `hud_orb.gd`, `hud_stamina_bar.gd`, `hud_stone_button.gd`, `hud_ui_buttons.gd`, `icon_atlas.gd` |
| Panels | `panels_ui.gd`, `inventory_ui.gd`, `stat_stepper_btn.gd`, `inventory.gd`, `items_db.gd` |
| Editor | `editor.gd/.tscn`, `editor_overlay.gd`, `building_generator.gd` |
| Dev | `bounds_editor.gd`, `fx_test_scene.gd`, `monster_debug_panel.gd`, `world_shader_panel.gd`, `asset_placer.gd` |
