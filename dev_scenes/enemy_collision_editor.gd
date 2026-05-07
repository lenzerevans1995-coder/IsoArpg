extends Control

# Visual editor for per-kind enemy collision capsules.
# Pick a Skeleton.Kind from the dropdown — the editor draws that
# class's idle-frame at the live `sprite_scale`, overlays the capsule
# in red, and lets you drag the four handles (top, bottom, left, right)
# to resize. Use the SpinBoxes for fine numerical control. The Save
# button writes data/enemy_presets.json which Skeleton reads at runtime.

const PRESETS_PATH := "res://data/enemy_presets.json"
const KIND_LIST := [
	"WARRIOR", "ARCHER", "WIZARD", "BRUTE", "DEATHLORD",
	"DARK_KNIGHT", "BERSERKER", "DARK_ARCHER", "NECROMANCER",
]
const CLASS_FOLDERS := {
	"WARRIOR": "6Warrior", "ARCHER": "5Archer", "WIZARD": "9Wizard",
	"BRUTE": "1Brute", "DEATHLORD": "2DeathLord",
	"DARK_KNIGHT": "3DarkKnight", "BERSERKER": "4Berserker",
	"DARK_ARCHER": "7DarkArcher", "NECROMANCER": "8Necromancer",
}
const PACK_BASE := "res://assets/charachters/Sprites/2D HD Undead pack 1/2D HD Undead pack 1/Spritesheets/With shadow"

@onready var stage: Control = Control.new()
@onready var sprite: Sprite2D = Sprite2D.new()
@onready var capsule_view: Node2D = Node2D.new()
@onready var kind_picker: OptionButton = OptionButton.new()
@onready var spin_x: SpinBox = SpinBox.new()
@onready var spin_y: SpinBox = SpinBox.new()
@onready var spin_r: SpinBox = SpinBox.new()
@onready var spin_h: SpinBox = SpinBox.new()
@onready var spin_scale: SpinBox = SpinBox.new()
@onready var spin_zoom: SpinBox = SpinBox.new()
@onready var status: Label = Label.new()

var _data: Dictionary = {}     # kind_index_str -> {scale, cap{x,y,r,h}}
var _current: String = "WARRIOR"
var _drag: String = ""

func _ready() -> void:
	_load_data()
	_build_ui()
	_select_kind("WARRIOR")

func _build_ui() -> void:
	# Stage on left (sprite + capsule overlay). Pivot at the sprite anchor
	# so the editor-zoom slider scales OUT from the foot of the sprite —
	# the character stays in place while the canvas around it expands,
	# instead of zooming the whole stage off-screen.
	stage.name = "Stage"
	stage.position = Vector2(40, 60)
	stage.custom_minimum_size = Vector2(420, 480)
	stage.pivot_offset = Vector2(210, 380)
	add_child(stage)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.12, 0.15, 1)
	bg.size = stage.custom_minimum_size
	stage.add_child(bg)
	# Sprite anchored at "ground" (foot row) — bottom-center of stage.
	sprite.centered = true
	sprite.position = Vector2(210, 380)
	stage.add_child(sprite)
	stage.add_child(capsule_view)

	# Right-side form.
	var form := VBoxContainer.new()
	form.position = Vector2(500, 60)
	form.custom_minimum_size = Vector2(280, 0)
	add_child(form)

	form.add_child(_label("Enemy kind:"))
	for k in KIND_LIST:
		kind_picker.add_item(k)
	kind_picker.item_selected.connect(_on_kind_changed)
	form.add_child(kind_picker)

	form.add_child(_label("editor zoom (preview only):"))
	spin_zoom.min_value = 1.0; spin_zoom.max_value = 8.0; spin_zoom.step = 0.5
	spin_zoom.value = 1.0
	spin_zoom.value_changed.connect(_on_zoom_changed)
	form.add_child(spin_zoom)

	form.add_child(_label("sprite_scale (saved):"))
	spin_scale.min_value = 0.05; spin_scale.max_value = 2.0; spin_scale.step = 0.01
	spin_scale.value_changed.connect(_on_spin_changed)
	form.add_child(spin_scale)

	form.add_child(_label("capsule x (offset):"))
	spin_x.min_value = -100; spin_x.max_value = 100; spin_x.step = 1
	spin_x.value_changed.connect(_on_spin_changed)
	form.add_child(spin_x)

	form.add_child(_label("capsule y (offset):"))
	spin_y.min_value = -200; spin_y.max_value = 50; spin_y.step = 1
	spin_y.value_changed.connect(_on_spin_changed)
	form.add_child(spin_y)

	form.add_child(_label("capsule radius:"))
	spin_r.min_value = 2; spin_r.max_value = 80; spin_r.step = 1
	spin_r.value_changed.connect(_on_spin_changed)
	form.add_child(spin_r)

	form.add_child(_label("capsule height (middle):"))
	spin_h.min_value = 0; spin_h.max_value = 200; spin_h.step = 1
	spin_h.value_changed.connect(_on_spin_changed)
	form.add_child(spin_h)

	var save := Button.new()
	save.text = "Save All Presets"
	save.pressed.connect(_save)
	form.add_child(save)

	status.text = ""
	form.add_child(status)

	form.add_child(_label("Tip: drag the red handles on the\ncapsule to resize / move it."))

	# Capsule overlay draws/hits via a script instance attached to capsule_view.
	capsule_view.set_script(_make_capsule_script())
	capsule_view.set("editor_ref", self)
	# Apply default editor zoom so the sprite reads big enough on first open.
	stage.scale = Vector2(spin_zoom.value, spin_zoom.value)

func _label(t: String) -> Label:
	var l := Label.new(); l.text = t; return l

func _load_data() -> void:
	if not FileAccess.file_exists(PRESETS_PATH):
		return
	var f := FileAccess.open(PRESETS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_data = parsed
		_data.erase("_loaded")

func _save() -> void:
	var out: Dictionary = _data.duplicate(true)
	out.erase("_loaded")
	var f := FileAccess.open(PRESETS_PATH, FileAccess.WRITE)
	if f == null:
		status.text = "save failed"
		return
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	status.text = "saved %d kinds to enemy_presets.json" % out.size()

func _on_kind_changed(idx: int) -> void:
	_select_kind(KIND_LIST[idx])

func _select_kind(name: String) -> void:
	_current = name
	kind_picker.select(KIND_LIST.find(name))
	_load_sprite_for_kind(name)
	var preset := _get_or_default(name)
	spin_scale.set_block_signals(true); spin_scale.value = preset["scale"]; spin_scale.set_block_signals(false)
	var cap: Dictionary = preset["cap"]
	spin_x.set_block_signals(true); spin_x.value = cap["x"]; spin_x.set_block_signals(false)
	spin_y.set_block_signals(true); spin_y.value = cap["y"]; spin_y.set_block_signals(false)
	spin_r.set_block_signals(true); spin_r.value = cap["r"]; spin_r.set_block_signals(false)
	spin_h.set_block_signals(true); spin_h.value = cap["h"]; spin_h.set_block_signals(false)
	_apply_to_view()

func _get_or_default(name: String) -> Dictionary:
	# Use Skeleton's defaults as the baseline, then overlay any override
	# we already loaded from JSON.
	var idx: int = KIND_LIST.find(name)
	var defaults: Dictionary = Skeleton.KIND_PRESETS.get(idx, {"scale": 0.5, "cap": {"x": 0, "y": -30, "r": 13, "h": 32}})
	var out: Dictionary = defaults.duplicate(true)
	var ov: Variant = _data.get(str(idx), null)
	if ov is Dictionary:
		if ov.has("scale"):
			out["scale"] = ov["scale"]
		if ov.has("cap") and ov["cap"] is Dictionary:
			for k in ov["cap"]:
				out["cap"][k] = ov["cap"][k]
	return out

func _load_sprite_for_kind(name: String) -> void:
	var folder: String = CLASS_FOLDERS.get(name, "6Warrior")
	var path: String = "%s/%s/Idle.png" % [PACK_BASE, folder]
	if not ResourceLoader.exists(path):
		sprite.texture = null
		return
	var sheet: Texture2D = load(path)
	# 8 rows of frames, each square. Use direction row 2 (S = facing camera)
	# so the sprite faces forward in the editor.
	var frame_h: int = sheet.get_height() / 8
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(0, 2 * frame_h, frame_h, frame_h)
	sprite.texture = atlas
	# Anchor offset like skeleton.gd does in-game so the foot row of the
	# rendered sprite lines up with the skeleton's local y=0 (sprite origin).
	sprite.offset = Vector2(0, -42)

func _on_spin_changed(_v: float) -> void:
	_apply_to_view()
	_write_back()

func _apply_to_view() -> void:
	sprite.scale = Vector2(spin_scale.value, spin_scale.value)
	capsule_view.queue_redraw()

func _on_zoom_changed(_v: float) -> void:
	# Scale the stage Control so the preview enlarges without changing
	# the saved sprite_scale or capsule values. Children's local mouse
	# coords stay in the unscaled frame so drag math is unaffected.
	var z: float = float(spin_zoom.value)
	stage.scale = Vector2(z, z)

func _write_back() -> void:
	var idx: int = KIND_LIST.find(_current)
	var entry: Dictionary = {
		"scale": float(spin_scale.value),
		"cap": {
			"x": int(spin_x.value),
			"y": int(spin_y.value),
			"r": int(spin_r.value),
			"h": int(spin_h.value),
		},
	}
	_data[str(idx)] = entry

# Capsule overlay: a small inline Node2D script. Draws the capsule in
# stage-local coords (sprite anchored at stage(210, 380)), and accepts
# drag input on four edge handles to resize / move.
func _make_capsule_script() -> GDScript:
	var src := """
extends Node2D
var editor_ref: Node = null
const ORIGIN := Vector2(210.0, 380.0)
const HANDLE_R := 6.0
var _drag := \"\"   # \"\", \"top\", \"bot\", \"left\", \"right\", \"move\"
var _drag_start := Vector2.ZERO
var _drag_initial: Dictionary = {}

func _process(_d: float) -> void:
	queue_redraw()

func _draw() -> void:
	if editor_ref == null: return
	var x: float = float(editor_ref.spin_x.value)
	var y: float = float(editor_ref.spin_y.value)
	var r: float = float(editor_ref.spin_r.value)
	var h: float = float(editor_ref.spin_h.value)
	var c := ORIGIN + Vector2(x, y)
	# Capsule outline: rectangle (size 2r x h) capped with two semicircles.
	draw_rect(Rect2(c - Vector2(r, h * 0.5), Vector2(2 * r, h)), Color(1, 0.3, 0.3, 0.18), true)
	draw_circle(c - Vector2(0, h * 0.5), r, Color(1, 0.3, 0.3, 0.18))
	draw_circle(c + Vector2(0, h * 0.5), r, Color(1, 0.3, 0.3, 0.18))
	# Outline.
	draw_rect(Rect2(c - Vector2(r, h * 0.5), Vector2(2 * r, h)), Color(1, 0.3, 0.3, 0.9), false, 2.0)
	draw_arc(c - Vector2(0, h * 0.5), r, PI, TAU, 24, Color(1, 0.3, 0.3, 0.9), 2.0)
	draw_arc(c + Vector2(0, h * 0.5), r, 0, PI, 24, Color(1, 0.3, 0.3, 0.9), 2.0)
	# Handles.
	for hp in _handle_positions(c, r, h):
		draw_circle(hp, HANDLE_R, Color(1, 1, 0.4, 0.95))
		draw_arc(hp, HANDLE_R, 0, TAU, 16, Color(0, 0, 0, 1), 1.0)

func _handle_positions(c: Vector2, r: float, h: float) -> Array:
	return [
		c + Vector2(0, -h * 0.5 - r),  # top
		c + Vector2(0,  h * 0.5 + r),  # bottom
		c + Vector2(-r, 0),             # left
		c + Vector2( r, 0),             # right
		c,                               # center (move)
	]

func _input(ev: InputEvent) -> void:
	if editor_ref == null: return
	if ev is InputEventMouseButton:
		if ev.button_index != MOUSE_BUTTON_LEFT: return
		var local := get_local_mouse_position()
		if ev.pressed:
			var x: float = float(editor_ref.spin_x.value)
			var y: float = float(editor_ref.spin_y.value)
			var r: float = float(editor_ref.spin_r.value)
			var h: float = float(editor_ref.spin_h.value)
			var c := ORIGIN + Vector2(x, y)
			var hps := _handle_positions(c, r, h)
			var labels := [\"top\", \"bot\", \"left\", \"right\", \"move\"]
			for i in hps.size():
				if local.distance_to(hps[i]) <= HANDLE_R + 4:
					_drag = labels[i]
					_drag_start = local
					_drag_initial = {\"x\": x, \"y\": y, \"r\": r, \"h\": h}
					return
		else:
			_drag = \"\"
	elif ev is InputEventMouseMotion and _drag != \"\":
		var local := get_local_mouse_position()
		var d := local - _drag_start
		var ix: float = _drag_initial[\"x\"]
		var iy: float = _drag_initial[\"y\"]
		var ir: float = _drag_initial[\"r\"]
		var ih: float = _drag_initial[\"h\"]
		match _drag:
			\"move\":
				editor_ref.spin_x.value = ix + d.x
				editor_ref.spin_y.value = iy + d.y
			\"top\":
				# Drag up (negative dy) grows the top -> increase h, raise y up half d.
				var new_h: float = max(0.0, ih - d.y)
				editor_ref.spin_h.value = new_h
				editor_ref.spin_y.value = iy + (d.y * 0.5)
			\"bot\":
				var new_h2: float = max(0.0, ih + d.y)
				editor_ref.spin_h.value = new_h2
				editor_ref.spin_y.value = iy + (d.y * 0.5)
			\"left\":
				editor_ref.spin_r.value = max(2.0, ir - d.x)
			\"right\":
				editor_ref.spin_r.value = max(2.0, ir + d.x)
"""
	var sc := GDScript.new()
	sc.source_code = src
	sc.reload()
	return sc
