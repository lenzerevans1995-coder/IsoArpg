extends CanvasLayer

# Top-of-screen boss HP bar. Auto-binds to the first goblin in
# main.goblins where is_boss == true, hides when it's gone.

const ArpgUI := preload("res://arpg_ui.gd")

var _bar: Control
var _name_lbl: Label
var _hp_lbl: Label
var _root: Control
var _bound: Node = null

func _ready() -> void:
	layer = 39
	_root = ArpgUI.make_scaled_root(self)

	# Bar is 70% of screen width, hugs the top edge.
	var holder := Control.new()
	holder.anchor_top = 0.0
	holder.anchor_bottom = 0.0
	holder.anchor_left = 0.5
	holder.anchor_right = 0.5
	holder.offset_left = -360
	holder.offset_right = 360
	holder.offset_top = 18
	holder.offset_bottom = 78
	_root.add_child(holder)

	_name_lbl = ArpgUI.styled_label("", 18, Color(1.0, 0.85, 0.55))
	_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_lbl.anchor_left = 0.0
	_name_lbl.anchor_right = 1.0
	_name_lbl.offset_top = 0
	_name_lbl.offset_bottom = 22
	holder.add_child(_name_lbl)

	_bar = ArpgUI.make_bar(720, "boss")
	if _bar:
		_bar.position = Vector2(0, 22)
		holder.add_child(_bar)

	_hp_lbl = ArpgUI.styled_label("", 12, Color(1, 0.9, 0.7))
	_hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_lbl.anchor_left = 0.0
	_hp_lbl.anchor_right = 1.0
	_hp_lbl.offset_top = 44
	_hp_lbl.offset_bottom = 60
	holder.add_child(_hp_lbl)

	_root.visible = false

func _process(_dt: float) -> void:
	ArpgUI.sync_scaled_viewport(self)
	# Re-bind every frame so dying / re-spawning bosses transition cleanly.
	var main := get_tree().root.get_node_or_null("Main")
	if main == null or not ("goblins" in main):
		_root.visible = false
		return
	var boss = null
	for g in main.goblins:
		if g != null and is_instance_valid(g) and not g.dead and "is_boss" in g and g.is_boss:
			boss = g
			break
	if boss == null:
		_root.visible = false
		_bound = null
		return
	if boss != _bound:
		_bound = boss
		_name_lbl.text = "GOBLIN WARLORD"
	_root.visible = true
	if _bar and _bar.has_method("set_value"):
		_bar.call("set_value", float(boss.hp), float(boss.max_hp))
	if _hp_lbl:
		_hp_lbl.text = "%d / %d" % [int(boss.hp), int(boss.max_hp)]
