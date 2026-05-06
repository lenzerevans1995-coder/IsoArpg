extends Node2D

# Standalone tool: click a button on the left to fire that FX at the
# center of the viewport. Mash repeatedly to A/B effect tweaks. Open
# this scene and F6 — no game state needed.
#
# Add a new entry to FX_LIST when you ship a new effect script.

const FX_LIST: Array = [
	# {"label": "...", "kind": "hit"|"thunder"|"explosion"|"attack_effect", "args": {...}}
	{"label": "Hit Pop (POW!)",      "kind": "hit"},
	{"label": "Hit (CRIT, red)",     "kind": "hit", "text": "CRIT", "color": Color(1.0, 0.30, 0.30)},
	{"label": "Thunder Strike",      "kind": "thunder"},
	{"label": "Thunder (big)",       "kind": "thunder", "scale": 1.2},
	{"label": "Attack Slash 1",      "kind": "attack_effect", "set": "Slash1", "anim": "Attack1"},
	{"label": "Attack Slash 2",      "kind": "attack_effect", "set": "Slash2", "anim": "Attack2"},
	{"label": "Attack Magic 1",      "kind": "attack_effect", "set": "Magic1", "anim": "Special1"},
]

var _preview_root: Node2D
var _info_label: Label

func _ready() -> void:
	# Background so the FX has something to render against.
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.11, 0.13)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)
	# Spawn point indicator (where every FX fires).
	_preview_root = Node2D.new()
	_preview_root.position = get_viewport_rect().size * 0.5
	add_child(_preview_root)
	var marker := Sprite2D.new()
	marker.modulate = Color(1, 1, 1, 0.15)
	add_child(marker)
	# Button column on the left.
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8)
	panel.custom_minimum_size = Vector2(220, 0)
	add_child(panel)
	var col := VBoxContainer.new()
	panel.add_child(col)
	var title := Label.new()
	title.text = "FX Preview"
	title.add_theme_font_size_override("font_size", 16)
	col.add_child(title)
	for entry in FX_LIST:
		var b := Button.new()
		b.text = String(entry.get("label", "(unnamed)"))
		b.pressed.connect(_fire.bind(entry))
		col.add_child(b)
	# Footer info.
	var hint := Label.new()
	hint.text = "Click anywhere in viewport to set spawn point"
	hint.add_theme_font_size_override("font_size", 10)
	hint.modulate = Color(0.7, 0.7, 0.75)
	col.add_child(hint)
	_info_label = Label.new()
	_info_label.text = "(no FX fired)"
	_info_label.add_theme_font_size_override("font_size", 11)
	_info_label.modulate = Color(0.6, 0.85, 0.55)
	col.add_child(_info_label)

func _input(event: InputEvent) -> void:
	# Click in the viewport (outside the button panel) to move the
	# spawn marker. Lets you preview FX in different positions /
	# against parallax / etc.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mb: InputEventMouseButton = event
		if mb.position.x > 240:
			_preview_root.position = mb.position

func _fire(entry: Dictionary) -> void:
	var pos: Vector2 = _preview_root.position
	var kind: String = String(entry.get("kind", ""))
	match kind:
		"hit":
			var Hit := preload("res://hit_fx.gd")
			var text: String = String(entry.get("text", "POW!"))
			var color: Color = entry.get("color", Color(1, 0.85, 0.4))
			Hit.spawn(self, pos, text, color)
		"thunder":
			var Thunder := preload("res://thunder_fx.gd")
			var sm: float = float(entry.get("scale", 0.6))
			Thunder.spawn(self, pos, sm)
		"attack_effect":
			var AE := preload("res://attack_effect.gd")
			var fx: Node2D = AE.new()
			fx.set("effect_set", String(entry.get("set", "Slash1")))
			fx.set("anim_name", String(entry.get("anim", "Attack1")))
			fx.set("direction", 2)
			add_child(fx)
			fx.global_position = pos
		"explosion":
			var Ex := preload("res://explosion_anim.gd")
			Ex.spawn(self, pos, String(entry.get("folder", "")))
		_:
			_info_label.text = "Unknown kind: %s" % kind
			return
	_info_label.text = "Fired: %s" % String(entry.get("label", ""))
