extends RefCounted
class_name SkillDB

# Central registry for skills. Add new entries to ENTRIES — each row is
# self-describing (id, name, class, icon path, hotbar slot, cooldown,
# placeholder for future damage/AP costs). UI code looks up by id; the
# skill bar reads `default_slot` to wire the right icon to the right
# hotbar key on init.

# Hotbar slot codes — keep aligned with the relabeled bar
# (RMB / 1 / 2 / 3 / 4 / 5).
enum Slot { RMB, K1, K2, K3, K4, K5 }

const ICON_ROOT_WARRIOR := "res://assets/SkillIcons/Warrior"

# All skills, keyed by id.
const ENTRIES := {
	"warrior_basic": {
		"name": "Basic Attack",
		"class": "warrior",
		"icon": ICON_ROOT_WARRIOR + "/Warriorskill_03_nobg.png",
		"default_slot": Slot.RMB,
		"cooldown": 0.4,        # quick GCD-style swing
	},
	"warrior_cleave": {
		"name": "Cleaving Strike",
		"class": "warrior",
		"icon": ICON_ROOT_WARRIOR + "/Warriorskill_21_nobg.png",
		"default_slot": Slot.K1,
		"cooldown": 3.0,
	},
	"warrior_whirlwind": {
		"name": "Whirlwind",
		"class": "warrior",
		"icon": ICON_ROOT_WARRIOR + "/Warriorskill_06_nobg.png",
		"default_slot": Slot.K2,
		"cooldown": 6.0,
	},
	"warrior_slam": {
		"name": "Slam",
		"class": "warrior",
		"icon": ICON_ROOT_WARRIOR + "/Warriorskill_08_nobg.png",
		"default_slot": Slot.K3,
		"cooldown": 2.5,
	},
	"warrior_berserk": {
		"name": "Berserk",
		"class": "warrior",
		"icon": ICON_ROOT_WARRIOR + "/Warriorskill_30_nobg.png",
		"default_slot": Slot.K4,
		"cooldown": 14.0,
	},
	"warrior_execute": {
		"name": "Execute",
		"class": "warrior",
		"icon": ICON_ROOT_WARRIOR + "/Warriorskill_28_nobg.png",
		"default_slot": Slot.K5,
		"cooldown": 8.0,
	},
}

static func get_skill(id: String) -> Dictionary:
	return ENTRIES.get(id, {})

static func icon_for(id: String) -> Texture2D:
	var entry: Dictionary = ENTRIES.get(id, {})
	var path: String = String(entry.get("icon", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path)

# Returns id → entry filtered by class + sorted by default_slot.
# `class_id` (NOT `class_name` — that's a GDScript keyword).
static func loadout_for_class(class_id: String) -> Array:
	var out: Array = []
	for id in ENTRIES.keys():
		var e: Dictionary = ENTRIES[id]
		if String(e.get("class", "")) == class_id:
			out.append({"id": id, "entry": e})
	out.sort_custom(func(a, b):
		return int(a.entry.get("default_slot", 0)) < int(b.entry.get("default_slot", 0)))
	return out

# Skill ids assigned to each hotbar slot for a given class. Index 0 = RMB,
# 1..5 = number keys. Empty string when nothing is bound.
static func default_bar_for_class(class_id: String) -> Array:
	var bar: Array = ["", "", "", "", "", ""]
	for entry in loadout_for_class(class_id):
		var slot: int = int(entry.entry.get("default_slot", 0))
		if slot >= 0 and slot < bar.size():
			bar[slot] = String(entry.id)
	return bar
