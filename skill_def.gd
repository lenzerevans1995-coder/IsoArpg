extends Resource
class_name SkillDef

# A skill definition — what the player binds to a hotbar slot.
# Saved per-skill at res://data/skills/<skill_id>.tres.
#
# Composition: a body trigger anim, up to two VFX overlay folders
# (effect_a + effect_b), an optional slash trail, and per-layer color
# modulates picked from the 81-swatch palette.

@export var skill_id: String = ""             # "lightning_burst", etc.
@export var display_name: String = ""

# Body anim played when this skill fires (Attack1..5, Special1, etc.).
# The chosen effect/slash sheets play their matching <anim>.png in sync.
@export var trigger_anim: String = "Attack1"

# Effect overlay folders (Effect1-5, Slash1-2, Magic1-3, or "" for none).
# vfx layer plays effect_a; vfx2 plays effect_b. Two simultaneous
# overlays so combos like 'Magic1 (aura) + Effect3 (cast burst)'
# render together.
@export var effect_a_folder: String = ""
@export var effect_b_folder: String = ""

# Slash trail folder (Slash1 / Slash2 / "") — plays on the dedicated
# slash layer so it can be tinted independently of the body weapon.
@export var slash_folder: String = ""

# Per-layer color tints. Each effect gets its own color so two
# overlays in a single skill can read distinctly (e.g. Magic1 aura in
# blue + Effect3 burst in white). Pulled from the 81-swatch palette
# via the skill editor.
@export var effect_a_color: Color = Color.WHITE
@export var effect_b_color: Color = Color.WHITE
@export var slash_color: Color = Color.WHITE

# World-space flipbook FX (Fantasy tileset Effects/ subfolders — AoE,
# Bolt, Buff*, Cone, Dash, Hook, LevelUp). Spawned at the player's
# foot when the skill fires, plays once via explosion_anim.gd, then
# despawns. Empty = no world fx.
# Stored as the subfolder name only (e.g. "AoE"). Full path is
# resolved at runtime against FANTASY_FX_ROOT in skill_def.gd.
@export var world_fx_folder: String = ""
@export var world_fx_color: Color = Color.WHITE

# Root path for Fantasy tileset effect frames. Caller resolves
# `world_fx_folder` against this to find the .png frames.
const FANTASY_FX_ROOT := "res://assets/tilesets/Fantasy tileset - 2D Isometric V1.1/Fantasy tileset - 2D Isometric/Animations/Effects"

static func world_fx_full_path(subfolder: String) -> String:
	if subfolder == "":
		return ""
	return "%s/%s" % [FANTASY_FX_ROOT, subfolder]

# Damage multiplier applied to the player's computed base damage
# when this skill fires.
@export var damage_mult: float = 1.0

# Projectile (Phase 2-4 add). Resolved at runtime by projectile_runtime.gd
# against `data/projectiles.json`. Empty pack/name = no projectile.
#
# motion modes:
#   at_player  - plays at the player's position (cast aura, self-buff fx)
#   at_target  - plays at the cursor / nearest enemy on impact (AoE, slam)
#   travel     - flies from player to target (arrow, bolt, magic missile)
#   arc_rain   - drops N copies in a spread radius around target (arrow rain)
@export var projectile_pack: String = ""        # "pack1" / "pack2" / "hd1"
@export var projectile_category: String = ""    # "Arrow Sprites" / "Spells" / "AoE" ...
@export var projectile_name: String = ""        # subfolder name
@export_enum("at_player", "at_target", "travel", "arc_rain") var projectile_motion: String = "travel"
@export var projectile_color: Color = Color.WHITE
@export var projectile_start_frame: int = 0     # trim head — first frame index played
@export var projectile_end_frame: int = -1      # trim tail — last frame; -1 = full length
@export var projectile_fps: float = 24.0
@export var projectile_speed: float = 220.0     # px/sec for 'travel' mode
@export var projectile_arc_count: int = 8       # number of drops for arc_rain
@export var projectile_arc_radius: float = 120.0 # spread for arc_rain
# Configurable spawn / impact offsets — the skill editor exposes these
# as draggable blue (origin) and red (target) markers in the preview
# stage. Origin is added to the caster's position; target is added to
# the cursor / true target before motion logic runs.
@export var projectile_origin_offset: Vector2 = Vector2.ZERO
@export var projectile_target_offset: Vector2 = Vector2.ZERO
# Render scale applied to the projectile flipbook. 0.5 matches the
# 64-px-character demo (sources are typically 128 px; 0.5 = 64). Bump
# to 1.0 for huge AoEs that should fill the screen.
@export var projectile_scale: float = 0.5

# Damage shape — controls who gets hit when the skill lands.
# 'cone'    : forward cone, angle = damage_angle_deg, range = damage_range
# 'circle'  : full 360° around the player, range = damage_range
# 'single'  : only the nearest enemy in front within damage_range
# 'none'    : no damage (self-buff skills like Berserk)
@export_enum("cone", "circle", "single", "none") var damage_shape: String = "cone"
@export var damage_range: float = 110.0       # px
@export var damage_angle_deg: float = 90.0    # full cone width (cone only)
# Offset of the damage-area center from the caster's position. Lets a
# skill drop its hitbox in front / beside / behind the player rather
# than always centered on the body. Configured visually in the skill
# editor by dragging the red shape overlay.
@export var damage_offset: Vector2 = Vector2.ZERO
# End / reach point of the damage area, relative to the caster's
# position. Together with damage_offset (start), the editor draws a
# draggable START + END pair that defines the cone's length and
# direction. damage_range is auto-derived from |end - start|.
@export var damage_end_offset: Vector2 = Vector2(110, 0)
