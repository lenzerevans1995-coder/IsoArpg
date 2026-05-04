extends Node2D

# Floating HP sliver above an enemy. Hides until the unit takes damage,
# then sticks around for FADE_AFTER_HIT seconds before fading out. Drawn
# at world-z high enough to clear painted tiles + tall grass.

const ArpgUI := preload("res://arpg_ui.gd")
const BAR_WIDTH := 64
const FADE_AFTER_HIT := 2.5
const Y_OFFSET := -110.0
@export var owner_node: Node = null      # the goblin we follow

var _bar: Control
var _last_seen_hp: int = -1
var _show_t: float = 0.0
var _root: Control

func _ready() -> void:
	z_index = 950
	z_as_relative = false
	top_level = true
	_root = Control.new()
	_root.position = Vector2(-BAR_WIDTH * 0.5, 0)
	_root.size = Vector2(BAR_WIDTH, 16)
	add_child(_root)
	_bar = ArpgUI.make_bar(BAR_WIDTH, "enemy")
	if _bar:
		_root.add_child(_bar)
	_root.modulate.a = 0.0

func _process(delta: float) -> void:
	if owner_node == null or not is_instance_valid(owner_node) or owner_node.get("dead"):
		_root.modulate.a = max(0.0, _root.modulate.a - delta * 4.0)
		if _root.modulate.a <= 0.01:
			queue_free()
		return
	# Follow the unit.
	global_position = (owner_node as Node2D).global_position + Vector2(0, Y_OFFSET)
	var hp: int = int(owner_node.get("hp"))
	var max_hp: int = int(owner_node.get("max_hp"))
	if _last_seen_hp == -1:
		_last_seen_hp = hp
	if hp < _last_seen_hp:
		_show_t = FADE_AFTER_HIT
	_last_seen_hp = hp
	if _show_t > 0.0:
		_show_t = max(0.0, _show_t - delta)
		_root.modulate.a = min(1.0, _root.modulate.a + delta * 4.0)
	else:
		_root.modulate.a = max(0.0, _root.modulate.a - delta * 1.5)
	if _bar and _bar.has_method("set_value"):
		_bar.call("set_value", float(hp), float(max_hp))
