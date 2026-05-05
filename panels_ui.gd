extends CanvasLayer
class_name PanelsUI

# Toggleable Inventory / Character / Skills panels — built from the same
# components as the combat HUD: HUDCenterBar for the panel chrome,
# HUDSkillSquare for slots. Master/equipped slots reuse the same
# component but rotated 45° for visual hierarchy.

const HUDCenterBarScript: Script   = preload("res://hud_center_bar.gd")
const HUDSkillSquareScript: Script = preload("res://hud_skill_square.gd")

const HUDStoneButtonScript: Script = preload("res://hud_stone_button.gd")
const StatStepperBtnScript: Script = preload("res://stat_stepper_btn.gd")

const PANEL_W: int = 460
const PANEL_H: int = 360
const SLOT_SIZE: int = 44
const SLOT_GAP: int = 4
const TITLE_H: int = 28

# Live state pulled from main.stats — `_refresh_stats()` syncs the
# locals so the panel rebuild logic doesn't have to special-case null.
var _level: int = 1
var _xp: int = 0
var _xp_needed: int = 100
var _available_points: int = 0
var _stats: Dictionary = {
	"STRENGTH":  0,
	"DEXTERITY": 0,
	"INTELLECT": 0,
	"VITALITY":  0,
}
var _stat_value_lbls: Dictionary = {}
var _points_lbl: Label = null
var _xp_val_lbl: Label = null
var _level_val_lbl: Label = null

# Maps the in-panel stat row labels onto the underlying CharacterStats
# attribute names. INTELLECT is shown as the row label; the underlying
# attribute is `energy` (matches the stat container's nomenclature).
const _STAT_ATTR := {
	"STRENGTH":  "strength",
	"DEXTERITY": "dexterity",
	"INTELLECT": "energy",
	"VITALITY":  "vitality",
}

const COL_TEXT     := Color(0.92, 0.92, 0.90)
const COL_TEXT_DIM := Color(0.62, 0.60, 0.55)
const COL_ACCENT   := Color(1.00, 0.92, 0.65)

var _inventory: Control
var _character: Control
var _skills: Control
var _root: Control

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_inventory = _build_inventory()
	_character = _build_character()
	_skills    = _build_skills()
	_inventory.visible = false
	_character.visible = false
	_skills.visible    = false

# ---- Shared helpers ------------------------------------------------------

func _make_panel(title: String) -> Control:
	# Centred HUDCenterBar-styled panel with a title label.
	var panel: Control = HUDCenterBarScript.new()
	panel.size = Vector2(PANEL_W, PANEL_H)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -PANEL_W / 2
	panel.offset_right = PANEL_W / 2
	panel.offset_top = -PANEL_H / 2
	panel.offset_bottom = PANEL_H / 2
	_root.add_child(panel)

	var title_lbl: Label = _styled_label(title, 18, COL_ACCENT)
	title_lbl.position = Vector2(0, 8)
	title_lbl.size = Vector2(PANEL_W, TITLE_H)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(title_lbl)
	return panel

func _make_slot(parent: Control, x: int, y: int, master: bool = false) -> Control:
	var slot: Control = HUDSkillSquareScript.new()
	slot.set("sz", SLOT_SIZE)
	slot.position = Vector2(x, y)
	slot.size = Vector2(SLOT_SIZE, SLOT_SIZE)
	if master:
		# Rotate 45° around the centre — distinguishes "equipped" / "master"
		# slots from inventory cells.
		slot.pivot_offset = Vector2(SLOT_SIZE / 2, SLOT_SIZE / 2)
		slot.rotation_degrees = 45.0
	parent.add_child(slot)
	return slot

func _styled_label(text: String, font_size: int = 13, color: Color = COL_TEXT) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.06, 0.95))
	lbl.add_theme_constant_override("outline_size", 4)
	return lbl

# ---- Inventory -----------------------------------------------------------

func _build_inventory() -> Control:
	var panel: Control = _make_panel("INVENTORY")
	# 6 cols × 5 rows = 30 inventory cells, centred horizontally below title.
	var cols: int = 6
	var rows: int = 5
	var grid_w: int = cols * SLOT_SIZE + (cols - 1) * SLOT_GAP
	var grid_h: int = rows * SLOT_SIZE + (rows - 1) * SLOT_GAP
	var origin_x: int = (PANEL_W - grid_w) / 2
	var origin_y: int = TITLE_H + 24
	for r in range(rows):
		for c in range(cols):
			var x: int = origin_x + c * (SLOT_SIZE + SLOT_GAP)
			var y: int = origin_y + r * (SLOT_SIZE + SLOT_GAP)
			_make_slot(panel, x, y)
	# Footer hint.
	var hint: Label = _styled_label("E  USE     C  DROP     ESC  CLOSE", 10, COL_TEXT_DIM)
	hint.position = Vector2(0, PANEL_H - 24)
	hint.size = Vector2(PANEL_W, 16)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(hint)
	return panel

# ---- Character -----------------------------------------------------------

func _build_character() -> Control:
	_refresh_stats()
	var panel: Control = _make_panel("CHARACTER")

	# --- Header: Level + XP read-out ---------------------------------------
	var header: VBoxContainer = VBoxContainer.new()
	header.add_theme_constant_override("separation", 2)
	header.position = Vector2(40, TITLE_H + 18)
	header.size = Vector2(PANEL_W - 80, 60)
	panel.add_child(header)

	var lvl_row: HBoxContainer = HBoxContainer.new()
	header.add_child(lvl_row)
	var lvl_name: Label = _styled_label("LEVEL", 13, COL_TEXT_DIM)
	lvl_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lvl_row.add_child(lvl_name)
	var lvl_val: Label = _styled_label(str(_level), 14, COL_ACCENT)
	lvl_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lvl_row.add_child(lvl_val)

	var xp_row: HBoxContainer = HBoxContainer.new()
	header.add_child(xp_row)
	var xp_name: Label = _styled_label("EXPERIENCE", 11, COL_TEXT_DIM)
	xp_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_row.add_child(xp_name)
	var xp_val: Label = _styled_label("%d / %d" % [_xp, _xp_needed], 11, COL_TEXT)
	xp_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	xp_row.add_child(xp_val)

	# --- Available points banner -------------------------------------------
	_points_lbl = _styled_label("AVAILABLE POINTS:  %d" % _available_points, 13, COL_ACCENT)
	_points_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_points_lbl.position = Vector2(0, TITLE_H + 90)
	_points_lbl.size = Vector2(PANEL_W, 20)
	panel.add_child(_points_lbl)

	# --- Stat rows with [+] allocation buttons -----------------------------
	var stats_box: VBoxContainer = VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 6)
	stats_box.position = Vector2(60, TITLE_H + 122)
	stats_box.size = Vector2(PANEL_W - 120, 200)
	panel.add_child(stats_box)
	for stat_name in _stats.keys():
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		stats_box.add_child(row)

		var name_lbl: Label = _styled_label(stat_name, 12, COL_TEXT_DIM)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var val_lbl: Label = _styled_label(str(_stats[stat_name]), 13, COL_ACCENT)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_lbl.custom_minimum_size = Vector2(36, 0)
		row.add_child(val_lbl)
		_stat_value_lbls[stat_name] = val_lbl

		# Lucide-style + glyph drawn in code, run through the pixelize
		# shader to match the rest of the HUD's chunky aesthetic.
		var plus_btn: Button = Button.new()
		plus_btn.set_script(StatStepperBtnScript)
		plus_btn.set("mode", 0)               # StatStepperBtn.Mode.PLUS
		plus_btn.set("glyph_color", COL_ACCENT)
		plus_btn.set("pixel_size", 2.0)
		plus_btn.flat = true
		plus_btn.custom_minimum_size = Vector2(26, 26)
		plus_btn.pressed.connect(_allocate_stat_point.bind(stat_name))
		row.add_child(plus_btn)

	# Footer hint.
	var hint: Label = _styled_label("ESC  CLOSE", 10, COL_TEXT_DIM)
	hint.position = Vector2(0, PANEL_H - 24)
	hint.size = Vector2(PANEL_W, 16)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(hint)
	return panel

func _allocate_stat_point(stat_name: String) -> void:
	if _available_points <= 0:
		return
	if not _stats.has(stat_name):
		return
	# Write back to main.stats so the change persists and re-derives
	# max_hp / max_mp / attack rating.
	var s: Object = _get_stats()
	if s != null:
		var attr_name: String = String(_STAT_ATTR.get(stat_name, ""))
		if attr_name != "":
			s.set(attr_name, int(s.get(attr_name)) + 1)
		s.unspent_stat_points = max(0, int(s.unspent_stat_points) - 1)
		# Refill current pools to the new max so the player sees the bonus
		# *immediately* on the HUD orbs. Without this the max grows but
		# the orb fill stays at the pre-allocation value, so the UI reads
		# as if nothing happened.
		if attr_name == "vitality":
			s.hp = s.max_hp()
			s.emit_signal("hp_changed", s.hp, s.max_hp())
		elif attr_name == "energy":
			s.mp = s.max_mp()
			s.emit_signal("mp_changed", s.mp, s.max_mp())
		else:
			# Strength / dex didn't change resources but did change derived
			# numbers (damage / attack rating); poke the HP signal so the
			# HUD re-renders any derived display tied to it.
			s.emit_signal("hp_changed", s.hp, s.max_hp())
	_stats[stat_name] = int(_stats[stat_name]) + 1
	_available_points -= 1
	if _stat_value_lbls.has(stat_name):
		(_stat_value_lbls[stat_name] as Label).text = str(_stats[stat_name])
	if _points_lbl:
		_points_lbl.text = "AVAILABLE POINTS:  %d" % _available_points
		_points_lbl.modulate = Color(1, 1, 1) if _available_points > 0 else Color(0.6, 0.6, 0.55)

# Pulls live values from main.stats into the panel's local mirrors so
# the UI shows real level / XP / attribute numbers instead of the
# dummy defaults. Called before the character panel is shown.
func _get_stats() -> Object:
	var main: Node = get_tree().root.get_node_or_null("Main")
	if main == null or not ("stats" in main):
		return null
	return main.stats

func _refresh_stats() -> void:
	var s: Object = _get_stats()
	if s == null:
		return
	_level = int(s.level)
	_xp = int(s.xp)
	_xp_needed = int(s.xp_for_level(s.level + 1))
	_available_points = int(s.unspent_stat_points)
	for ui_name in _STAT_ATTR.keys():
		_stats[ui_name] = int(s.get(_STAT_ATTR[ui_name]))

# ---- Skill tree ----------------------------------------------------------

const SKILLS_PANEL_W: int = 820
const SKILLS_PANEL_H: int = 620
const TIER_LABEL_W: int = 88
const NODE_LABEL_GAP: int = 10
const SKILL_TITLE_H: int = 56
const TIER_BAND_H: int = 130

# Skill tree spec — tier list with node positions, names, max ranks, and
# parent indices (for connector wiring). All x is in panel-local space.
# Layout: title=56h, then 4 bands @ 130h each = 520, footer at 600.
const _SKILL_TIERS: Array = [
	{
		"y": 130,
		"req_level": 1,
		"label": "TIER I — INITIATE",
		"nodes": [
			{ "name": "MARK", "x": 410, "max": 1, "master": true, "parents": [] },
		],
	},
	{
		"y": 260,
		"req_level": 3,
		"label": "TIER II — APPRENTICE",
		"nodes": [
			{ "name": "ICE SHARD",  "x": 250, "max": 5, "master": false, "parents": [Vector2i(0, 0)] },
			{ "name": "FROST BOLT", "x": 410, "max": 5, "master": false, "parents": [Vector2i(0, 0)] },
			{ "name": "STORM SHOT", "x": 570, "max": 5, "master": false, "parents": [Vector2i(0, 0)] },
		],
	},
	{
		"y": 390,
		"req_level": 8,
		"label": "TIER III — ADEPT",
		"nodes": [
			{ "name": "PIERCE",     "x": 180, "max": 5, "master": false, "parents": [Vector2i(1, 0)] },
			{ "name": "MULTISHOT",  "x": 330, "max": 5, "master": false, "parents": [Vector2i(1, 0), Vector2i(1, 1)] },
			{ "name": "CHAIN BOLT", "x": 490, "max": 5, "master": false, "parents": [Vector2i(1, 1), Vector2i(1, 2)] },
			{ "name": "TEMPEST",    "x": 640, "max": 5, "master": false, "parents": [Vector2i(1, 2)] },
		],
	},
	{
		"y": 520,
		"req_level": 15,
		"label": "TIER IV — MASTER",
		"nodes": [
			{ "name": "AVATAR OF FROST", "x": 410, "max": 1, "master": true,
			  "parents": [Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3)] },
		],
	},
]

# Mock player progression — tweak to test states.
var _player_level: int = 5
var _skill_points: int = 3
var _skill_ranks: Dictionary = {}
var _skill_state_lbls: Dictionary = {}     # node_id -> rank chip Label
var _skill_node_ctrls: Dictionary = {}     # node_id -> outer Control (for re-modulating on level change)
var _skill_points_lbl: Label = null

func _build_skills() -> Control:
	# Override panel size for the wider skill tree.
	var panel: Control = HUDCenterBarScript.new()
	panel.size = Vector2(SKILLS_PANEL_W, SKILLS_PANEL_H)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -SKILLS_PANEL_W / 2
	panel.offset_right = SKILLS_PANEL_W / 2
	panel.offset_top = -SKILLS_PANEL_H / 2
	panel.offset_bottom = SKILLS_PANEL_H / 2
	_root.add_child(panel)

	# Title (left).
	var title_lbl: Label = _styled_label("PATH OF THE FROST-ARCHER", 18, COL_ACCENT)
	title_lbl.position = Vector2(28, 14)
	title_lbl.size = Vector2(500, 26)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(title_lbl)

	# Subtitle.
	var subtitle: Label = _styled_label("Allocate points to learn and rank up skills.", 10, COL_TEXT_DIM)
	subtitle.position = Vector2(28, 36)
	subtitle.size = Vector2(500, 16)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	panel.add_child(subtitle)

	# Skill points chip (right).
	_skill_points_lbl = _styled_label("SKILL POINTS  %d" % _skill_points, 14, COL_ACCENT)
	_skill_points_lbl.position = Vector2(SKILLS_PANEL_W - 220, 16)
	_skill_points_lbl.size = Vector2(190, 26)
	_skill_points_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skill_points_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(_skill_points_lbl)

	# Tier banners along the left — full label, gold accent, with required-level chip.
	for ti in range(_SKILL_TIERS.size()):
		var tier: Dictionary = _SKILL_TIERS[ti]
		var unlocked: bool = _player_level >= int(tier["req_level"])
		var label_col: Color = COL_ACCENT if unlocked else COL_TEXT_DIM
		var tier_lbl: Label = _styled_label(tier["label"], 11, label_col)
		tier_lbl.position = Vector2(14, int(tier["y"]) - 12)
		tier_lbl.size = Vector2(170, 14)
		tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		panel.add_child(tier_lbl)
		var req_lbl: Label = _styled_label(
			"REQ LEVEL %d" % int(tier["req_level"]), 9, COL_TEXT_DIM
		)
		req_lbl.position = Vector2(14, int(tier["y"]) + 2)
		req_lbl.size = Vector2(170, 12)
		req_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		panel.add_child(req_lbl)
		# Faint horizontal divider line below each tier.
		if ti < _SKILL_TIERS.size() - 1:
			var sep: ColorRect = ColorRect.new()
			sep.position = Vector2(20, int(tier["y"]) + 60)
			sep.size = Vector2(SKILLS_PANEL_W - 40, 1)
			sep.color = Color(0.30, 0.32, 0.34, 0.4)
			sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			panel.add_child(sep)

	# Connectors first (drawn under nodes).
	var connector_layer: Control = Control.new()
	connector_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	connector_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(connector_layer)
	for ti in range(_SKILL_TIERS.size()):
		var tier: Dictionary = _SKILL_TIERS[ti]
		for ni in range((tier["nodes"] as Array).size()):
			var node: Dictionary = tier["nodes"][ni]
			for parent_ref in node["parents"]:
				var p_tier: Dictionary = _SKILL_TIERS[parent_ref.x]
				var p_node: Dictionary = p_tier["nodes"][parent_ref.y]
				var unlocked: bool = _player_level >= int(tier["req_level"])
				var line_col: Color = COL_ACCENT if unlocked else Color(0.30, 0.32, 0.34, 0.8)
				_draw_elbow_connector(
					connector_layer,
					Vector2(int(p_node["x"]), int(p_tier["y"]) + SLOT_SIZE / 2),
					Vector2(int(node["x"]), int(tier["y"]) - SLOT_SIZE / 2),
					line_col
				)

	# Nodes + helper labels.
	for ti in range(_SKILL_TIERS.size()):
		var tier: Dictionary = _SKILL_TIERS[ti]
		for ni in range((tier["nodes"] as Array).size()):
			var node: Dictionary = tier["nodes"][ni]
			_make_skill_node(panel, ti, ni, tier, node)

	# Footer legend.
	var legend: Label = _styled_label(
		"LEGEND:  ◆ MASTER  ·  ☐ NODE  ·  +  RANK UP   |   ESC CLOSE", 10, COL_TEXT_DIM
	)
	legend.position = Vector2(0, SKILLS_PANEL_H - 24)
	legend.size = Vector2(SKILLS_PANEL_W, 16)
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(legend)
	return panel

# Builds an L-shaped (orthogonal) connector between two nodes — vertical
# down from parent, horizontal across at midpoint, vertical down into
# child. Far less visually noisy than diagonal lines.
func _draw_elbow_connector(parent_ctrl: Control, from: Vector2, to: Vector2, col: Color) -> void:
	var mid_y: float = (from.y + to.y) * 0.5
	var line: Line2D = Line2D.new()
	line.add_point(Vector2(from.x, from.y))
	line.add_point(Vector2(from.x, mid_y))
	line.add_point(Vector2(to.x, mid_y))
	line.add_point(Vector2(to.x, to.y))
	line.width = 2.0
	line.default_color = col
	line.joint_mode = Line2D.LINE_JOINT_BEVEL
	line.begin_cap_mode = Line2D.LINE_CAP_NONE
	line.end_cap_mode = Line2D.LINE_CAP_NONE
	parent_ctrl.add_child(line)

# Composite skill-node: HUDSkillSquare slot + name label + rank chip,
# wrapped in an outer Control so we can dim the whole node when locked.
func _make_skill_node(parent: Control, tier_idx: int, node_idx: int,
		tier: Dictionary, node: Dictionary) -> void:
	var node_id: String = "%d:%d" % [tier_idx, node_idx]
	_skill_ranks[node_id] = 0

	var unlocked: bool = _player_level >= int(tier["req_level"])
	var node_x: int = int(node["x"]) - SLOT_SIZE / 2
	var node_y: int = int(tier["y"]) - SLOT_SIZE / 2

	var wrapper: Control = Control.new()
	wrapper.position = Vector2(node_x, node_y)
	wrapper.size = Vector2(SLOT_SIZE, SLOT_SIZE + NODE_LABEL_GAP + 28)
	wrapper.modulate = Color(1, 1, 1, 1) if unlocked else Color(0.45, 0.45, 0.45, 0.85)
	parent.add_child(wrapper)
	_skill_node_ctrls[node_id] = wrapper

	# Slot.
	var slot: Control = HUDSkillSquareScript.new()
	slot.set("sz", SLOT_SIZE)
	slot.position = Vector2.ZERO
	slot.size = Vector2(SLOT_SIZE, SLOT_SIZE)
	if node["master"]:
		slot.pivot_offset = Vector2(SLOT_SIZE / 2, SLOT_SIZE / 2)
		slot.rotation_degrees = 45.0
	wrapper.add_child(slot)

	# Name label below the slot — accommodate the diamond rotation by adding
	# a little extra margin for masters (they extend below their bbox).
	var label_y: int = SLOT_SIZE + (NODE_LABEL_GAP + 6 if node["master"] else NODE_LABEL_GAP)
	var name_lbl: Label = _styled_label(node["name"], 10, COL_TEXT)
	name_lbl.position = Vector2(-30, label_y)
	name_lbl.size = Vector2(SLOT_SIZE + 60, 14)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrapper.add_child(name_lbl)

	# Rank chip (e.g. "0 / 5").
	var rank_lbl: Label = _styled_label(
		"%d / %d" % [0, int(node["max"])], 9, COL_TEXT_DIM
	)
	rank_lbl.position = Vector2(-30, label_y + 13)
	rank_lbl.size = Vector2(SLOT_SIZE + 60, 12)
	rank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrapper.add_child(rank_lbl)
	_skill_state_lbls[node_id] = rank_lbl

	# [+] button — only the master/non-master nodes that are unlocked can
	# allocate. Bottom-right of the slot.
	if unlocked:
		var plus_btn: Button = Button.new()
		plus_btn.set_script(HUDStoneButtonScript)
		plus_btn.text = "+"
		plus_btn.custom_minimum_size = Vector2(18, 18)
		plus_btn.size = Vector2(18, 18)
		plus_btn.position = Vector2(SLOT_SIZE - 6, SLOT_SIZE - 6)
		plus_btn.pressed.connect(_allocate_skill_rank.bind(node_id, int(node["max"])))
		wrapper.add_child(plus_btn)

func _allocate_skill_rank(node_id: String, max_rank: int) -> void:
	if _skill_points <= 0:
		return
	var current: int = int(_skill_ranks.get(node_id, 0))
	if current >= max_rank:
		return
	_skill_ranks[node_id] = current + 1
	_skill_points -= 1
	if _skill_state_lbls.has(node_id):
		var lbl: Label = _skill_state_lbls[node_id]
		lbl.text = "%d / %d" % [current + 1, max_rank]
		lbl.add_theme_color_override("font_color", COL_ACCENT if (current + 1) >= max_rank else COL_TEXT)
	if _skill_points_lbl:
		_skill_points_lbl.text = "SKILL POINTS  %d" % _skill_points
		_skill_points_lbl.modulate = Color(1, 1, 1) if _skill_points > 0 else Color(0.6, 0.6, 0.55)

# ---- Toggle helpers ------------------------------------------------------

func toggle_inventory() -> void:
	_inventory.visible = not _inventory.visible
	_animate_in(_inventory, Vector2(0, 30))

func toggle_character() -> void:
	# Re-pull live stats then rebuild the panel content so level / XP /
	# attribute numbers always reflect main.stats — much cheaper than
	# wiring a per-field signal listener.
	if not _character.visible:
		_refresh_stats()
		_rebuild_character()
	_character.visible = not _character.visible

func _rebuild_character() -> void:
	if _character == null:
		return
	var was_visible: bool = _character.visible
	# `_make_panel` (inside _build_character) auto-adds the new panel
	# to `_root`, so we just free the old one and let the new one take
	# its place — no manual reparent needed.
	_character.queue_free()
	_stat_value_lbls.clear()
	_points_lbl = null
	_character = _build_character()
	_character.visible = was_visible
	_animate_in(_character, Vector2(-30, 0))

func toggle_skills() -> void:
	_skills.visible = not _skills.visible
	_animate_in(_skills, Vector2(0, 30))

func _animate_in(panel: Control, from: Vector2) -> void:
	if not panel.visible:
		return
	var orig: Vector2 = panel.position
	panel.modulate.a = 0.0
	panel.position = orig + from
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel, "position", orig, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, 0.18)
