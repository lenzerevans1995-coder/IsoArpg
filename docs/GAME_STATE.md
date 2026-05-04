# Game State Snapshot — 2026-05-03

A single-file map of where the project actually is, so future ideas can be slotted against it without re-reading the whole codebase. Pairs with `CHARACTER.md`, `WORLD.md`, `NOTES.md` (older topical docs).

---

## Engine / Project

- Godot 4.6.2 stable, GDScript, Windows.
- Entry scene: `main.tscn` (script `main.gd`).
- Pixel-art project, integer offsets, snap-to-pixel pipeline; custom `pixelize` / `world_pixelate` shaders for global feel.
- `NO_GEN := true` kill-switch in main: procedural overworld generator does **not** populate on startup. Only manually painted tiles + Layer 2 path preset (A1 dirt, grass edges, I1–I10 mud) appear.
- Player start hard-coded to cell `(1, -36)`.

---

## Overworld

- Iso tilemap with two layers (ground + decoration). Path tool retired; current path is a saved preset placed by the editor.
- Long grass / Flora B is the only destructible foliage (short grass left static).
- Clouds, fog, water, ripple_froth shaders running. Cloud drift + chunk updates **suspended** while in dungeon (perf).
- Portal interaction: **Q** opens "Enter dungeon?" (`portal_dialog.gd`). Inside dungeon, **ESC** opens "Leave?".

## Dungeon (`dungeon.gd`)

- Procedural, fixed `FIXED_SEED = 1337` for repeatability.
- 7–11 rooms + 1 boss room, BSP-ish, connected by corridors.
- Persistence: full round-trip to `draft_Dungeon.json` (floor cells, walls, transparent walls, spawn, props).
- Walls:
  - **Wall A1** straight pieces with `_N / _E / _S / _W` suffix variants.
  - **Wall A2** corner pieces, only at outer corners (cells with two cardinal voids).
  - Opaque (`_N / _W`) at `z = 110`; transparent south/east (`_S / _E`) at `z = 100` so player + enemies render in front.
- Skeletons get a darker tint when behind transparent walls (footprint check 6 cells south of foot).
- World tree set to `PROCESS_MODE_DISABLED` while dungeon is active.

---

## Player

- `main.gd` owns the player directly (not a separate scene). 8-direction iso animation.
- Constants still in main: `PLAYER_MAX_HP = 100`, `PLAYER_MAX_MP = 50`, `PLAYER_ATTACK_DAMAGE = 14`.
- HP/MP **max** now read live from `stats.max_hp() / stats.max_mp()` via `combat_hud.set_player_stats(...)`.
- **Damage scaling NOT yet wired** — `PLAYER_ATTACK_DAMAGE` is still a flat constant; `stats.damage_bonus_pct()` is computed but unused at the strike sites (~main.gd:3164 spider, ~3282 skeleton).

### CharacterStats (`character_stats.gd`)

- RefCounted. Per-class baseline init (`_init("warrior")`).
- Primary: Str / Dex / Vit / Energy. Meta: level, xp, unspent_stat_points, unspent_skill_points.
- Derived methods: `max_hp()`, `max_mp()`, `attack_rating()`, `defense()`, `damage_bonus_pct()`.
- XP curve: `XP_BASE * 1.18^(L-1) * (1 + 0.4L)` (polynomial, snowballs late).
- `add_xp()` cascades level-ups: +5 stat points, +1 skill point per level. Emits `xp_changed`, `hp_changed`, `mp_changed`, `level_changed`.

### Skill DB (`skill_db.gd`)

Warrior loadout currently bound to combat_hud slots:

| Slot | Skill            | Icon | CD   |
|------|------------------|------|------|
| RMB  | warrior_basic    | 03   | 0.4  |
| 1    | warrior_cleave   | 21   | 3.0  |
| 2    | warrior_whirlwind| 06   | 6.0  |
| 3    | warrior_slam     | 08   | 2.5  |
| 4    | warrior_berserk  | 30   | 14.0 |
| 5    | warrior_execute  | 28   | 8.0  |

- Hotkeys 1–5 + RMB route through `_activate_skill_slot` → `slot.trigger_cooldown(cd)`.
- Cooldown overlay (dark sweep + yellow flash) implemented in `hud_skill_square.gd`.
- **Skill *effects* not implemented** — only basic attack does damage; the others just animate cooldown.

---

## Enemies

### Skeletons (`skeleton.gd`)

9 kinds from "2D HD Undead pack 1", spawned via factory `Skeleton.make(kind_id, target)`.

- Sleep at distance (>1100px) for perf.
- BFS pathfinding against `floor_cells`, repath gated on player cell change or 1.2s timeout.
- Strict wall collision (no clipping into wall cells).
- `_main_ref` cached once (avoids `get_tree().root.get_node_or_null("Main")` every tick).
- Drops loot via `LootDrop.spawn(parent, world_pos, rarity)`.
- On death: grants XP via `EnemyDB.id_for_skeleton_kind(kind)` → `main.stats.add_xp(amount)`.

Class abilities:
- **Brute** — slam.
- **Dark Knight** — riposte.
- **Berserker** — rage state.
- **Dark Archer** — shadow-step.
- **Necromancer** — revives downed skeletons.
- **Deathlord** (boss) — 3 phases + Death Cry AoE.
- **Wizard** — zoner (ranged AoE).
- **Archer** — kite + arrows via `arrow.gd`.

### Goblins / Spiders / Boss

- `goblin.gd`, `monster.gd`, `boss_monster.gd` exist; goblins/spiders are the older overworld threats.
- `EnemyDB`: skel_warrior 28xp, skel_archer 32, skel_wizard 38; elites 220–320; Deathlord 1800; goblin 14, goblin_archer 18, boss 220. Level-gap multiplier dwindles XP past +5 levels.

---

## Loot (`loot_drop.gd`)

- Static coin pile sprite (`coins_drop.png`), scale 1.0, pixelize shader at `pixel_size = 1.1`.
- Code-drawn rarity beam (`_BeamNode`): three stacked rects (glow/mid/core), width 3.5, height 160, offset Y 83.
- Rarity tints (modulates a yellow base): COMMON white, MAGIC blue, RARE gold, UNIQUE orange, LEGENDARY red.
- Random rarity weighted: 65% common, 20% magic, 10% rare, 4% unique, 1% legendary.
- Hover detection throttled to 10 Hz; beam alpha bumps on hover, gold stays static.
- **No pickup yet** — drops linger forever until a future loot system collects them.

---

## UI / HUD

### Bottom HUD (live)

- Granite + warm-grey "stage" with brushed-bronze rim, gold pinstripe, dark cavity, white-spec corner rivets — the visual recipe other panels must match.
- Reusable parts:
  - `hud_center_bar.gd` — panel chrome.
  - `hud_skill_square.gd` — 44px slot, axis-aligned or rotated to diamond. Inspector knobs for icon col/row, linear_index, fill, greyed, pixel_size (defaults to 9.0). Cooldown overlay built in.
  - `hud_stone_button.gd` — small inset stone button, sinks 1px on press, accepts atlas icons.
  - `hud_orb.gd` — HP/MP globes.
  - `hud_belt.gd`, `hud_stamina_bar.gd` — XP/stamina bar.
- Slot labels: RMB / 1 / 2 / 3 / 4 / 5.
- XP bar bound to `Root/Stamina` node, value = `xp / xp_for_next_level`.

### Pop-up panels (`panels_ui.gd`)

- Toggles: **I** inventory, **C** character, **K** skill tree.
- Character panel reads live from `main.stats`; allocate-stat `+` buttons write back via `_allocate_stat_point`.
- `StatStepperBtn` (`stat_stepper_btn.gd`) — Lucide-style +/- drawn in code, pixelized at 2.0. Rounded line caps removed (caused white-dot artifacts under the pixelize shader).
- **Known recurring error**: `panels_ui.gd:540 _rebuild_character` → "Can't add child, already has a parent". Root cause not yet identified. Trace points into `_make_panel`'s `_root.add_child(panel)`.

### Icon system (`icon_atlas.gd`)

- Sheet `assets/ui/Icons/64X64 DARK.png` is 1024×22464 — exceeds the 16384 GPU texture limit on many cards.
- Workaround: `FileAccess.get_file_as_bytes` + `Image.load_png_from_buffer` keeps the sheet on the CPU; each 64×64 cell sliced into its own `ImageTexture` on demand and cached.
- `_load_failed` latch + smoke-test (probe region + ImageTexture creation) prevents per-frame retries that previously froze Godot.

### Shaders

`pixelize`, `pixelize_ui`, `skill_icon_pixelize`, `world_pixelate`, `iso_ground`, `flora_wind`, `fog`, `water`, `ripple_froth`, `beams`, `breathe`, `outline`, `monster_painterly`.

---

## Editor / Tools

- `editor.tscn` / `editor.gd` — main tile editor (F1).
- `loot_beam_editor.tscn` — calibration scene for the rarity beam (used to lock width 3.5 / height 160 / offset 83).
- `bounds_editor.tscn`, `fx_test_scene.tscn`, `monster_debug_panel.gd` — auxiliary tooling.
- Asset placer (`asset_placer.gd`), composite baker (`composite_baker.gd`) for character generation.

---

## Performance Mitigations Applied

- World tree disabled while in dungeon.
- Cloud drift / chunk updates skipped in dungeon mode.
- Skeleton sleep at distance + cell-gated repathing.
- Loot hover throttled to 10 Hz.
- Icon atlas load failure latched.
- Skeleton `_main_ref` cached.

Open: user has reported lag again as recently as this session; not yet definitively root-caused.

---

## Outstanding / Next-Up

1. **Stats → damage**: hook `stats.damage_bonus_pct()` into the player attack damage at the strike sites.
2. **Reparent crash** in `_rebuild_character` — investigate `_make_panel` / `HUDCenterBarScript.new()` parenting.
3. **Skill effects** — Cleave / Whirlwind / Slam / Berserk / Execute currently only animate cooldowns; need real combat logic.
4. **Loot pickup** — drops accumulate forever; need an inventory grab path.
5. **Other classes** — only warrior is wired through SkillDB and CharacterStats baselines.
6. **Panel system pass** — inventory / character / skill-tree pop-ups planned (see latest design doc); only character is partially live.

---

## File Map (the ones that matter)

| Area | Files |
|------|-------|
| Core | `main.gd`, `main.tscn` |
| Player | `player.gd`, `player_layered.gd`, `composite_character.gd`, `character_stats.gd` |
| Enemies | `skeleton.gd`, `goblin.gd`, `monster.gd`, `boss_monster.gd`, `enemy_db.gd` |
| Combat FX | `arrow.gd`, `attack_effect.gd`, `chain_lightning_fx.gd`, `ice_spike_fx.gd`, `thunder_fx.gd`, `explosion_anim.gd`, `hit_fx.gd` |
| Dungeon | `dungeon.gd`, `portal_dialog.gd` |
| Loot / items | `loot_drop.gd`, `loot_beam_editor.gd`, `inventory.gd`, `items_db.gd`, `loadout.gd` |
| Skills | `skill_db.gd` |
| HUD | `hud_center_bar.gd`, `hud_skill_square.gd`, `hud_stone_button.gd`, `hud_orb.gd`, `hud_belt.gd`, `hud_stamina_bar.gd`, `combat_hud.gd`, `combat_hud.tscn` |
| Panels | `panels_ui.gd`, `stat_stepper_btn.gd`, `icon_atlas.gd` |
| Editors | `editor.gd`, `bounds_editor.gd`, `loot_beam_editor.gd`, `fx_test_scene.gd` |
