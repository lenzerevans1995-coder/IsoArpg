@tool
extends Button
class_name IconButton

# Attach this script to any Button node (e.g. the HUD's BtnC / BtnI)
# and pick the icon directly from the inspector via icon_col / icon_row.
# Updates live in the editor while you tweak. The icon is sourced from
# the shared 64×64 sheet (assets/ui/Icons/64X64 DARK.png) — same atlas
# used by inventory slots etc., so changing it propagates everywhere.

const _IconAtlas := preload("res://icon_atlas.gd")

@export var icon_col: int = 0 :
	set(v):
		icon_col = v
		_apply_icon()
@export var icon_row: int = 0 :
	set(v):
		icon_row = v
		_apply_icon()
# When non-negative, takes precedence over (col, row) — handy for
# pasting a single number from a sheet preview tool.
@export var icon_linear_index: int = -1 :
	set(v):
		icon_linear_index = v
		_apply_icon()
@export var icon_size: Vector2 = Vector2(40, 40) :
	set(v):
		icon_size = v
		_apply_icon()

func _ready() -> void:
	_apply_icon()

func _apply_icon() -> void:
	var tex: Texture2D = null
	if icon_linear_index >= 0:
		tex = _IconAtlas.at_index(icon_linear_index)
	else:
		tex = _IconAtlas.at(icon_col, icon_row)
	icon = tex
	# Force the icon to render at icon_size regardless of the source
	# 64×64 cell. Using expand_icon + custom_minimum_size keeps the
	# button's hit area tight.
	expand_icon = true
	custom_minimum_size.x = max(custom_minimum_size.x, icon_size.x)
	custom_minimum_size.y = max(custom_minimum_size.y, icon_size.y)
