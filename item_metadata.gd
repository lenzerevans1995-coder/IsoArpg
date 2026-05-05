extends Resource
class_name ItemMetadata

# Per-item metadata, layered on top of items_db.gd's runtime catalog.
# One .tres file per item lives under res://data/items/<slot>/<item_id>.tres.
# Items without a matching .tres still appear in-game via runtime fallback
# (display name = "<slot> <item_id>" until the editor fills them in).

# --- Identity (matches the items_db catalog entry) ---
@export var item_id: String = ""               # "sword_3", "chest_12", "mount_2"…
@export var slot: int = 0                      # ItemsDB.Slot enum value
@export var weapon_class: int = 0              # ItemsDB.WeaponClass enum value

# --- Display ---
@export var base_name: String = ""             # e.g. "Curved Blade". Empty -> fallback.

# --- Drop characteristics ---
@export_group("Drop")
@export var can_drop: bool = true              # false = creator-only, never rolls as loot
@export var drop_weight: float = 1.0           # relative chance vs other items in same slot
@export var min_zone_level: int = 1
@export var max_zone_level: int = 999

# --- Base stats (weapons + armor share this resource; only fields relevant
# to the slot get used at runtime) ---
@export_group("Base Stats")
@export var base_damage_min: int = 0
@export var base_damage_max: int = 0
@export var base_attack_speed: float = 1.0
@export var base_armor: int = 0

# --- Affixes allowed to roll on this item ---
@export_group("Affix Rolls")
@export var allowed_prefixes: Array[String] = []
@export var allowed_suffixes: Array[String] = []

# --- Unique override (only used when is_unique = true) ---
@export_group("Unique")
@export var is_unique: bool = false
@export var unique_name: String = ""           # replaces generated name
@export var unique_glow_color: Color = Color.WHITE
@export var unique_flavor_text: String = ""
@export var unique_fixed_affixes: Array[ItemAffix] = []

# --- Icon render config (for the icon baker) ---
@export_group("Icon")
@export var icon_render_direction: String = "SE"
@export var icon_render_anim: String = "Idle"
@export var icon_render_frame: int = 0
