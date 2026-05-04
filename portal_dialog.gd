extends CanvasLayer
class_name PortalDialog

# Centered modal asking the player whether to enter / leave a dungeon.
# Two buttons: confirm + cancel. Emits a signal so callers don't have to
# wire connections through the main scene.

signal confirmed
signal cancelled

func _init() -> void:
	layer = 60

func _ready() -> void:
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.55)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(360, 0)
	scrim.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var ok := Button.new()
	ok.text = confirm_text
	ok.pressed.connect(_on_ok)
	row.add_child(ok)
	var no := Button.new()
	no.text = cancel_text
	no.pressed.connect(_on_no)
	row.add_child(no)

var title_text: String = "Enter the dungeon?"
var confirm_text: String = "Enter"
var cancel_text: String = "Cancel"

func _on_ok() -> void:
	emit_signal("confirmed")
	queue_free()

func _on_no() -> void:
	emit_signal("cancelled")
	queue_free()
