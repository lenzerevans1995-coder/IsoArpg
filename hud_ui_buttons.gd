extends Control
class_name HUDUIButtons

# Horizontal row of small UI-toggle buttons (Character, Inventory, Skills,
# Map, Quest, Party, Help, Menu) like Diablo 2's right-bar utility row.
# Emits `pressed(action)` when a button is clicked.

signal pressed(action: String)

const BUTTON_SIZE: int = 26
const BUTTON_GAP: int = 4

const BUTTONS: Array[Dictionary] = [
	{"action": "character",   "letter": "C", "hint": "Character (C)"},
	{"action": "inventory",   "letter": "I", "hint": "Inventory (I)"},
	{"action": "skills",      "letter": "K", "hint": "Skill Tree (K)"},
	{"action": "map",         "letter": "M", "hint": "Map (M)"},
	{"action": "quest",       "letter": "Q", "hint": "Quest Log (Q)"},
	{"action": "party",       "letter": "P", "hint": "Party (P)"},
	{"action": "help",        "letter": "?", "hint": "Help (H)"},
	{"action": "menu",        "letter": "≡", "hint": "Menu (Esc)"},
]

const COL_STONE_DARK   := Color(0.10, 0.09, 0.08)
const COL_BRONZE_MID   := Color(0.55, 0.42, 0.22)
const COL_GOLD         := Color(0.92, 0.78, 0.42)
const COL_GOLD_HI      := Color(1.00, 0.92, 0.65)
const COL_VOID         := Color(0.05, 0.04, 0.06)

func _ready() -> void:
	custom_minimum_size = Vector2(_total_width(), BUTTON_SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in range(BUTTONS.size()):
		var b: Button = Button.new()
		b.text = BUTTONS[i]["letter"]
		b.tooltip_text = BUTTONS[i]["hint"]
		b.position = Vector2(i * (BUTTON_SIZE + BUTTON_GAP), 0)
		b.size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
		b.flat = true
		b.add_theme_color_override("font_color", COL_GOLD_HI)
		b.add_theme_color_override("font_color_hover", Color(1, 1, 1))
		b.add_theme_color_override("font_color_pressed", COL_BRONZE_MID)
		b.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		b.add_theme_constant_override("outline_size", 3)
		b.add_theme_font_size_override("font_size", 13)
		var action: String = BUTTONS[i]["action"]
		b.pressed.connect(func() -> void: emit_signal("pressed", action))
		add_child(b)

func _total_width() -> int:
	return BUTTONS.size() * BUTTON_SIZE + (BUTTONS.size() - 1) * BUTTON_GAP

func _draw() -> void:
	# Backdrop strip behind the buttons (so the row reads as a "tray").
	var w: int = int(size.x)
	var h: int = int(size.y)
	draw_rect(Rect2(-3, -3, w + 6, h + 6), COL_STONE_DARK, true)
	draw_rect(Rect2(-2, -2, w + 4, h + 4), COL_BRONZE_MID, true)
	draw_rect(Rect2(-1, -1, w + 2, h + 2), COL_GOLD, true)
	draw_rect(Rect2(0, 0, w, h), COL_VOID, true)
	# Button cell separators.
	for i in range(BUTTONS.size()):
		var x: int = i * (BUTTON_SIZE + BUTTON_GAP)
		draw_rect(Rect2(x, 0, BUTTON_SIZE, BUTTON_SIZE), Color(0.10, 0.08, 0.10), true)
		draw_rect(Rect2(x + 1, 1, BUTTON_SIZE - 2, max(2, BUTTON_SIZE / 6)), Color(1, 1, 1, 0.05), true)
