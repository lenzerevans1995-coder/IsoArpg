# Game State Snapshot — 2026-05-05

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
- **Slice scope (warrior baseline):** Str 10, Dex 5, Vit 10, Energy 5.
  - Str: `damage_bonus_pct = strength * 1.0` % (no cap for slice).
  - Vit: `max_hp = base 50 + vit * 5` → 100 HP at L1, +5 HP per Vit point.
  - Dex / Energy stubbed with `# TODO post-slice` comments — allocation works but no gameplay effect yet.
- Polynomial XP curve, total to L5 ≈ 870. `add_xp()` cascades level-ups (+5 stat / +1 skill point each).
- `_allocate_stat_point` in `panels_ui.gd` now refills hp/mp to new max on Vit/Energy spend so the orb visibly responds; emits `hp_changed` / `mp_changed` to refresh HUD.

### Skill / VFX system (composable, data-driven)

A skill is a `SkillDef` resource (`skill_def.gd`) saved at `res://data/skills/<id>.tres`. The author builds it visually in `dev_scenes/skill_editor.tscn` — no code changes per skill. A skill is a stack of independently-tuned layers:

| Layer | Pool | Sources |
|---|---|---|
| Trigger body anim | 11 | `Attack1..5`, `AttackRun`, `AttackRun2`, `Special1`, `Idle`, `Walk`, `Run` (LayeredCharacter sheets) |
| Effect A overlay | 9 | `Effect1..5`, `Magic1..3`, `(none)` (character-creator pack) |
| Effect B overlay | 9 | same pool, second slot for combos (e.g. aura + cast burst) |
| Slash trail | 3 | `Slash1`, `Slash2`, `(none)` |
| Per-layer tint | 81 | swatches in `data/swatch_palette.json`, applied via the `effect_tint.gdshader` luminance-recolor (Effect A / B / Slash / Projectile each get their own) |
| Projectile | 70 | `data/projectiles.json` registry: HD pack 1 (10), Pack 1 (20), Pack 2 (26), Fantasy tileset (14) |
| Projectile motion | 4 | `at_player`, `at_target`, `travel`, `arc_rain` |
| Origin / target offset | continuous | blue / red drag markers in editor stage |
| Projectile scale + frame trim + fps + speed + arc count + arc radius | continuous | per-skill numeric tuning |
| Damage shape | 4 | `cone`, `circle`, `single`, `none` |

**Modularity score (rough combinatorial space)**: `11 × 9 × 9 × 3 × 71 × 4 × 4 ≈ 10.1M` discrete configurations before any color picks. With four palette-tinted layers (`81^4 ≈ 43M` color combos on top), the coarse upper bound is **~430 trillion unique skill configurations** — and that's still ignoring the continuous fields (offsets, scale, frame trim, fps, speed, arc count, arc radius, damage range, damage angle). For practical purposes the system is *open-ended*: every skill can have its own visual identity without writing a line of GDScript.

**Editor UX** (`dev_scenes/skill_editor.tscn`):
- Cascading Pack → Category → Name pickers populate the projectile slot.
- Draggable **blue** marker = origin offset (where projectile spawns relative to caster). Visible for `at_player` + `travel`.
- Draggable **red** marker = target offset (where projectile lands relative to enemy silhouette). Visible for `at_target` + `travel` + `arc_rain`.
- Draggable **dummy enemy** silhouette in the preview stage; the red marker follows it so target offsets stay anchored to the enemy's body.
- Body anim + projectile auto-fire in sync each loop — the projectile spawns automatically each time the trigger anim wraps from frame 14 → 0, no need to press Play Skill repeatedly.
- Preview SubViewport renders at 140×140, NEAREST-upscaled 4× to match the in-game pixel grid.

**Runtime path**: `player_layered.gd::play_skill(def)` reads the SkillDef → equips Effect A / B / Slash layers with the luminance shader tinted to the saved colors → spawns world-FX (Fantasy tileset effect, `explosion_anim.gd`) → calls `ProjectileRuntime.play(def, parent, origin, target)` which scans the projectile folder via DirAccess, loads frames, applies offsets + scale, and drives one of the four motion modes.

### Buff skill plan (`damage_shape = "none"`)

`warrior_berserk` is the canonical self-buff. Plan for the buff system:

1. **Trigger path** — `play_skill(def)` already runs the cast anim + spawns the buff projectile (`fantasy/Buffs/Buff1` `at_player`). Damage code returns early on `damage_shape = "none"`.
2. **Buff resource** — add a sibling `BuffDef` (per-skill, optional). Fields:
   - `duration_sec: float` (e.g. 6.0 for Berserk)
   - `damage_mult_bonus: float` (1.5 = +50% damage while active)
   - `move_speed_mult: float` (1.2)
   - `incoming_damage_mult: float` (1.4 — Berserk takes more damage as a tradeoff)
   - `tick_effect_folder: String` (optional aura layer that loops on the body for the duration, NOT a one-shot)
3. **Runtime** — a small `ActiveBuff` struct on the player tracks `time_left`, applies the multipliers each frame to `compute_player_damage`, `move_speed`, and `take_player_damage`. Stacking rules: re-cast refreshes duration; multiple distinct buffs stack multiplicatively.
4. **Visual feedback** — looping `vfx2` layer on the LayeredCharacter (e.g. `Magic1`) tinted to the buff's color, plus a HUD ring around the active skill icon ticking down. Cleared in `_on_skill_finished` for one-shots; explicit clear when the timer hits 0 for buffs.
5. **Wiring** — read `def.damage_shape == "none"` in `play_skill` and pull the optional buff fields from `def` (or a separate `def.buff_resource`). No buff resource = simple self-effect cast with no stat changes.

Implement when the warrior progression demands it; the hooks already exist.

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

## Loot system

| File | Purpose |
|------|---------|
| `loot/rarity_visuals.gd` | Rarity → palette index in `data/swatch_palette.json`. `color_for(rarity)` is the only API. |
| `loot/loot_drop.gd` | Visual coin drop + rarity beam. `spawn(parent, pos, rarity, item_id)` — `item_id` carries the rolled identity for future pickup. |
| `loot/loot_tables.gd` | Per-enemy drop tables. `roll_drops(enemy_id, rng) -> Array[{item_id, rarity}]`. Wired into `skeleton.gd._die()`. |
| `loot/item_metadata.gd` | Resource class — per-item `.tres` schema. |
| `loot/item_affix.gd` | Resource class — rolled-affix instance. |
| `loot/affix_db.gd` | 7 baseline affixes (4 prefix incl. new `vicious` damage_pct, 3 suffix). |
| `loot/item_editor.gd` + `.tscn` | Naming / metadata editor with live preview, swatch grid, rotation, zoom, mount/wield toggles. |
| `loot/icon_baker.gd` | Bakes per-item PNGs to `assets/generated/icons/<id>.png` (S-facing) + `assets/generated/ground/<id>.png` (death pose). |
| `loot/item_catalog_dump.gd` | `@tool` EditorScript dumper. |
| `combat.gd` | `Combat.compute_player_damage(stats, loadout, rng)` — central damage calc used at every strike site. |

**Rarity colors** (indices into `data/swatch_palette.json`):
| Rarity | Idx | Hex | |
|--------|-----|-----|-|
| COMMON | 0 | `#f5f5f5` | white |
| MAGIC | 33 | `#1854a1` | blue |
| RARE | 55 | `#efd834` | yellow-gold |
| UNIQUE | 58 | `#dc740b` | orange |
| LEGENDARY | 49 | `#c60024` | red |

### Damage formula (`combat.gd`)

```
final = (weapon_base + flat_dmg_aff) × (1 + pct_dmg_aff/100) × (1 + Str%/100)
```

- Equipped mainhand folder (`Melee3`) → item_id (`melee_3`) → `data/items/mainhand/<id>.tres`.
- Rolls within `base_damage_min..base_damage_max`.
- Sums `unique_fixed_affixes` per stat: `damage` (sharp) → flat, `damage_pct` (vicious) → multiplicative.
- Fist fallback **2-4 dmg** when no weapon equipped.
- Strike sites in `main.gd` (~line 3114) compute one `scaled_dmg` per swing, applied to skeleton/spider/goblin hits + the floating damage number.

### Drop tables

| Tier | Drop chance | Rarity skew |
|------|-------------|-------------|
| Regular skel (warrior/archer/wizard) | 45% | common-heavy |
| Elite (brute/dark_knight/berserker/dark_archer/necromancer) | 85% | magic-heavy |
| Boss (deathlord) | 100%, **3 drops** | rare/unique-heavy |

Slot weights per kind (warrior favors mainhand+shield, wizard favors robes+hoods, deathlord any-slot). Unique tier filters items_db for `is_unique=true`; falls back to rare-tier pool if no uniques exist for the slot. Drops jitter ±12 px so a 3-drop boss kill doesn't stack on one tile.

### Item naming pass

- **117 / 117 catalog entries named.** All metadata in `data/items/<slot>/<item_id>.tres`.
- **21 marked unique** (Whisperveil, Wargaze, Skyrender, Brood Mother, Stormcaller, Crown of the Lich, etc.).
- **6 stubbed** `can_drop = false`: melee_18 Pickaxe (pending mining), ranged_5 Garden Tool (pending), 5 cosmetic head entries (hair_1..5, bald).
- `head_2` ("necklace") deleted entirely; skipped via `items_db.SKIP_IDS`.
- Magic mainhands (`magic_1/2/3`) removed — they're spell-cast animations, not items. `WeaponClass.MAGIC` enum kept for future spell items.

### XP balance (slice: L1→L5 across ~3 dungeon runs)

| Enemy | XP | Level |
|-------|-----|------|
| Skel warrior / archer / wizard | 2 / 3 / 3 | 4-5 |
| Brute / Dark Knight / Berserker / Dark Archer | 18-22 | 8-9 |
| Necromancer | 28 | 10 |
| Deathlord (boss) | 80 | 14 |
| Goblin / Goblin Archer | 2 / 2 | 2-3 |
| Goblin Boss | 18 | 6 |

Level-gap bonus: `1 + (deficit-5) × 0.08`, capped at **1.5×** (was 2.5×).

### Outstanding loot work

- **Pickup not implemented** — drops linger forever. Next obvious step.
- Inventory UI / panels_ui need to consume baked icons + apply material tint + rarity glow.
- Magic / rare drops have no in-flight rolled-affix data yet; affix paths in `compute_player_damage` only honor unique fixed-affixes (no items to attach rolled affixes to until pickup lands).
- Damage numbers display now works (was a Control-vs-Node2D bug — see fix below).

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

## Outstanding

1. **Loot pickup** — drops accumulate forever; no inventory grant. Highest leverage next step.
2. **Skill effects** — Cleave / Whirlwind / Slam / Berserk / Execute only animate cooldowns.
3. **`_rebuild_character` crash** in `panels_ui.gd:540` — reparent error, not yet root-caused.
4. **Inventory UI consolidation** — `inventory_ui.gd` vs `panels_ui.gd` overlap. Task #22 (Rework Inventory panel — paper-doll + grid + gold).
5. **Magic / rare rolled affixes on drops** — paths exist in `combat.gd`, no flow yet (depends on pickup).
6. **Other classes** — only warrior wired through SkillDB / CharacterStats baselines.
7. **Dex / Energy stat effects** — currently stubbed, allocation works but no gameplay.

## Recently fixed (this session)

- Stats → HP/MP/damage all wired and visible on the HUD.
- BloodEye test enemy + spider system trimmed back.
- 85k → 15k PNGs scanned (deleted Effekseer, HD Character pack V1.2, per-frame Undead folders, Stand-alone creator runtime files).
- Skeleton refactored to spritesheet slicing (`Spritesheets/With shadow/<class>/<anim>.png`).
- Editor RID-leak crash root-caused: Godot 4.6.2 Windows accessibility bug. Disabled in `project.godot`.
- Damage numbers root-caused: was a Control parented to a Node2D rendering in screen space. Fixed via inline `_DamageNumber extends Node2D`.
- Item naming pass: 117/117 named, 21 uniques.
- Loot system structurally complete (drop tables, rarity, item metadata, naming editor, baker, beam visuals).

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
| Skills | `skill_db.gd`, `skill_def.gd`, `projectile_runtime.gd`, `dev_scenes/skill_editor.gd` |
| HUD | `combat_hud.gd/.tscn`, `hud_center_bar.gd`, `hud_skill_square.gd`, `hud_orb.gd`, `hud_stamina_bar.gd`, `hud_stone_button.gd`, `hud_ui_buttons.gd`, `icon_atlas.gd` |
| Panels | `panels_ui.gd`, `inventory_ui.gd`, `stat_stepper_btn.gd`, `inventory.gd`, `items_db.gd` |
| Editor | `editor.gd/.tscn`, `editor_overlay.gd`, `building_generator.gd` |
| Dev | `bounds_editor.gd`, `fx_test_scene.gd`, `monster_debug_panel.gd`, `world_shader_panel.gd`, `asset_placer.gd` |
