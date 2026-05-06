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

# Reserved for combat wiring (post-slice). Damage multiplier applied
# to the player's base damage when this skill is the active one.
@export var damage_mult: float = 1.0
