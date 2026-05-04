@tool
extends Node2D

# Visual collision-bounds editor focused on PLAYER ↔ GOBLIN proximity.
# Open `bounds_editor.tscn` in the editor or hit F6 to run. Drag the
# Goblin / BossGoblin Node2Ds in the 2D viewport to test distances
# live; the gap-line readout shows whether the goblin can actually
# reach the player given the pushback radius.

# ─── Player movement collision ─────────────────────────────────────
# `player_longbow.gd → GOBLIN_BODY_RADIUS` — pushback radius. The
# player CANNOT approach a goblin closer than this (foot-anchored).
@export_range(8.0, 96.0, 1.0) var player_pushback_radius: float = 32.0 :
	set(v):
		player_pushback_radius = v
		queue_redraw()

# Player's hittable body for melee reach calculations.
@export_range(8.0, 64.0, 1.0) var player_body_radius: float = 24.0 :
	set(v):
		player_body_radius = v
		queue_redraw()

# ─── Goblin movement / peer separation ─────────────────────────────
# `goblin.gd → PEER_BODY_RADIUS` (28 default; bosses use ×1.6).
@export_range(8.0, 96.0, 1.0) var goblin_peer_radius: float = 28.0 :
	set(v):
		goblin_peer_radius = v
		queue_redraw()

@export_range(16.0, 128.0, 1.0) var goblin_boss_peer_radius: float = 44.0 :
	set(v):
		goblin_boss_peer_radius = v
		queue_redraw()

# ─── Goblin attack reach ──────────────────────────────────────────
# `goblin.gd → @export attack_range` and `aoe_attack_range`.
@export_range(16.0, 160.0, 1.0) var goblin_attack_range: float = 56.0 :
	set(v):
		goblin_attack_range = v
		queue_redraw()

@export_range(32.0, 256.0, 1.0) var goblin_aoe_attack_range: float = 96.0 :
	set(v):
		goblin_aoe_attack_range = v
		queue_redraw()

@export var print_values: bool = false :
	set(v):
		if v:
			_print_values()

# ─── Colours ──────────────────────────────────────────────────────
const COL_PLAYER_PUSHBACK := Color(0.30, 0.70, 1.00, 0.55)
const COL_PLAYER_BODY     := Color(0.55, 0.85, 1.00, 0.85)
const COL_GOBLIN_PEER     := Color(1.00, 0.55, 0.20, 0.55)
const COL_GOBLIN_BOSS     := Color(1.00, 0.30, 0.30, 0.55)
const COL_GOBLIN_ATTACK   := Color(1.00, 0.85, 0.20, 0.70)
const COL_GOBLIN_AOE      := Color(1.00, 0.40, 0.20, 0.55)
const COL_FOOT_DOT        := Color(1.00, 1.00, 0.10, 0.95)
const COL_GAP_OK          := Color(0.40, 1.00, 0.40, 0.95)
const COL_GAP_BAD         := Color(1.00, 0.30, 0.30, 0.95)
const COL_GAP_BLOCKED     := Color(1.00, 0.55, 0.20, 0.95)

func _ready() -> void:
	set_process(true)

func _process(_dt: float) -> void:
	queue_redraw()

func _draw() -> void:
	var player: Node2D = get_node_or_null("Player")
	var goblin: Node2D = get_node_or_null("Goblin")
	var boss: Node2D = get_node_or_null("BossGoblin")

	if player:
		_draw_circle_outline(player.global_position, player_pushback_radius, COL_PLAYER_PUSHBACK)
		_draw_circle_outline(player.global_position, player_body_radius, COL_PLAYER_BODY, 1.5)
		_draw_foot_marker(player.global_position)
		_draw_label(player.global_position + Vector2(0, 18),
			"PLAYER  pushback=%d  body=%d" % [
				int(player_pushback_radius), int(player_body_radius)
			])
	if goblin:
		_draw_circle_outline(goblin.global_position, goblin_peer_radius, COL_GOBLIN_PEER)
		_draw_circle_outline(goblin.global_position, goblin_attack_range, COL_GOBLIN_ATTACK, 1.5)
		_draw_foot_marker(goblin.global_position)
		_draw_label(goblin.global_position + Vector2(0, 18),
			"GOBLIN  peer=%d  attack=%d" % [
				int(goblin_peer_radius), int(goblin_attack_range)
			])
		if player:
			_draw_attack_gap(goblin.global_position, player.global_position,
				goblin_attack_range, player_body_radius, player_pushback_radius)
	if boss:
		_draw_circle_outline(boss.global_position, goblin_boss_peer_radius, COL_GOBLIN_BOSS)
		_draw_circle_outline(boss.global_position, goblin_attack_range, COL_GOBLIN_ATTACK, 1.5)
		_draw_circle_outline(boss.global_position, goblin_aoe_attack_range, COL_GOBLIN_AOE, 1.5)
		_draw_foot_marker(boss.global_position)
		_draw_label(boss.global_position + Vector2(0, 18),
			"BOSS  peer=%d  attack=%d  aoe=%d" % [
				int(goblin_boss_peer_radius), int(goblin_attack_range),
				int(goblin_aoe_attack_range)
			])
		if player:
			_draw_attack_gap(boss.global_position, player.global_position,
				goblin_aoe_attack_range, player_body_radius, player_pushback_radius * 1.6)

# ─── Helpers ───────────────────────────────────────────────────────

func _draw_circle_outline(centre: Vector2, radius: float, col: Color, thickness: float = 2.0) -> void:
	var local: Vector2 = to_local(centre)
	draw_arc(local, radius, 0.0, TAU, 64, col, thickness, true)
	var fill: Color = col
	fill.a *= 0.16
	draw_circle(local, radius, fill)

func _draw_foot_marker(centre: Vector2) -> void:
	var local: Vector2 = to_local(centre)
	draw_circle(local, 3.0, COL_FOOT_DOT)

# Gap = real foot-to-foot distance.
# Reach = goblin attack_range + player body_radius (overlap = hit).
# Pushback = enemy can never get closer than `pushback` to player.
# So the EFFECTIVE distance the enemy stops at is max(dist, pushback).
# If reach < pushback → goblin literally cannot ever reach the player,
# its swings will always land in air. That's the bug to fix.
func _draw_attack_gap(g_pos: Vector2, p_pos: Vector2,
		attack_r: float, p_body_r: float, pushback_r: float) -> void:
	var dist: float = g_pos.distance_to(p_pos)
	var reach: float = attack_r + p_body_r
	var stops_at: float = max(dist, pushback_r)
	var ok: bool = reach >= dist
	var blocked: bool = reach < pushback_r
	var col: Color = COL_GAP_OK if ok else (COL_GAP_BLOCKED if blocked else COL_GAP_BAD)
	var local_g: Vector2 = to_local(g_pos)
	var local_p: Vector2 = to_local(p_pos)
	draw_line(local_g, local_p, col, 2.0, true)
	var mid: Vector2 = (local_g + local_p) * 0.5
	var status: String
	if blocked:
		status = "BLOCKED  reach %d < pushback %d  (will ALWAYS attack air)" % [
			int(reach), int(pushback_r)
		]
	elif ok:
		status = "OK  reach %d ≥ dist %d" % [int(reach), int(dist)]
	else:
		status = "GAP  reach %d  dist %d  short %d" % [
			int(reach), int(dist), int(dist - reach)
		]
	var font: Font = ThemeDB.fallback_font
	draw_string(font, mid + Vector2(-110, -10), status,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)

func _draw_label(centre: Vector2, text: String) -> void:
	var font: Font = ThemeDB.fallback_font
	var local: Vector2 = to_local(centre)
	draw_string(font, local + Vector2(-90, 28), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.9))

func _print_values() -> void:
	print("[bounds_editor] CURRENT VALUES — copy into source files")
	print("  player_longbow.gd : GOBLIN_BODY_RADIUS  = ", player_pushback_radius)
	print("  goblin.gd         : PEER_BODY_RADIUS    = ", goblin_peer_radius)
	print("  goblin.gd  (boss) : peer radius (×1.6)  = ", goblin_boss_peer_radius)
	print("  goblin.gd         : @export attack_range = ", goblin_attack_range)
	print("  goblin.gd         : @export aoe_attack_range = ", goblin_aoe_attack_range)
	print("  (informational)   : player_body_radius  = ", player_body_radius)
