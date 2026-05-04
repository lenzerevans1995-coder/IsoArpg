extends Node
class_name Inventory

# Persistent player inventory. Lives next to the loadout in user://profile.json
# under the "inventory" key:
#   {"gold": 100, "items": ["chest_2", "melee_3", ...]}
# Items are item_ids from ItemsDB.build_catalog(); equipping moves an item id
# from the items list onto the matching loadout slot (and the previously
# equipped item moves back into the items list).

const STARTING_GOLD := 50

static func get_gold(loadout: Dictionary) -> int:
	return int(loadout.get("inventory", {}).get("gold", 0))

static func set_gold(loadout: Dictionary, amount: int) -> void:
	var inv: Dictionary = loadout.get("inventory", {"gold": 0, "items": []})
	inv["gold"] = max(0, amount)
	loadout["inventory"] = inv

static func add_gold(loadout: Dictionary, delta: int) -> void:
	set_gold(loadout, get_gold(loadout) + delta)

static func get_items(loadout: Dictionary) -> Array:
	return loadout.get("inventory", {}).get("items", [])

static func add_item(loadout: Dictionary, item_id: String) -> void:
	var inv: Dictionary = loadout.get("inventory", {"gold": STARTING_GOLD, "items": []})
	if not (inv["items"] is Array):
		inv["items"] = []
	inv["items"].append(item_id)
	loadout["inventory"] = inv

static func remove_item(loadout: Dictionary, item_id: String) -> bool:
	var items: Array = get_items(loadout)
	var idx := items.find(item_id)
	if idx < 0:
		return false
	items.remove_at(idx)
	return true

static func ensure_inventory(loadout: Dictionary) -> void:
	if not loadout.has("inventory"):
		loadout["inventory"] = {"gold": STARTING_GOLD, "items": []}

# Equip an item from the inventory onto the matching loadout slot. The item
# previously occupying that slot returns to the inventory.
static func equip(loadout: Dictionary, item_id: String) -> bool:
	var item := _find_item(item_id)
	if item.is_empty():
		return false
	var layer: String = ItemsDB.SLOT_LAYER.get(item["slot"], "")
	if layer == "":
		return false
	# Remove the new item from inventory.
	if not remove_item(loadout, item_id):
		return false
	# Move the currently-equipped sheet back into the inventory as its item id.
	var current_folder: String = String(loadout.get(layer, ""))
	if current_folder != "":
		var prev_id := _id_for_folder(current_folder, item["slot"])
		if prev_id != "":
			add_item(loadout, prev_id)
	loadout[layer] = String(item["folder"])
	# For weapons, store the class so attack-anim picker can read it back.
	if item["slot"] == ItemsDB.Slot.MAINHAND:
		loadout["mainhand_class"] = int(item.get("weapon_class", ItemsDB.WeaponClass.NONE))
	return true

static func _find_item(item_id: String) -> Dictionary:
	for it in ItemsDB.build_catalog():
		if it["id"] == item_id:
			return it
	return {}

static func _id_for_folder(folder: String, slot: int) -> String:
	for it in ItemsDB.build_catalog():
		if it["slot"] == slot and it["folder"] == folder:
			return it["id"]
	return ""
