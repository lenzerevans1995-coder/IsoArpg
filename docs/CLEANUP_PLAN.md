# Cleanup Plan — 2026-05-04

Plan only; no file changes performed. Goal: untangle file organization, flag dead/duplicate code, surface doc contradictions, and stage a `scripts/<system>/` reorg for review. Vertical-slice context: half-finished systems are intentional — flagged, not judged.

Pairs with `GAME_STATE.md` (current state), `CHARACTER.md`, `WORLD.md`, `NOTES.md`.

Engine: Godot 4.6.2 stable. Main scene: `main.tscn`. No autoloads declared in `project.godot`.

---

## 1. File inventory

Grouped by purpose. Wiring column: **WIRED** = referenced from `main.tscn` / `main.gd` / scene chain, **DEV** = dev-only tool (key-toggled or standalone), **ORPHAN** = no references found, **SHELVED** = preloaded/declared but not actively used.

### Core
| File | Purpose | Wiring |
|------|---------|--------|
| `main.gd` | World gen, player spawn, dungeon gating, combat, HUD spawn, editor toggle, skill routing | WIRED |
| `main.tscn` | Root scene: Main(Node2D) → World(y_sort) + HUD(CanvasLayer) | WIRED |
| `terrain_lift.gd` | Tile role / lift / storey rules; preloaded as `TerrainLiftScript` in main | WIRED |
| `tile_rules.gd` | Tile taxonomy helpers (Ground/Water/Wall/Decor/Prop) | WIRED |
| `building_generator.gd` | Building placement helper for editor | DEV (editor) |

### Player (5 variants — only 1 actively instantiated)
| File | Purpose | Wiring |
|------|---------|--------|
| `player.gd` + `player.tscn` | Original PoC: single Sprite2D, region-rect anim | ORPHAN (PoC, kept) |
| `player_layered.gd` | Fantasy-tileset LayeredCharacter driver | WIRED — main.gd:171 instantiates `PLAYER_LAYERED_SCRIPT.new()` |
| `player_simple.gd` | Bare spritesheet fallback | ORPHAN |
| `player_longbow.gd` | Archer w/ Effekseer FX shots — "shelved while iterating on dungeon" (main.gd:169) | SHELVED |
| `player_otherworlds.gd` | PVGames OtherWorlds driver — comment at main.gd:113 calls it active, code uses layered instead | SHELVED (contradiction — see §6) |

### Character composition
| File | Purpose | Wiring |
|------|---------|--------|
| `layered_character.gd` | 13-layer Fantasy stack, live equipment swap | WIRED via player_layered |
| `layered_otherworlds_character.gd` | 7–9-layer OtherWorlds stack | SHELVED (only used by player_otherworlds) |
| `composite_character.gd` | Pre-baked OtherWorlds single sprite | SHELVED (only via player_otherworlds → composite_baker) |
| `backer_character.gd` | PVGames BackerReward kit (FemaleArcher, MaleMusketeer) | ORPHAN |
| `character_creator.gd` | Fantasy preset creator modal | SHELVED (block at main.gd:205–212 commented out) |
| `otherworlds_creator.gd` | OtherWorlds + Backer "Forge" — auto-shows on first run if no profile | DEV / first-run only |
| `composite_baker.gd` | Bakes layered → composite spritesheet | DEV (called by player_otherworlds:105) |
| `character_stats.gd` | Str/Dex/Vit/Energy + level + xp + signals; derived `max_hp/max_mp/...` | WIRED — `stats` in main.gd |
| `loadout.gd` | Slot profile + 15 presets; persists `user://profile.json` | WIRED |
| `inventory.gd` | Item container + equip/swap | PARTIAL |
| `items_db.gd` | Item catalog from StreamingAssets | PARTIAL |

### Enemies & combat
| File | Purpose | Wiring |
|------|---------|--------|
| `skeleton.gd` | 9 undead kinds, BFS path, drop loot, grant XP | WIRED (dungeon) |
| `goblin.gd` | Melee/archer goblin, peer separation | WIRED (BATTLE_WORLD spawn, currently commented at main.gd:205–212) |
| `monster.gd` | OtherWorlds_Monsters renderer | SHELVED (no spawner active) |
| `boss_monster.gd` | Medieval Bosses (cardinal+diagonal anim) | ORPHAN |
| `enemy_db.gd` | XP rewards + level-gap multiplier | WIRED |
| `arrow.gd` | Arrow projectile | WIRED (skeleton archer) |
| `attack_effect.gd` | Damage number + knockback | WIRED |
| `hit_fx.gd`, `thunder_fx.gd`, `chain_lightning_fx.gd`, `ice_spike_fx.gd`, `explosion_anim.gd`, `archer_shot_fx.gd` | Skill/projectile FX | PARTIAL — exist but not triggered by skills yet |
| `skill_db.gd` | Warrior skill registry (cooldowns, icons) | WIRED (HUD) |

### World / dungeon
| File | Purpose | Wiring |
|------|---------|--------|
| `dungeon.gd` | Procedural dungeon (BSP rooms, JSON round-trip, FIXED_SEED 1337) | WIRED |
| `portal_dialog.gd` | "Enter / leave dungeon?" modal | WIRED |

### Loot
| File | Purpose | Wiring |
|------|---------|--------|
| `loot_drop.gd` | Coin pile + rarity beam (visual only, no pickup) | WIRED |

### HUD
| File | Purpose | Wiring |
|------|---------|--------|
| `combat_hud.gd` + `combat_hud.tscn` | Bottom chrome, orbs, skill slots, XP bar | WIRED |
| `hud_center_bar.gd` | Reusable panel chrome (granite + bronze rim) | WIRED |
| `hud_skill_square.gd` | 44px slot, cooldown overlay, atlas icon | WIRED |
| `hud_orb.gd` | HP/MP globes | WIRED |
| `hud_stamina_bar.gd` | XP bar (named `Root/Stamina`) | WIRED |
| `hud_stone_button.gd` | Inset stone button (atlas icon) | WIRED |
| `hud_ui_buttons.gd` | C/I/K/M/Q/P/?/≡ button grid | WIRED |
| `hud_belt.gd` | Belt strip component | ORPHAN |
| `icon_atlas.gd` | CPU-side 64×64 icon slicer (sheet exceeds GPU max) | WIRED |
| `icon_button.gd` | Single icon button | ORPHAN |
| `fighter_bar.gd` + `fighter_bar.tscn` | Health bar component | ORPHAN |
| `arpg_ui.gd` | Sci-fi color palette constants | ORPHAN |

### Panels
| File | Purpose | Wiring |
|------|---------|--------|
| `panels_ui.gd` | I/C/K pop-up panels (inventory/character/skill tree) | WIRED — known crash at line 540 |
| `inventory_ui.gd` | Modal inventory grid | PARTIAL — overlaps panels_ui |
| `stat_stepper_btn.gd` | +/- Lucide-style buttons | WIRED |
| `boss_hp_bar.gd` | Boss HP bar | PARTIAL |
| `enemy_hp_bar.gd` | Enemy floating HP bar | WIRED |
| `monster_debug_panel.gd` | Runtime monster inspector (F9) | DEV |
| `world_shader_panel.gd` | Shader tweaker (F6) | DEV |

### Editors / tools
| File | Purpose | Wiring |
|------|---------|--------|
| `editor.gd` + `editor.tscn` | In-engine tile painter (F1) | DEV (wired) |
| `editor_overlay.gd` | Rect selection overlay for editor | DEV |
| `bounds_editor.gd` + `bounds_editor.tscn` | Collision tuning standalone | DEV (standalone scene) |
| `loot_beam_editor.gd` + `loot_beam_editor.tscn` | Rarity beam calibration | DEV (standalone scene) |
| `fx_test_scene.gd` + `fx_test_scene.tscn` | Effekseer FX harness | DEV (standalone scene) |
| `asset_placer.gd` | Asset preview placer | DEV (key toggle) |

### Shaders (13)
`pixelize.gdshader`, `pixelize_ui.gdshader`, `skill_icon_pixelize.gdshader`, `world_pixelate.gdshader`, `iso_ground.gdshader`, `flora_wind.gdshader`, `breathe.gdshader`, `fog.gdshader`, `water.gdshader`, `ripple_froth.gdshader`, `beams.gdshader`, `outline.gdshader`, `monster_painterly.gdshader`.

`iso_ground.gdshader` and `outline.gdshader` not observed in active use — verify before moving.

### Data (JSON, root)
| File | Purpose |
|------|---------|
| `gear_presets.json` | 15 color presets for Loadout |
| `swatch_palette.json` | Per-slot color swatches |
| `monster_anim_catalog.json` | OtherWorlds_Monsters anim metadata |
| `character_pieces_catalog.json` | OtherWorlds piece metadata |
| `backer_anim_catalog.json` | Backer kit anim metadata |
| `character_kit_manifest.json` | Backer kit listing |
| `tile_roles.json` | Tile taxonomy by suffix |
| `cfxr_font_glyphs.json` | Glyph mappings (likely unused — no references found) |

---

## 2. Suspected dead or duplicated code

### Player scripts — 5 variants, 1 actively running
- **Currently instantiated:** `player_layered.gd` at `main.gd:171` (`PLAYER_LAYERED_SCRIPT.new()`).
- **Comment contradiction:** `main.gd:113` says `player_otherworlds.gd` is active. **Code disagrees.** Resolve before any move.
- **Candidates for removal pending review:** `player_simple.gd`, `player_longbow.gd`, `player_otherworlds.gd`. Old PoC `player.gd` may be repurposable for authored NPCs (per user note) — keep but flag.

### Character composition — 3 layered variants
- `layered_character.gd` (Fantasy, active via player_layered)
- `layered_otherworlds_character.gd` (used only by shelved player_otherworlds)
- `composite_character.gd` (preempts layered_otherworlds when bake exists)
- **Candidate for removal pending review:** `backer_character.gd` (zero references). The other two are tied to player_otherworlds — fate depends on §6 resolution.

### Character creators — 2 implementations
- `character_creator.gd` (Fantasy) — call site at `main.gd:205–212` is fully commented out.
- `otherworlds_creator.gd` — auto-shows on first run only.
- Neither wired to a default UI button. Panels_ui covers stat editing.
- **Candidate for removal pending review:** `character_creator.gd`.

### UI — `inventory_ui.gd` vs `panels_ui.gd`
- `panels_ui.gd` defines I/C/K toggles but inventory panel content is incomplete.
- `inventory_ui.gd` is a separate modal grid with equip flow.
- Unclear which the I key opens at runtime.
- **Action needed (later, not in this pass):** decide if inventory_ui merges into panels_ui or stays as a sub-modal launched from it.

### HUD orphans (zero references in `.gd` / `.tscn`)
- `hud_belt.gd`
- `icon_button.gd`
- `fighter_bar.gd` + `fighter_bar.tscn`
- `arpg_ui.gd` (sci-fi palette — possibly kept as design template)

**Candidates for removal pending review:** all four. Move to an `archive/` folder if the user wants to retain for reference.

### Editor / test scenes — confirmed dev-only
| File | Confirmation |
|------|--------------|
| `loot_beam_editor.tscn` | Not loaded by main; opened standalone (F6/F7 in editor) |
| `fx_test_scene.tscn` | Not loaded by main; standalone harness |
| `bounds_editor.tscn` | Not loaded by main; standalone calibration scene |
| `monster_debug_panel.gd` | F9 toggle (`main.gd:617`) — gated behind key |
| `world_shader_panel.gd` | F6 toggle (`main.gd:425`) — gated behind key |
| `asset_placer.gd` | Key-toggled (~main.gd:520) |
| `editor.gd/tscn` | F1 toggle, primary dev tool |
| `composite_baker.gd` | Called on demand by player_otherworlds at startup |

All confirmed dev-only; none load during normal play unless toggled. Safe to relocate to `tools/`.

### Possibly unreferenced scripts
- `boss_monster.gd` — never instantiated.
- `cfxr_font_glyphs.json` — no `load()` / `FileAccess` reference found.
- **Candidates for removal pending review.**

---

## 3. Folder structure proposal

Source paths are project-root-relative (`C:\Users\evans\OneDrive\Desktop\2dIsoGame\`). Proposed destinations under `scripts/<system>/`. **No moves performed.**

### scripts/core/
| From | To |
|------|----|
| `main.gd` | `scripts/core/main.gd` |
| `main.tscn` | `scripts/core/main.tscn` (or keep at root — see §4) |
| `terrain_lift.gd` | `scripts/core/terrain_lift.gd` |
| `tile_rules.gd` | `scripts/core/tile_rules.gd` |

> **Note:** `main.tscn` may need to stay at root because `project.godot` declares it as the run scene with `res://main.tscn`. Moving it requires updating `project.godot` and verifying `application/run/main_scene` path.

### scripts/player/
| From | To |
|------|----|
| `player.gd` | `scripts/player/player.gd` |
| `player.tscn` | `scripts/player/player.tscn` |
| `player_layered.gd` | `scripts/player/player_layered.gd` |
| `player_simple.gd` | `scripts/player/player_simple.gd` |
| `player_longbow.gd` | `scripts/player/player_longbow.gd` |
| `player_otherworlds.gd` | `scripts/player/player_otherworlds.gd` |
| `character_stats.gd` | `scripts/player/character_stats.gd` |
| `loadout.gd` | `scripts/player/loadout.gd` |

### scripts/character/
| From | To |
|------|----|
| `layered_character.gd` | `scripts/character/layered_character.gd` |
| `layered_otherworlds_character.gd` | `scripts/character/layered_otherworlds_character.gd` |
| `composite_character.gd` | `scripts/character/composite_character.gd` |
| `backer_character.gd` | `scripts/character/backer_character.gd` |
| `character_creator.gd` | `scripts/character/character_creator.gd` |
| `otherworlds_creator.gd` | `scripts/character/otherworlds_creator.gd` |

### scripts/enemies/
| From | To |
|------|----|
| `skeleton.gd` | `scripts/enemies/skeleton.gd` |
| `goblin.gd` | `scripts/enemies/goblin.gd` |
| `monster.gd` | `scripts/enemies/monster.gd` |
| `boss_monster.gd` | `scripts/enemies/boss_monster.gd` |
| `enemy_db.gd` | `scripts/enemies/enemy_db.gd` |
| `enemy_hp_bar.gd` | `scripts/enemies/enemy_hp_bar.gd` |
| `boss_hp_bar.gd` | `scripts/enemies/boss_hp_bar.gd` |

### scripts/combat/
| From | To |
|------|----|
| `arrow.gd` | `scripts/combat/arrow.gd` |
| `attack_effect.gd` | `scripts/combat/attack_effect.gd` |
| `hit_fx.gd` | `scripts/combat/hit_fx.gd` |
| `thunder_fx.gd` | `scripts/combat/thunder_fx.gd` |
| `chain_lightning_fx.gd` | `scripts/combat/chain_lightning_fx.gd` |
| `ice_spike_fx.gd` | `scripts/combat/ice_spike_fx.gd` |
| `explosion_anim.gd` | `scripts/combat/explosion_anim.gd` |
| `archer_shot_fx.gd` | `scripts/combat/archer_shot_fx.gd` |

### scripts/dungeon/
| From | To |
|------|----|
| `dungeon.gd` | `scripts/dungeon/dungeon.gd` |
| `portal_dialog.gd` | `scripts/dungeon/portal_dialog.gd` |

### scripts/loot/
| From | To |
|------|----|
| `loot_drop.gd` | `scripts/loot/loot_drop.gd` |
| `inventory.gd` | `scripts/loot/inventory.gd` |
| `items_db.gd` | `scripts/loot/items_db.gd` |

### scripts/skills/
| From | To |
|------|----|
| `skill_db.gd` | `scripts/skills/skill_db.gd` |

### scripts/hud/
| From | To |
|------|----|
| `combat_hud.gd` | `scripts/hud/combat_hud.gd` |
| `combat_hud.tscn` | `scripts/hud/combat_hud.tscn` |
| `hud_center_bar.gd` | `scripts/hud/hud_center_bar.gd` |
| `hud_skill_square.gd` | `scripts/hud/hud_skill_square.gd` |
| `hud_orb.gd` | `scripts/hud/hud_orb.gd` |
| `hud_stamina_bar.gd` | `scripts/hud/hud_stamina_bar.gd` |
| `hud_stone_button.gd` | `scripts/hud/hud_stone_button.gd` |
| `hud_ui_buttons.gd` | `scripts/hud/hud_ui_buttons.gd` |
| `hud_belt.gd` | `scripts/hud/hud_belt.gd` (orphan — flagged) |
| `icon_atlas.gd` | `scripts/hud/icon_atlas.gd` |
| `icon_button.gd` | `scripts/hud/icon_button.gd` (orphan — flagged) |

### scripts/panels/
| From | To |
|------|----|
| `panels_ui.gd` | `scripts/panels/panels_ui.gd` |
| `inventory_ui.gd` | `scripts/panels/inventory_ui.gd` |
| `stat_stepper_btn.gd` | `scripts/panels/stat_stepper_btn.gd` |

### scripts/editors/
| From | To |
|------|----|
| `editor.gd` | `scripts/editors/editor.gd` |
| `editor.tscn` | `scripts/editors/editor.tscn` |
| `editor_overlay.gd` | `scripts/editors/editor_overlay.gd` |
| `building_generator.gd` | `scripts/editors/building_generator.gd` |
| `bounds_editor.gd` + `.tscn` | `scripts/editors/bounds_editor.{gd,tscn}` |
| `loot_beam_editor.gd` + `.tscn` | `scripts/editors/loot_beam_editor.{gd,tscn}` |
| `fx_test_scene.gd` + `.tscn` | `scripts/editors/fx_test_scene.{gd,tscn}` |
| `monster_debug_panel.gd` | `scripts/editors/monster_debug_panel.gd` |
| `world_shader_panel.gd` | `scripts/editors/world_shader_panel.gd` |

### scripts/tools/
| From | To |
|------|----|
| `composite_baker.gd` | `scripts/tools/composite_baker.gd` |
| `asset_placer.gd` | `scripts/tools/asset_placer.gd` |

### shaders/
All 13 `.gdshader` files → `shaders/`.

### data/
All 8 root `.json` files → `data/`.

### archive/ (proposed)
For files flagged dead-but-keep:
| Candidate |
|-----------|
| `arpg_ui.gd` |
| `fighter_bar.gd` + `fighter_bar.tscn` |
| `cfxr_font_glyphs.json` |

---

## 4. Reference updates required

Every move requires updating `res://` paths. Godot UID files (`.gd.uid`) usually shield against breakage **inside the editor**, but explicit `preload("res://...")` and `load("res://...")` strings are NOT auto-rewritten. All of these need manual updates after a move.

### Hard-coded `res://` paths found

**`main.gd` script preloads (high impact):**
- `PLAYER_LAYERED_SCRIPT = preload("res://player_layered.gd")` → `res://scripts/player/player_layered.gd`
- `PLAYER_OTHERWORLDS_SCRIPT = preload("res://player_otherworlds.gd")` → `res://scripts/player/player_otherworlds.gd`
- `TerrainLiftScript = preload("res://terrain_lift.gd")` → `res://scripts/core/terrain_lift.gd`
- `CombatHUD = preload("res://combat_hud.tscn")` → `res://scripts/hud/combat_hud.tscn`
- `EditorScene = preload("res://editor.tscn")` → `res://scripts/editors/editor.tscn`
- (Other preloads for skeleton, goblin, dungeon, etc. — full grep needed before move)

**`combat_hud.tscn`:**
- ExtResource paths to `hud_center_bar.gd`, `hud_skill_square.gd`, `hud_orb.gd`, `hud_stamina_bar.gd`, `hud_stone_button.gd`, `hud_ui_buttons.gd`, `combat_hud.gd`, `panels_ui.gd`, `icon_atlas.gd`, `skill_db.gd`. **All need rewriting.**

**`loot_drop.gd:42`:**
- `load("res://loot_drop.gd")` (self-load) → update to new path.

**`loot_drop.gd:84`:**
- `preload("res://skill_icon_pixelize.gdshader")` → `res://shaders/skill_icon_pixelize.gdshader`.

**`icon_atlas.gd:14`:**
- `SHEET_PATH := "res://assets/ui/Icons/64X64 DARK.png"` — does not move (assets stay).

**`dungeon.gd`:**
- JSON path: `user://draft_Dungeon.json` — user:// path, not affected by reorg.
- Wall texture loads — likely under `assets/`, not affected.

**`project.godot`:**
- `application/run/main_scene` declares the entry scene path. If `main.tscn` moves, this line must be updated.

### Recommended pre-move audit
Before any move, run:

```
grep -rn 'res://[a-zA-Z_]\+\.gd' .
grep -rn 'res://[a-zA-Z_]\+\.tscn' .
grep -rn 'res://[a-zA-Z_]\+\.gdshader' .
grep -rn 'res://[a-zA-Z_]\+\.json' .
```

Generate a complete `from → to` table; then either:
- (a) Use Godot's editor "Move" feature on each file (which updates references via UID).
- (b) Use a script to rewrite paths in one pass after batch-moving.

**Risk:** Moving while the editor is closed will break UID lookups. **Preferred path: open project, move via FileSystem dock, let Godot rewrite refs.**

---

## 5. Naming consistency issues

- All `class_name` declarations match snake_case filenames (verified — e.g., `layered_character.gd` → `LayeredCharacter`, `hud_skill_square.gd` → `HUDSkillSquare`).
- No `MainGD.gd` / `MainGD` mismatches found.

### Near-duplicate names (confusion risk)
| Pair | Risk |
|------|------|
| `layered_character.gd` ↔ `layered_otherworlds_character.gd` | Same purpose, different asset packs |
| `character_creator.gd` ↔ `otherworlds_creator.gd` | Same UX, different kits |
| `inventory.gd` ↔ `inventory_ui.gd` | Data vs UI — name doesn't make split obvious |
| `panels_ui.gd` ↔ `inventory_ui.gd` | Both UI, overlap unclear |
| `arpg_ui.gd` ↔ everything else | Vague name, orphan |
| `editor.gd` ↔ `editor_overlay.gd` ↔ `bounds_editor.gd` ↔ `loot_beam_editor.gd` | Three "editor" types — `editor.gd` is the main one |

No renames proposed in this pass — flag only.

---

## 6. Documentation hygiene

### Doc inventory (`docs/`)
- `GAME_STATE.md` — current snapshot (2026-05-03), most accurate
- `CHARACTER.md` — layered character system
- `WORLD.md` — overworld + paint editor
- `NOTES.md` — original PoC, oldest

### Outdated claims to verify
- **NOTES.md** (PoC): may describe earlier player driver, key bindings, or scene layout. Cross-check key bindings list (editor key, panels keys) against current `main.gd` `_input` handler.
- **WORLD.md**: per the user's brief, says key `1` toggles editor. Code at `main.gd:808–814` toggles editor on `KEY_F1`. **WORLD.md outdated; should say F1.**
- **CHARACTER.md**: discusses LayeredCharacter / OtherWorlds / CompositeCharacter. Verify which is described as "active" — code path is layered (Fantasy), but composite + otherworlds infrastructure remains.

### Internal contradictions
- **`main.gd:113` comment vs `main.gd:171` code:** comment says player_otherworlds is active, code instantiates player_layered. One must be wrong.
- **`GAME_STATE.md` "Player owns directly, not a separate scene"** is correct: `main.gd:171` calls `PLAYER_LAYERED_SCRIPT.new()` and adds to world.

### Missing system docs
- **LOOT.md** — loot_drop visual rules, rarity tints, hover throttling, beam calibration values. Not currently documented anywhere except inline comments + `loot_beam_editor.tscn` context.
- **SKILLS.md** — SkillDB warrior loadout, slot routing, cooldown overlay, planned but unimplemented effects.
- **HUD.md** — combat_hud structure, the granite/bronze recipe, reusable components (HUDCenterBar, HUDSkillSquare, HUDStoneButton), icon atlas constraints (GPU max texture limit workaround).
- **DUNGEON.md** — dungeon.gd generation rules, wall transparency tiers (z=110 vs z=100), draft_Dungeon.json schema, FIXED_SEED behavior.
- **BAKING.md** — composite_baker pipeline, when it runs, where its output lives.
- **EDITORS.md** — F1/F6/F9 dev-tool inventory, what each one calibrates.

---

## 7. Outstanding issues (verified file:line)

### 7.1 Damage scaling not wired
**File:** `main.gd`
- `main.gd:232` — `const PLAYER_ATTACK_DAMAGE := 14`
- `main.gd:3288` — `var skel_dmg: int = PLAYER_ATTACK_DAMAGE` (skeleton hit)
- `main.gd:3314` — `m.take_damage(PLAYER_ATTACK_DAMAGE)` (goblin hit)
- `main.gd:3321` — `_spawn_damage_number(..., PLAYER_ATTACK_DAMAGE)` (number display)
- `main.gd:3342` — `best_goblin.take_damage(PLAYER_ATTACK_DAMAGE)` (single-target)
- `main.gd:3343` — `_spawn_damage_number(..., PLAYER_ATTACK_DAMAGE)` (number display)

`stats.damage_bonus_pct()` defined in `character_stats.gd` but never called (zero references in repo). Strength allocation does not affect damage.

### 7.2 panels_ui.gd `_rebuild_character` reparent crash
**File:** `panels_ui.gd:530–542`
- Trace: `_rebuild_character()` calls `_build_character()` which routes through `_make_panel()` (`_root.add_child(panel)`).
- Error: `Can't add child '@Control@<n>' ... already has a parent`.
- Hypothesis: queue-freed panel still in tree on the same frame, OR `_build_character()` returns a node already attached from `_animate_in`. Not yet root-caused.

### 7.3 Loot pickup missing
**File:** `loot_drop.gd:1–10` (header comment confirms)
- Spawned at `skeleton.gd:625`, `goblin.gd:541`.
- No collision area, no pickup logic, no inventory grant.
- Drops persist in scene tree until scene change (potential memory growth in long sessions).

### 7.4 Skill effects are stubs
**File:** `skill_db.gd:18–60` — entries list cooldowns/icons; no damage/effect fields.
**File:** `main.gd:1986–2009` — `_activate_skill_slot(slot_key)` calls only `slot.trigger_cooldown(cd)`.
- Cleave / Whirlwind / Slam / Berserk / Execute animate cooldown only.
- Existing FX scripts (chain_lightning_fx.gd, ice_spike_fx.gd, etc.) never invoked from skill flow.

### 7.5 FIXED_SEED in dungeon.gd
**File:** `dungeon.gd:49` — `const FIXED_SEED := 1337`
- `dungeon.gd:62` — used unless caller passes nonzero `seed_value`.
- Intentional for testing; will produce same dungeon on every run if shipped.

### 7.6 NO_GEN kill-switch
**File:** `main.gd:226` — `const NO_GEN := true`
- `main.gd:1408` — `if NO_GEN: loaded_chunks[cv] = sprites; return` short-circuits all procedural overworld decoration.
- Intentional for current testing; would result in empty world if shipped as-is.

### 7.7 Other flags also intentional but ship-risky
- `main.gd:24` — `BATTLE_WORLD := true`
- `main.gd:220` — `MINIMAL_GEN := true`
- All three (`BATTLE_WORLD`, `MINIMAL_GEN`, `NO_GEN`) are dev toggles. Consolidate into a single `DEV_FLAGS` block or move to a config file before ship.

---

## 8. Risk flags

### Hardcoded debug values (intentional but ship-risky)
- `main.gd:24` — `BATTLE_WORLD := true`
- `main.gd:220` — `MINIMAL_GEN := true`
- `main.gd:226` — `NO_GEN := true`
- `dungeon.gd:49` — `FIXED_SEED := 1337`

### Print statements (debug leftovers vs intentional logs)
- `skeleton.gd:622–628` — three `print()` calls per death tracing loot drop. Likely debug leftover.
- `player_layered.gd:120–126` — manual lift adjustment debug (every keypress).
- `editor.gd:970, 1839, 1962` — save/load confirmations. Intentional.
- `bounds_editor.gd:162–168` — calibration output. Intentional (dev tool).
- `archer_shot_fx.gd:171, 260` — gated behind `if DEBUG_FX:`. Intentional.
- `otherworlds_creator.gd:729–734` — kit selection logging. Likely debug leftover.

### Large commented-out blocks (≥10 lines)
- `main.gd:205–212` — goblin spawn + character_creator block fully commented. Comment explains: paused while iterating dungeon. Intentional but ship-risky.

### TODO / FIXME comments
- `main.gd:1986` — "(TODO) routes to actual skill behaviour" (skill_db routing).
- Other TODOs sparse — full grep recommended before ship.

### Empty error handlers
- None found in core scripts (`pass\s+#` pattern returned nothing in spot-check). Verify with full grep before ship.

### Performance concerns (already partially mitigated)
- User reports recurring lag. Mitigations already applied: skeleton sleep, cloud drift pause, loot hover 10 Hz, icon atlas latch, `_main_ref` caching.
- Suspected remaining cost: `VIEW_RADIUS_CHUNKS = 2` chunk streaming + y_sort recalc on chunk load.
- Not blocking; flagged for profiling later.

---

## Summary counts

- **Files at root (excluding addons/, assets/, tools/, docs/):**
  - `.gd` ≈ 62
  - `.tscn` ≈ 8
  - `.gdshader` = 13
  - `.json` = 8
- **Flagged possibly dead / orphaned:** ~10 files
  - `player_simple.gd`, `player_longbow.gd`, `player_otherworlds.gd` (shelved)
  - `backer_character.gd`, `boss_monster.gd`
  - `hud_belt.gd`, `icon_button.gd`, `fighter_bar.gd` + `fighter_bar.tscn`, `arpg_ui.gd`
  - `cfxr_font_glyphs.json`
- **Reference updates required to do the proposed move:** ~30+ `res://` path strings inside `.gd` and `.tscn` files. Plus `project.godot` `main_scene` line if `main.tscn` moves.
