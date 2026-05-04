extends CanvasLayer

# Editor-driven HUD: every visual element lives in `combat_hud.tscn` so
# you can drag the angel statues, resize orbs, move the belt etc. without
# touching code. This script just wires the nodes up to runtime data.
#
# Scene contract (named children — DO NOT rename without updating here):
#   Root/HpStatue, Root/HpOrb, Root/HpLabel
#   Root/MpStatue, Root/MpOrb, Root/MpLabel
#   Root/UiButtons/{BtnC, BtnI, BtnK, BtnM, BtnQ, BtnP, BtnHelp, BtnMenu}
#   Root/LmbSquare, Root/RmbSquare
#   Root/StaminaBg, Root/StaminaFill
#   Root/Belt

@onready var _hp_orb: Control      = $Root/HpOrb
@onready var _hp_label: Label      = $Root/HpLabel
@onready var _mp_orb: Control      = $Root/MpOrb
@onready var _mp_label: Label      = $Root/MpLabel
@onready var _stamina: Control       = $Root/Stamina
@onready var _ui_buttons: GridContainer = $Root/UiButtons

var _panels_ui: Node = null

const _ACTIONS: Dictionary = {
	"BtnC":    "character",
	"BtnI":    "inventory",
	"BtnK":    "skills",
	"BtnM":    "map",
	"BtnQ":    "quest",
	"BtnP":    "party",
	"BtnHelp": "help",
	"BtnMenu": "menu",
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Wire each UI button to the toggle dispatcher.
	if _ui_buttons:
		for child in _ui_buttons.get_children():
			if child is Button and _ACTIONS.has(child.name):
				var action: String = _ACTIONS[child.name]
				(child as Button).pressed.connect(_on_ui_button_pressed.bind(action))

# ---- Public API ----------------------------------------------------------

func bind_panels_ui(panels: Node) -> void:
	_panels_ui = panels

func set_player_stats(hp: int, max_hp: int, mp: int, max_mp: int) -> void:
	if _hp_orb:
		var t: float = clamp(float(hp) / max(float(max_hp), 1.0), 0.0, 1.0)
		_hp_orb.set("value", t)
	if _hp_label:
		_hp_label.text = "Life: %d / %d" % [hp, max_hp]
	if _mp_orb:
		var t: float = clamp(float(mp) / max(float(max_mp), 1.0), 0.0, 1.0)
		_mp_orb.set("value", t)
	if _mp_label:
		_mp_label.text = "Mana: %d / %d" % [mp, max_mp]

func set_stamina(value: float, max_value: float) -> void:
	if _stamina == null:
		return
	var t: float = clamp(value / max(max_value, 1.0), 0.0, 1.0)
	_stamina.set("value", t)

func set_wave_info(_wave: int, _alive: int) -> void:
	pass

func set_level(_level: int) -> void:
	pass

# ---- Internals -----------------------------------------------------------

func _on_ui_button_pressed(action: String) -> void:
	if _panels_ui == null:
		return
	match action:
		"character":
			if _panels_ui.has_method("toggle_character"):
				_panels_ui.call("toggle_character")
		"inventory":
			if _panels_ui.has_method("toggle_inventory"):
				_panels_ui.call("toggle_inventory")
		"skills":
			if _panels_ui.has_method("toggle_skills"):
				_panels_ui.call("toggle_skills")
		_:
			pass
