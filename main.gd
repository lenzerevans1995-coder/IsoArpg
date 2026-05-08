extends Node2D

# ---- Tile / iso constants ----------------------------------------------------
# Fantasy tileset: 256x256 canvas, diamond footprint 128x80 at bottom-center.
# Pivot is (0.5, 0.18) measured from the bottom -> canvas y = 256 - 0.18*256 = 210.
# Sprite native center (with centered=true) is at canvas y = 128. To align the
# pivot to the node origin, shift the sprite up by 210 - 128 = 82 pixels.
const TILE_W := 128
const TILE_H := 64
const SPRITE_Y_OFFSET := -82
# Some tall tiles (cliffs, big rocks) want a higher pivot per the asset spec.
# We don't use those in phase 1.

# ---- World streaming ---------------------------------------------------------
const CHUNK_SIZE := 16            # cells per chunk side
const VIEW_RADIUS_CHUNKS := 2     # load chunks within this radius of player

# Battle / physics sample arena. When true, the world is a fixed bounded
# rectangle (BATTLE_RECT) instead of infinite noise terrain — every chunk in
# the rect loads at startup and never unloads. Used for designing terrain
# rules and testing combat / physics in a known layout. The editor (`1` key)
# also skips its draft auto-load while this is on so the test arena isn't
# overwritten by a previous painting session.
const BATTLE_WORLD := true
const BATTLE_RECT := Rect2i(-40, -40, 80, 80)

const FOREST := "res://assets/forest"
const TileRules := preload("res://tile_rules.gd")

# Base ground pools - one chosen per cell deterministically from a hash.
var dirt_pool: Array[Texture2D] = []
var grass_pool: Array[Texture2D] = []
var grass_dark_pool: Array[Texture2D] = []
var stone_pool: Array[Texture2D] = []
var sand_pool: Array[Texture2D] = []
var wheat_pool: Array[Texture2D] = []
var mud_path_pool: Array[Texture2D] = []   # light indented dirt - walkable streams
var water_bed_pool: Array[Texture2D] = []  # deep indented dirt - water fills the dip

# Decoration overlays.
var tuft_pool: Array[Texture2D] = []           # small grass clumps on the floor
var flower_pool: Array[Texture2D] = []         # small flower decorations
var flora_small_pool: Array[Texture2D] = []    # standing small clumps
var tall_grass_pool: Array[Texture2D] = []     # walkable grass that sways
var scattered_stones_pool: Array[Texture2D] = []  # small rock decorations

# Prop pools.
var oak_tree_pool: Array[Texture2D] = []
var pine_tree_pool: Array[Texture2D] = []
var dead_tree_pool: Array[Texture2D] = []
var bush_pool: Array[Texture2D] = []
var log_pool: Array[Texture2D] = []
var sapling_pool: Array[Texture2D] = []
var hedge_maze_pool: Array[Texture2D] = []   # Tree B4/B5 hedge wall pieces

# Water: uses Ground C tiles whose dark portion is recolored to animated water.
# C3 = solid bed (interior), C2 = 2-edge corner, C1 = 1-edge (water side touches land).
const WATER_SHADER := preload("res://shaders/water.gdshader")
var water_solid_pool: Array[Texture2D] = []     # C3 (all 4 dirs)
var water_corner_dir: Dictionary = {}           # C2 - asset suffix preserved as direction key
var water_edge_dir: Dictionary = {}             # C1
# Ripple pools categorized by which diamond edge of the cell they decorate.
# Each value is an Array of frame Arrays (one per ripple variant).
var ripple_pools: Dictionary = {}

# River carves a winding water ridge; ocean is large noise-blob bodies.
var ocean_noise := FastNoiseLite.new()
var river_noise := FastNoiseLite.new()

# Hill cliff-edge tile pools, by directional suffix (E/N/S/W).
# G3 = corner (used for the 4 plateau corners), G1 = edge (used along edges).
var hill_corner_dir: Dictionary = {}   # G3 (outer convex corner) by suffix
var hill_fold_dir: Dictionary = {}     # G5 (inside-fold junction) by suffix
var hill_edge_dir: Dictionary = {}     # G1 (straight edge) by suffix
var hill_channel_dir: Dictionary = {}  # G4 (1-wide channel) by suffix

# Path-edge tile pools, keyed by the directional suffix N/S/E/W.
# Each direction is now an Array of textures (multiple family variants curated
# into the same folder), and we pick one per cell by hash.
var path_corner_dir: Dictionary = {}    # {"N": Array[Texture2D], ...}
var path_single_dir: Dictionary = {}

var tree_shadow_tex: Texture2D

const FLORA_SHADER := preload("res://shaders/flora_wind.gdshader")
const FROTH_SHADER := preload("res://shaders/ripple_froth.gdshader")
const BREATHE_SHADER := preload("res://shaders/breathe.gdshader")

# Flower families (each is the 4 directional variants of one flower TYPE).
# Built from decor/flowers/ so we can pick one consistent family per
# FLOWERS-biome pocket via species_noise instead of mixing types per cell.
var flower_families: Array = []   # Array of Array[Texture2D]
const ATTACK_RADIUS := 150.0
const ATTACK_HALF_ANGLE := 1.2   # radians (~69deg, ~138deg total cone)

@onready var game_viewport: SubViewport = $GameLayer/GameContainer/GameViewport
@onready var world: Node2D = $GameLayer/GameContainer/GameViewport/World
@onready var hud_label: Label = $HUD/Label
@onready var ambient: CanvasModulate = $GameLayer/GameContainer/GameViewport/Ambient
@onready var sun: DirectionalLight2D = $GameLayer/GameContainer/GameViewport/Sun
@onready var rain: CPUParticles2D = $Weather/Rain
@onready var clouds_root: Node2D = $GameLayer/GameContainer/GameViewport/Clouds
@onready var beams_rect: ColorRect = $Atmosphere/Beams

# Clouds live in world space at high z_index so the player walks under them
# and as they walk new "rows" of cloud come into view.
const CLOUD_COUNT := 18
const CLOUD_SPREAD := 3000.0         # world-space radius around the player
const CLOUD_RECYCLE_DIST := 3400.0   # if farther than this from player, recycle ahead
var clouds: Array[Sprite2D] = []
var cloud_velocities: Array[Vector2] = []
@onready var player_scene := preload("res://player.tscn")
const PLAYER_LAYERED_SCRIPT := preload("res://player_layered.gd")
# Player scene with a child CollisionShape2D you can drag visually in
# Godot's 2D editor. Replaces script-only .new() so the collision
# shape's position/radius are editable WITHOUT code edits.
const PLAYER_BODY_SCENE := preload("res://scenes/player_body.tscn")
# Painted-world hook. When true, main.gd loads scenes/world_painted.tscn
# under the World node and skips the chunk streamer + custom paint
# editor's arena.json. Player spawns at the spawn marker (or 0,0 if
# absent). Flip to false to fall back to the legacy chunk-streamed
# world while the painted scene is still under construction.
const USE_PAINTED_WORLD := true
const PAINTED_WORLD_SCENE := preload("res://scenes/world_painted.tscn")
var painted_world: Node2D = null
const EDITOR_SCENE := preload("res://editor.tscn")
var editor: Node

const INVENTORY_UI_SCRIPT := preload("res://inventory_ui.gd")
const Inventory := preload("res://inventory.gd")
const PROFILE_PATH := "user://profile.json"
var inventory_ui: Control = null
var player: Node2D
var hud_mode_text: String = "[F2] dusk"

# Per-chunk state.
var loaded_chunks: Dictionary = {}      # Vector2i -> Array[Sprite2D]
var blocked: Dictionary = {}            # Vector2i (cell) -> true
var flora_at: Dictionary = {}           # Vector2i (cell) -> Sprite2D
var last_player_chunk := Vector2i(99999, 99999)

# Noise sources. Same seed across runs for the moment so the world is reproducible
# while we iterate. Swap to randomized later if desired.
var biome_noise := FastNoiseLite.new()    # broad biome regions
var tree_noise := FastNoiseLite.new()     # high-freq detail (tufts, etc)
var forest_noise := FastNoiseLite.new()   # forest density (clusters trees, leaves clearings)
var path_noise := FastNoiseLite.new()     # carves winding dirt paths through the world
var species_noise := FastNoiseLite.new()  # very low freq - which tree species fills a forest pocket
var color_noise := FastNoiseLite.new()    # per-pocket HSV recolor offset (purple forests etc.)

func _ready() -> void:
	_init_noise()
	_load_textures()
	_setup_clouds()
	# Terrain physics + per-cell rules live in their own node. Instantiate
	# first so any spawned monster / player path can read lift values.
	terrain_lift = TerrainLiftScript.new()
	terrain_lift.main = self
	add_child(terrain_lift)
	# Mirror the rule dicts onto self so existing callers (editor.gd reads
	# main_ref.tile_paint_lift directly) keep working without code changes.
	# Dictionaries are reference types, so these are aliases of the same
	# storage owned by terrain_lift.
	tile_paint_lift = terrain_lift.tile_paint_lift
	tile_storey = terrain_lift.tile_storey
	tile_role_lift = terrain_lift.tile_role_lift
	tile_blocked = terrain_lift.tile_blocked
	_tile_height_maps = terrain_lift._tile_height_maps
	_painted_pixels = terrain_lift._painted_pixels
	# Always use the LayeredCharacter player (the character-creator
	# rig). Longbow archer is shelved while we iterate on the dungeon
	# / chest interactions / skill bar.
	# Instantiate the scene (not .new()) so the CollisionShape2D under
	# scenes/player_body.tscn comes along — that shape is editable in
	# Godot's 2D viewport (drag handles, change radius without code).
	player = PLAYER_BODY_SCENE.instantiate()
	# Parent the player into whichever world is active. y-sort only
	# compares siblings under a y_sort_enabled parent, so the player
	# must live at the SAME depth as the TileMapLayers it should
	# occlude/be-occluded-by.
	if USE_PAINTED_WORLD:
		painted_world = PAINTED_WORLD_SCENE.instantiate()
		world.add_child(painted_world)
		# Player lives on the FLORA TileMapLayer so it y-sorts directly
		# against trees and tall props. z_index = 2 lifts the player
		# above ground / grass / decor layers (which sit at z=0) so
		# flat tiles never occlude the body, only flora at the same
		# layer can hide it via y-sort.
		var flora_layer: Node = painted_world.get_node_or_null("flora")
		if flora_layer:
			flora_layer.add_child(player)
		else:
			painted_world.add_child(player)
		# Match the flora layer's z so trees and player share the same
		# z context — y-sort then governs depth within that layer
		# (canopy hides player north of trunk, player draws over canopy
		# south of trunk). Relative z = 0 on the player keeps it in
		# lockstep with whatever the flora layer is set to.
		# Match the global enemy z lift (+1 above flora) so player and
		# enemies share a z bucket and y-sort against each other normally
		# while always rendering above tall-grass / flora tiles.
		(player as Node2D).z_index = 1
		(player as Node2D).z_as_relative = true
		var spawn := painted_world.get_node_or_null("spawns/player_start")
		if spawn:
			player.position = (spawn as Marker2D).position
		else:
			player.position = Vector2.ZERO
		_spawn_overworld_skeletons(flora_layer if flora_layer else painted_world, player.position)
	else:
		# Legacy chunk-streamed world. Hardcoded battle-arena spawn at
		# iso cell (1, -36); arena.json overwrites once persistent.
		world.add_child(player)
		player.position = grid_to_screen(Vector2i(1, -36)) if BATTLE_WORLD else Vector2.ZERO
		# Editor overlay (toggled with key 1).
		editor = EDITOR_SCENE.instantiate()
		add_child(editor)
		editor.set("main_ref", self)
		if BATTLE_WORLD and editor.has_method("_load_arena"):
			if editor.has_method("_ensure_paint_root_on_world"):
				editor._ensure_paint_root_on_world()
			editor._load_arena()
			editor.set("_auto_loaded_draft", true)
			_apply_battle_terrain_rules()
			player.position = grid_to_screen(Vector2i(1, -36))
		_update_chunks()
	player.set("main", self)
	_set_lighting_mode(1)
	_spawn_combat_hud()
	# Goblin spawn disabled for now (paused while iterating on dungeon
	# layout and editor flow). Re-enable by uncommenting the call.
	# if BATTLE_WORLD:
	# 	_spawn_battle_goblins()

var overworld_skeletons: Array = []

func _spawn_overworld_skeletons(parent: Node, around: Vector2) -> void:
	# One of each of the 9 skeleton kinds for the demo.
	var kinds := [
		Skeleton.Kind.WARRIOR, Skeleton.Kind.ARCHER, Skeleton.Kind.WIZARD,
		Skeleton.Kind.BRUTE, Skeleton.Kind.DEATHLORD, Skeleton.Kind.DARK_KNIGHT,
		Skeleton.Kind.BERSERKER, Skeleton.Kind.DARK_ARCHER, Skeleton.Kind.NECROMANCER,
	]
	# All at the player's y-row so they share the same y-sort comparison
	# against any tall-grass tiles. x offsets fan them out left/right.
	for i in kinds.size():
		var sk := Skeleton.make(kinds[i], player)
		parent.add_child(sk)
		var dx: float = (i - 4) * 80.0
		sk.position = around + Vector2(dx, 0)
		overworld_skeletons.append(sk)

var monster_debug_panel: Control = null

# Combat
# Minimal generation: skip trees, bushes, logs, saplings, flowers, scattered
# stones, and small tufts. Keeps grass, tall grass, water, paths, hills.
const MINIMAL_GEN := true
# Hard kill-switch for the procedural generator. When true, _load_chunk
# places NO sprites at all — every tile you see comes from the editor's
# painted_base (loaded from arena.json on startup). Use this when you're
# hand-authoring the world and don't want the noise generator to fill in
# anything around your edits.
const NO_GEN := true

const PLAYER_MAX_HP := 100
const PLAYER_MAX_MP := 50
const SPIDER_HP := 45
const SPIDER_DAMAGE := 8
# PLAYER_ATTACK_DAMAGE removed — damage now flows through
# combat.gd::compute_player_damage(stats, loadout). Fist fallback
# (2-4 dmg) when no weapon equipped lives in combat.gd.
const _CombatScript := preload("res://combat.gd")
const WAVE_BASE_COUNT := 3
const WAVE_RING_RADIUS := 320.0

var player_hp: int = PLAYER_MAX_HP
var player_mp: int = PLAYER_MAX_MP
var combat_hud: CanvasLayer = null
# Player stats (level, XP, HP/MP, attribute points). Owned by main so
# every UI panel + combat path reads from one source.
const _CharacterStats := preload("res://character_stats.gd")
const _SkillDB := preload("res://skill_db.gd")
const _EnemyDB := preload("res://enemy_db.gd")
var stats: CharacterStats = _CharacterStats.new("warrior")
# Map combat_hud.tscn slot node names → SkillDB.Slot indices for input
# routing. Names are scene-fixed (relabeling text didn't rename nodes).
const _SLOT_NODE_BY_KEY: Dictionary = {
	"rmb":  "LmbSquare",     # left-most slot (now labeled RMB)
	"k1":   "RmbSquare",
	"k2":   "BeltSlot1",
	"k3":   "BeltSlot2",
	"k4":   "BeltSlot3",
	"k5":   "BeltSlot4",
}
var active_spiders: Array = []
var current_wave: int = 0
var spiders_remaining_in_wave: int = 0
var asset_placer: CanvasLayer = null
var world_shader_panel: CanvasLayer = null

const GOBLIN_SCRIPT := preload("res://goblin.gd")
var goblins: Array[Node2D] = []
var current_target_idx: int = -1

func _spawn_battle_goblins() -> void:
	# Drop a small pack near the player. Three melee variants (kinds 1, 2,
	# 4) plus the kind 3 archer who keeps distance and kites. They all
	# auto-target the player and stutter-step so they don't bunch.
	if player == null:
		return
	# Pack: only goblin_1 minions plus one goblin_boss. No archers / no
	# kind 2/3.
	var spawn_offsets: Array = [
		[1, Vector2( 160,  -80)],
		[1, Vector2(-160,  -60)],
		[1, Vector2( 220,   30)],
		[1, Vector2(-220,   60)],
		[1, Vector2(  90,  150)],
		[1, Vector2(-100,  150)],
		[1, Vector2( 280,  -40)],
		[1, Vector2(-280,  -10)],
		[4, Vector2(   0,  240)],   # boss south
	]
	for s in spawn_offsets:
		var g: Goblin = GOBLIN_SCRIPT.new()
		g.goblin_kind = int(s[0])
		g.target = player
		var is_boss_kind: bool = (g.goblin_kind == 4)
		g.max_hp = 320 if is_boss_kind else 70
		g.damage = 14 if is_boss_kind else 8
		g.move_speed = 95.0 if is_boss_kind else 130.0
		if g.goblin_kind == 4:
			g.is_boss = true
			g.aoe_attack_range = 110.0
			g.attack_cooldown = 1.6
			g.attack_windup = 0.6
			g.enrage_hp_threshold = 0.5
		g.add_to_group("goblin")
		g.died.connect(_on_goblin_died)
		world.add_child(g)
		g.position = player.position + (s[1] as Vector2)
		goblins.append(g)
	if goblins.size() > 0:
		current_target_idx = 0

func _refresh_goblin_target_marker() -> void:
	# Tab-target marker is now just the goblin's yellow outline (handled
	# in goblin.gd's _process), so this is a no-op kept as a hook for
	# future status indicators.
	pass

func _player_attack_target() -> void:
	var g := current_target_goblin()
	if g == null:
		return
	var dist := player.position.distance_to(g.global_position)
	if dist > 90.0:
		return   # out of melee range
	if g.has_method("take_damage"):
		g.take_damage(12)
	_camera_shake(2.0, 0.08)

func _on_goblin_died(_g) -> void:
	# Compact targeting list to surviving goblins.
	goblins = goblins.filter(func(x): return is_instance_valid(x) and not x.dead)
	if current_target_idx >= goblins.size():
		current_target_idx = goblins.size() - 1

func current_target_goblin() -> Node2D:
	if current_target_idx < 0 or current_target_idx >= goblins.size():
		return null
	var g = goblins[current_target_idx]
	if not is_instance_valid(g) or g.dead:
		return null
	return g

func _cycle_goblin_target(direction: int = 1) -> void:
	if goblins.is_empty():
		return
	var n := goblins.size()
	for _i in range(n):
		current_target_idx = (current_target_idx + direction + n) % n
		var g = goblins[current_target_idx]
		if is_instance_valid(g) and not g.dead:
			return


const BOSS_NAMES := [
	"Medieval_Bosses_Gollageth", "Medieval_Bosses_Haelerion", "Medieval_Bosses_Hive",
	"Medieval_Bosses_PrinceTaerron", "Medieval_Bosses_SunkenGod", "Medieval_Bosses_TheOldKing",
	"Medieval_Bosses_TheTriplets", "Medieval_Bosses_Witch",
]
var _next_boss_idx: int = 0

const BUILDING_PACKS := ["building_stone_1", "building_wood_1"]
var _building_pack_idx: int = 0

func _spawn_test_building() -> void:
	var Gen := load("res://building_generator.gd")
	var pack: String = BUILDING_PACKS[_building_pack_idx % BUILDING_PACKS.size()]
	_building_pack_idx += 1
	# Snap origin to a world iso cell 3 tiles north of the player (so the
	# building sits ON the world tile grid, not floating in screen-space).
	var player_cell: Vector2i = _screen_to_grid(player.position)
	var origin_cell := Vector2i(player_cell.x, player_cell.y - 5)
	var origin: Vector2 = grid_to_screen(origin_cell)
	Gen.generate(world, origin, 5, 4, pack, 2)
	print("spawned %s at iso %s" % [pack, str(origin_cell)])

func _spawn_next_boss() -> void:
	var Boss := load("res://boss_monster.gd")
	var b: Node2D = Boss.new()
	b.boss_name = BOSS_NAMES[_next_boss_idx % BOSS_NAMES.size()]
	b.display_size = 256.0
	b.wander = true
	world.add_child(b)
	b.position = player.position + Vector2(192, 0)
	b.set_direction(4)
	b.add_to_group("placed_shader_asset")
	print("spawned ", b.boss_name)
	_next_boss_idx += 1

func _toggle_world_shader_panel() -> void:
	if world_shader_panel == null:
		world_shader_panel = load("res://world_shader_panel.gd").new()
		world_shader_panel.main_ref = self
		add_child(world_shader_panel)
	world_shader_panel.toggle()

func _toggle_asset_placer() -> void:
	if asset_placer == null:
		asset_placer = load("res://asset_placer.gd").new()
		asset_placer.main_ref = self
		add_child(asset_placer)
	asset_placer.toggle()

var boss_hp_bar: CanvasLayer = null
var panels_ui: CanvasLayer = null

func _spawn_combat_hud() -> void:
	combat_hud = load("res://combat_hud.tscn").instantiate()
	# Pipe stats → HUD whenever they change. The HUD already exposes
	# set_player_stats / set_xp via combat_hud.gd.
	if stats:
		stats.connect("xp_changed", Callable(self, "_on_xp_changed"))
		stats.connect("hp_changed", Callable(self, "_on_hp_changed"))
		stats.connect("mp_changed", Callable(self, "_on_mp_changed"))
		stats.connect("level_changed", Callable(self, "_on_level_changed"))
		# Mirror current player resource state into the stats container
		# so the legacy `player_hp / player_mp` paths and the new stats
		# system stay in sync. Allocating Vit / Energy raises max_hp /
		# max_mp through stats; we use those getters everywhere now.
		player_hp = stats.max_hp()
		player_mp = stats.max_mp()
		# Push initial values so the bars don't sit at their default
		# state. Dynamic call() avoids parse-time identifier checks
		# (the methods are defined later in this file).
		call("_on_xp_changed", stats.xp, stats.xp_for_level(stats.level + 1))
		call("_on_hp_changed", stats.hp, stats.max_hp())
		call("_on_mp_changed", stats.mp, stats.max_mp())
	add_child(combat_hud)
	combat_hud.set_player_stats(player_hp, stats.max_hp(), player_mp, stats.max_mp())
	# Inventory / Character / Skills panels — wired so the HUD's UI button
	# row can toggle them (Character / Inventory / Skills buttons in the bar).
	panels_ui = load("res://panels_ui.gd").new()
	add_child(panels_ui)
	if combat_hud.has_method("bind_panels_ui"):
		combat_hud.bind_panels_ui(panels_ui)

func _start_next_wave() -> void:
	if spiders_remaining_in_wave > 0:
		return
	current_wave += 1
	var count: int = WAVE_BASE_COUNT + (current_wave - 1)
	spiders_remaining_in_wave = count
	for i in range(count):
		_spawn_spider(i, count)
	if combat_hud:
		combat_hud.set_wave_info(current_wave, spiders_remaining_in_wave)

func _spawn_spider(idx: int, count: int) -> void:
	var Monster := load("res://monster.gd")
	var tex: Texture2D = load("res://assets/shader_sprites/GiantSpider/Spritesheet.png")
	if Monster == null or tex == null:
		return
	var s: Node2D = Monster.new()
	s.spritesheet = tex
	s.display_size = 64.0
	s.hp = SPIDER_HP
	s.max_hp = SPIDER_HP
	s.damage = SPIDER_DAMAGE
	s.aggressive = true
	s.attack_range = 56.0
	s.chase_speed = 110.0
	world.add_child(s)
	var ang: float = (TAU / float(count)) * float(idx) + randf_range(-0.3, 0.3)
	s.position = player.position + Vector2(cos(ang), sin(ang)) * WAVE_RING_RADIUS
	s.target = player
	s.died.connect(_on_spider_died)
	active_spiders.append(s)
	s.play_anim("Idle", true)

func _on_spider_died(_m) -> void:
	spiders_remaining_in_wave = max(0, spiders_remaining_in_wave - 1)
	active_spiders = active_spiders.filter(func(x): return is_instance_valid(x) and not x.dead)
	if combat_hud:
		combat_hud.set_wave_info(current_wave, spiders_remaining_in_wave)

func take_player_damage(amount: int) -> void:
	if player and player.get("dodging"):
		return
	player_hp = max(0, player_hp - amount)
	if combat_hud:
		combat_hud.set_player_stats(player_hp, stats.max_hp(), player_mp, stats.max_mp())
	if player_hp <= 0:
		# Soft-reset for now: refill HP and clear current wave so testing keeps going.
		player_hp = stats.max_hp() if stats != null else PLAYER_MAX_HP
		for s in active_spiders:
			if is_instance_valid(s):
				s.queue_free()
		active_spiders.clear()
		spiders_remaining_in_wave = 0
		if combat_hud:
			combat_hud.set_player_stats(player_hp, stats.max_hp(), player_mp, stats.max_mp())
			combat_hud.set_wave_info(0, 0)

func _toggle_monster_debug_panel() -> void:
	if monster_debug_panel and is_instance_valid(monster_debug_panel):
		monster_debug_panel.visible = not monster_debug_panel.visible
	else:
		var Panel := load("res://monster_debug_panel.gd")
		var layer := CanvasLayer.new()
		layer.layer = 50
		add_child(layer)
		monster_debug_panel = Panel.new()
		layer.add_child(monster_debug_panel)
	# Hide trees while the panel is up so monsters aren't occluded.
	var trees_hidden: bool = monster_debug_panel.visible
	for t in get_tree().get_nodes_in_group("tree"):
		if t is CanvasItem:
			t.visible = not trees_hidden

func _toggle_inventory() -> void:
	if inventory_ui and is_instance_valid(inventory_ui):
		inventory_ui.queue_free()
		inventory_ui = null
		return
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var ui: Control = INVENTORY_UI_SCRIPT.new()
	layer.add_child(ui)
	inventory_ui = ui
	# Hand the live player loadout to the panel so the paper-doll +
	# backpack populate. Without this the panel renders blank since the
	# script's _loadout var is an empty dict by default.
	if player and "_loadout" in player and ui.has_method("open_with"):
		ui.open_with(player._loadout)
	ui.closed.connect(func():
		if is_instance_valid(layer):
			layer.queue_free()
		inventory_ui = null
		# Refresh the player after equipping changes (loadout was saved by UI).
		if player and player.has_method("reload_loadout"):
			player.reload_loadout()
	)

func _grant_random_item() -> void:
	var loadout := Loadout.load_or_default()
	Inventory.ensure_inventory(loadout)
	var catalog: Array = ItemsDB.build_catalog()
	# Filter to items the player doesn't already own and that aren't currently
	# equipped, biased toward shop/craft/loot tiers (not starter).
	var candidates: Array = []
	var owned: Array = Inventory.get_items(loadout)
	var equipped: Dictionary = {
		"head": String(loadout.get("head", "")),
		"chest": String(loadout.get("chest", "")),
		"legs": String(loadout.get("legs", "")),
		"shoes": String(loadout.get("shoes", "")),
		"hands": String(loadout.get("hands", "")),
		"belt": String(loadout.get("belt", "")),
		"bag": String(loadout.get("bag", "")),
		"mainhand": String(loadout.get("mainhand", "")),
		"offhand": String(loadout.get("offhand", "")),
	}
	for it in catalog:
		if it["source"] == "starter":
			continue
		var layer: String = ItemsDB.SLOT_LAYER.get(it["slot"], "")
		if equipped.get(layer, "") == it["folder"]:
			continue
		if owned.has(it["id"]):
			continue
		candidates.append(it)
	if candidates.is_empty():
		return
	var picked: Dictionary = candidates[randi() % candidates.size()]
	Inventory.add_item(loadout, picked["id"])
	Loadout.save(loadout)
	if hud_label:
		hud_label.text = "+ %s" % picked["display"]

func _setup_clouds() -> void:
	var cloud_dir := "res://assets/tilesets/Fantasy tileset - 2D Isometric V1.1/Fantasy tileset - 2D Isometric/Other"
	var c1: Texture2D = load("%s/Cloud1.png" % cloud_dir)
	var c2: Texture2D = load("%s/Cloud2.png" % cloud_dir)
	var pool: Array[Texture2D] = []
	if c1: pool.append(c1)
	if c2: pool.append(c2)
	if pool.is_empty():
		return
	for i in range(CLOUD_COUNT):
		var s := Sprite2D.new()
		s.texture = pool[i % pool.size()]
		s.centered = true
		s.z_as_relative = false
		s.z_index = 100
		s.position = Vector2(
			randf_range(-CLOUD_SPREAD, CLOUD_SPREAD),
			randf_range(-CLOUD_SPREAD, CLOUD_SPREAD)
		)
		s.scale = Vector2(randf_range(0.8, 1.3), randf_range(0.6, 0.95))
		s.modulate = Color(1.0, 1.0, 1.0, randf_range(0.04, 0.10))
		clouds_root.add_child(s)
		clouds.append(s)
		# Slow horizontal drift, near zero vertical.
		cloud_velocities.append(Vector2(randf_range(6.0, 16.0), randf_range(-1.0, 1.0)))

func _input(event: InputEvent) -> void:
	# LMB click → select / chest open.
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_try_open_chest_under_cursor()
	# RMB → activate the slot bound to RMB (basic attack).
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		_activate_skill_slot("rmb")
	# Number keys 1-5 → corresponding slot.
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: _activate_skill_slot("k1")
			KEY_2: _activate_skill_slot("k2")
			KEY_3: _activate_skill_slot("k3")
			KEY_4: _activate_skill_slot("k4")
			KEY_5: _activate_skill_slot("k5")
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			# Number row 1-4 is reserved for the player's hotbar (handled
			# in player_longbow.gd). Dev shortcuts moved to F11/F12/Shift+:
			KEY_F11:
				pass
			KEY_F12:
				_toggle_monster_debug_panel()
			KEY_N:
				# Start next wave (was KEY_4). N for "next wave".
				_start_next_wave()
			KEY_I:
				if panels_ui: panels_ui.toggle_inventory()
			KEY_C:
				if panels_ui: panels_ui.toggle_character()
			KEY_K:
				if panels_ui: panels_ui.toggle_skills()
			KEY_Q:
				# In the open world Q opens the portal dialog if we're
				# standing near one. Inside a dungeon Q is unused.
				if not in_dungeon and _has_portal_in_range():
					_show_portal_dialog()
			KEY_E:
				# Pick up the nearest LootDrop within PICKUP_RADIUS.
				_try_pickup_nearest_drop()
			KEY_ESCAPE:
				# Inside a dungeon ESC offers to leave. Outside it falls
				# through (engine default; nothing else listens here yet).
				if in_dungeon:
					_show_portal_dialog()
			KEY_T:
				# Dungeon-edit: toggle wall transparency on the cell
				# under the cursor. Off by default (generation no longer
				# auto-applies it); flip it on for walls the player
				# should be able to see through.
				if in_dungeon and dungeon:
					var c: Vector2i = _screen_to_grid(player.get_global_mouse_position())
					dungeon.toggle_wall_transparent(c)
			KEY_DELETE:
				# Dungeon-edit: delete the cell under the cursor.
				if in_dungeon and dungeon:
					var c: Vector2i = _screen_to_grid(player.get_global_mouse_position())
					dungeon.delete_cell(c)
			KEY_G:
				# Debug: grant a random non-starter item so inventory has content
				# to work with before shops/loot are wired up.
				_grant_random_item()
			# --- Dev / debug F-row -------------------------------------------
			# Number row 1-9 / 0 reserved for hotbar; tooling lives on F-keys.
			KEY_F1:
				# F1 opens the editor. Inside a dungeon the palette is
				# filtered to dungeon tiles (Walls, Stone, Misc, Chest,
				# Ground A1/D1/E1). Outside it shows everything.
				if editor:
					editor.dungeon_mode = in_dungeon
					editor.toggle()
					if editor.has_method("_init_dropdowns"):
						editor._init_dropdowns()
			KEY_F2: _set_lighting_mode(1)
			KEY_F3: _set_lighting_mode(2)
			KEY_F4: _set_lighting_mode(3)
			KEY_F5: _set_lighting_mode(4)
			KEY_F6: _toggle_world_shader_panel()
			KEY_F8:
				# Inside a dungeon F8 saves the layout to draft_Dungeon;
				# outside it toggles cloud visibility (the original dev
				# binding).
				if in_dungeon and dungeon:
					dungeon.save_draft()
					print("[dungeon] saved draft to ", dungeon.DRAFT_PATH)
				else:
					clouds_root.visible = not clouds_root.visible
			KEY_F9: _spawn_next_boss()
			KEY_F10: _spawn_test_building()

func _set_lighting_mode(m: int) -> void:
	var lantern_energy: float = 0.0
	var sun_energy: float = 0.0
	var sun_color := Color(1, 0.97, 0.88)
	match m:
		1:
			ambient.color = Color(0.92, 0.94, 0.98)
			sun_energy = 0.45
			sun_color = Color(1.0, 0.97, 0.86)
			hud_mode_text = "[F1] daylight + shadows"
		2:
			ambient.color = Color(0.78, 0.82, 0.92)
			hud_mode_text = "[F2] overcast"
		3:
			ambient.color = Color(0.32, 0.36, 0.5)
			lantern_energy = 1.6
			hud_mode_text = "[F3] night + lantern"
		4:
			ambient.color = Color(0.06, 0.06, 0.12)
			lantern_energy = 2.4
			hud_mode_text = "[F4] pitch black"
	sun.energy = sun_energy
	sun.color = sun_color
	sun.visible = sun_energy > 0.0
	beams_rect.visible = false
	# Atmosphere effects: clouds drift in daylight/overcast; beams disabled.
	clouds_root.visible = (m == 1 or m == 2)
	beams_rect.visible = false
	if player and is_instance_valid(player):
		var lantern: PointLight2D = player.get_node_or_null("Lantern")
		if lantern:
			lantern.energy = lantern_energy
			lantern.visible = lantern_energy > 0.0

func _toggle_rain() -> void:
	rain.emitting = not rain.emitting

func _process(dt: float) -> void:
	# In dungeon mode the world's chunk streamer + cloud drift are
	# irrelevant — skipping them removes a per-frame chunk-distance
	# walk and a sprite-position update across cloud sprites that the
	# player can't even see.
	if not in_dungeon:
		_update_chunks()
		_drift_clouds(dt)
	if player and is_instance_valid(player):
		var cell := _screen_to_grid(player.position)
		hud_label.text = "%s\nplayer cell: %s    chunks: %d" % [hud_mode_text, str(cell), loaded_chunks.size()]
		# Carry the dark transparent-wall tint over to the player when
		# they stand on one of those cells.
		if in_dungeon and dungeon and dungeon.transparent_walls.has(cell):
			(player as CanvasItem).modulate = Color(0.55, 0.55, 0.62, 1.0)
		else:
			(player as CanvasItem).modulate = Color(1, 1, 1, 1)
		# Same rule for ALL enemies in the dungeon — goblins, skeletons,
		# spiders, anything in the "enemy" group. Avoids per-class code
		# in goblin.gd / spider.gd / skeleton.gd having to re-implement
		# the same behaviour.
		# In dungeon mode the enemies-tint pass runs over the dungeon's
		# own skeleton list (cheaper than scanning groups every frame).
		if in_dungeon and dungeon and "skeletons" in dungeon:
			for sk in dungeon.skeletons:
				_apply_enemy_wall_tint(sk)
	# Mouse-hover enemy highlight (Diablo-style targeting reticle).
	_hover_throttle -= dt
	if _hover_throttle <= 0.0:
		_hover_throttle = HOVER_UPDATE_INTERVAL
		_update_hovered_enemy()
	# Camera shake decay (Diablo-style hit feedback).
	if player and player.has_node("Camera2D"):
		var cam: Camera2D = player.get_node("Camera2D")
		if _shake_left > 0.0:
			_shake_left -= dt
			var k: float = clamp(_shake_left / 0.18, 0.0, 1.0)
			cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake_amp * k
		elif cam.offset != Vector2.ZERO:
			cam.offset = Vector2.ZERO

func _drift_clouds(dt: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var ppos: Vector2 = player.position
	for i in clouds.size():
		var s: Sprite2D = clouds[i]
		s.position += cloud_velocities[i] * dt
		# Recycle clouds that have drifted (or been left behind) far from the
		# player back to the opposite side, so the world always has cover.
		var off: Vector2 = s.position - ppos
		if off.length() > CLOUD_RECYCLE_DIST:
			# Reposition to a fresh band on the upwind side of the player.
			s.position = ppos + Vector2(
				-CLOUD_SPREAD,
				randf_range(-CLOUD_SPREAD, CLOUD_SPREAD)
			)

# ---- iso math ---------------------------------------------------------------

func grid_to_screen(g: Vector2i) -> Vector2:
	return Vector2(
		(g.x - g.y) * (TILE_W * 0.5),
		(g.x + g.y) * (TILE_H * 0.5)
	)

func _screen_to_grid(p: Vector2) -> Vector2i:
	var tw: float = TILE_W * 0.5
	var th: float = TILE_H * 0.5
	var gx: float = (p.x / tw + p.y / th) * 0.5
	var gy: float = (p.y / th - p.x / tw) * 0.5
	return Vector2i(int(floor(gx)), int(floor(gy)))

func is_blocked(cell: Vector2i) -> bool:
	# Inside a dungeon ONLY consult dungeon state. World blocking dicts
	# carry stale forest entries that overlap dungeon coords. Block:
	#   - void cells (no floor under them)
	#   - opaque wall cells (those NOT in transparent_walls)
	# Transparent wall cells stay walkable so the player can stand
	# under translucent front walls.
	if in_dungeon and dungeon:
		if not dungeon.floor_cells.has(cell):
			return true
		if dungeon.wall_cells.has(cell) and not dungeon.transparent_walls.has(cell):
			return true
		return false
	return blocked.has(cell)

# Walls (hedge, hill cliff, …) use sprites that extend ~2 iso-tiles UP from
# the placement-cell foot AND a fraction below it (texture is centred on
# offset −82 with `centered = true`, so a tall texture reaches both ways).
# Block the placement cell PLUS its four screen-vertical neighbours so the
# player can't slip onto the visual base or behind the visual top.
#   N  on screen = (c-1, r-1)         ↑ one tile-height up
#   NE/NW on screen = (c-1, r) / (c, r-1)   ↗↖ half-height up
#   S  on screen = (c+1, r+1)         ↓ one tile-height down
func _block_wall_cell(cell: Vector2i) -> void:
	blocked[cell] = true
	blocked[Vector2i(cell.x - 1, cell.y - 1)] = true
	blocked[Vector2i(cell.x - 1, cell.y)] = true
	blocked[Vector2i(cell.x, cell.y - 1)] = true
	blocked[Vector2i(cell.x + 1, cell.y + 1)] = true

# ---- noise ------------------------------------------------------------------

func _init_noise() -> void:
	# Biome noise: continent-scale. Each biome region spans hundreds of cells -
	# you walk for a while before crossing into the next biome.
	biome_noise.seed = 1337
	biome_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	biome_noise.frequency = 0.003
	biome_noise.fractal_octaves = 2
	tree_noise.seed = 4242
	tree_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	tree_noise.frequency = 0.18
	# Forest density: smaller-scale variation INSIDE a forest biome -
	# denser cores, softer edges, occasional clearings.
	forest_noise.seed = 909
	forest_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	forest_noise.frequency = 0.012
	forest_noise.fractal_octaves = 2
	# Species noise: one species per ~500-cell stretch so an entire forest is
	# the same tree type.
	species_noise.seed = 1212
	species_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	species_noise.frequency = 0.002
	species_noise.fractal_octaves = 1
	# Color noise: also low-frequency, drives per-pocket HSV recolor so
	# different forest/flower regions read as different color tones (e.g.
	# a purple woods next to a default-green woods).
	color_noise.seed = 5151
	color_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	color_noise.frequency = 0.0015
	color_noise.fractal_octaves = 1
	# Path noise: a single layer; the path lies along its zero crossing (a ridge).
	path_noise.seed = 7777
	path_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	path_noise.frequency = 0.020
	path_noise.fractal_octaves = 2
	# Maze noise kept around as a fallback though the active maze layout
	# now uses a deterministic hash-grid (see _maze_rect_for).
	maze_noise.seed = 31415
	maze_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	maze_noise.frequency = 0.004
	maze_noise.fractal_octaves = 2
	# Ocean: large rare bodies of water.
	ocean_noise.seed = 12121
	ocean_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ocean_noise.frequency = 0.0035
	ocean_noise.fractal_octaves = 2
	# River: ridge of noise carves a winding waterway.
	river_noise.seed = 33333
	river_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	river_noise.frequency = 0.011
	river_noise.fractal_octaves = 2

func _path_strength(cell: Vector2i) -> float:
	var v: float = path_noise.get_noise_2d(float(cell.x), float(cell.y))
	var d: float = abs(v)
	# Path width: a slow-varying noise fattens or narrows the path along its
	# length. A second very-low-frequency noise picks "road" stretches where
	# the path stays consistently narrow so each cell ends up with grass on
	# both perpendicular sides (= edges on both sides via the opposite-edge mask).
	var w_noise: float = path_noise.get_noise_2d(float(cell.x) * 0.18 + 91.0, float(cell.y) * 0.18 - 41.0)
	var road_noise: float = path_noise.get_noise_2d(float(cell.x) * 0.04 + 333.0, float(cell.y) * 0.04 - 217.0)
	var is_road: bool = road_noise > 0.05
	var width: float
	if is_road:
		# Wider, consistent road -> 3+ cells across so the centerline stays
		# pure dirt and only the outermost cells get edge tiles
		# (edge | dirt | edge structure).
		width = lerp(0.045, 0.075, clamp(w_noise * 0.5 + 0.5, 0.0, 1.0))
	else:
		# Narrow rustic trail -> 1-2 cells, edges hug close on both sides.
		width = lerp(0.020, 0.035, clamp(w_noise * 0.5 + 0.5, 0.0, 1.0))
	if d > width:
		return 0.0
	return 1.0 - (d / width)

# Editor-stamped path cells override the procedural noise. Populated by
# paint_path_at(). _has_grass_cover and _is_on_path both consult this.
var path_cells_override: Dictionary = {}
# Cells the editor explicitly turned OFF (right-click on a procedurally
# generated path). _is_on_path returns false for these even though the
# noise might say otherwise.
var path_cells_force_off: Dictionary = {}

func _is_on_path(cell: Vector2i) -> bool:
	if path_cells_force_off.has(cell):
		return false
	if path_cells_override.has(cell):
		return true
	return _path_strength(cell) > 0.0 or _is_on_straight_road(cell)

# Straight cardinal/diagonal roads laid on a coarse grid. The two axes are:
#   gx - gy  (lines of constant difference -> screen-horizontal road)
#   gx + gy  (lines of constant sum        -> screen-vertical road)
# Every STRAIGHT_ROAD_SPACING units along either axis there's a band of width
# STRAIGHT_ROAD_WIDTH that becomes road. Hash-gated per band so not every
# slot turns into a road - some areas stay rural.
const STRAIGHT_ROAD_SPACING := 100
const STRAIGHT_ROAD_WIDTH := 2
const STRAIGHT_ROAD_CHANCE := 0.20

func _is_on_straight_road(cell: Vector2i) -> bool:
	# East-west axis (gx - gy constant).
	var ew_axis: int = cell.x - cell.y
	var ew_band: int = int(floor(float(ew_axis) / float(STRAIGHT_ROAD_SPACING)))
	var ew_off: int = ew_axis - ew_band * STRAIGHT_ROAD_SPACING
	if ew_off < STRAIGHT_ROAD_WIDTH \
		and _hash01(Vector2i(ew_band, 0), 33333) < STRAIGHT_ROAD_CHANCE:
		return true
	# North-south axis (gx + gy constant).
	var ns_axis: int = cell.x + cell.y
	var ns_band: int = int(floor(float(ns_axis) / float(STRAIGHT_ROAD_SPACING)))
	var ns_off: int = ns_axis - ns_band * STRAIGHT_ROAD_SPACING
	if ns_off < STRAIGHT_ROAD_WIDTH \
		and _hash01(Vector2i(0, ns_band), 44444) < STRAIGHT_ROAD_CHANCE:
		return true
	return false

# ---- Clearings: large dirt circles seeded at a jittered grid -----------------

const CLEARING_GRID := 60
const CLEARING_CHANCE := 0.20
const CLEARING_RADIUS_MIN := 4
const CLEARING_RADIUS_MAX := 8

func _clearing_strength(cell: Vector2i) -> float:
	# Returns 0..1 - how far inside a clearing this cell sits. 0 = outside.
	# Check the 9 nearest grid slots so cells near a slot boundary still see it.
	var gx: int = int(floor(float(cell.x) / float(CLEARING_GRID)))
	var gy: int = int(floor(float(cell.y) / float(CLEARING_GRID)))
	var best: float = 0.0
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var sg := Vector2i(gx + dx, gy + dy)
			# Does this grid slot host a clearing?
			if _hash01(sg, 5500) > CLEARING_CHANCE:
				continue
			# Jittered center within the slot.
			var jx: float = _hash01(sg, 5501)
			var jy: float = _hash01(sg, 5502)
			var center := Vector2(
				(float(sg.x) + jx) * float(CLEARING_GRID),
				(float(sg.y) + jy) * float(CLEARING_GRID)
			)
			var radius: float = lerp(
				float(CLEARING_RADIUS_MIN),
				float(CLEARING_RADIUS_MAX),
				_hash01(sg, 5503)
			)
			var d: float = Vector2(cell.x, cell.y).distance_to(center)
			if d < radius:
				var s: float = 1.0 - (d / radius)
				if s > best:
					best = s
	return best

func _is_in_clearing(cell: Vector2i) -> bool:
	return _clearing_strength(cell) > 0.0

# ---- texture loading --------------------------------------------------------

func _load_textures() -> void:
	# Base ground pools: every PNG in each folder becomes a candidate.
	dirt_pool       = _load_pool("%s/ground/dirt"       % FOREST)
	grass_pool      = _load_pool("%s/ground/grass"      % FOREST)
	grass_dark_pool = _load_pool("%s/ground/grass_dark" % FOREST)
	stone_pool      = _load_pool("%s/ground/stone"      % FOREST)
	sand_pool       = _load_pool("%s/ground/sand"       % FOREST)
	wheat_pool      = _load_pool("%s/ground/wheat"      % FOREST)
	mud_path_pool   = _load_pool("%s/ground/mud_path"   % FOREST)
	water_bed_pool  = _load_pool("%s/ground/water_bed"  % FOREST)
	# Overlays
	tuft_pool             = _load_pool("%s/decor/tufts"             % FOREST)
	flower_pool           = _load_pool("%s/decor/flowers"           % FOREST)
	# Build family-grouped flower lookup: filename "Ground A22_E.png" -> family "Ground A22"
	var flower_dir := "%s/decor/flowers" % FOREST
	var fd := DirAccess.open(flower_dir)
	if fd != null:
		var fams: Dictionary = {}
		fd.list_dir_begin()
		var fn: String = fd.get_next()
		while fn != "":
			if not fd.current_is_dir() and fn.ends_with(".png"):
				# Strip "_<X>.png" (6 chars) to get the family name.
				var fam_name: String = fn.substr(0, fn.length() - 6)
				if not fams.has(fam_name):
					fams[fam_name] = []
				var t: Texture2D = load("%s/%s" % [flower_dir, fn])
				if t != null:
					fams[fam_name].append(t)
			fn = fd.get_next()
		fd.list_dir_end()
		for k in fams.keys():
			if (fams[k] as Array).size() > 0:
				flower_families.append(fams[k])
	flora_small_pool      = _load_pool("%s/decor/flora_small"       % FOREST)
	tall_grass_pool       = _load_pool("%s/decor/tall_grass"        % FOREST)
	scattered_stones_pool = _load_pool("%s/decor/scattered_stones"  % FOREST)
	# Props
	oak_tree_pool  = _load_pool("%s/props/trees/oak"  % FOREST)
	pine_tree_pool = _load_pool("%s/props/trees/pine" % FOREST)
	dead_tree_pool = _load_pool("%s/props/trees/dead" % FOREST)
	bush_pool      = _load_pool("%s/props/bushes"     % FOREST)
	log_pool       = _load_pool("%s/props/logs"       % FOREST)
	sapling_pool   = _load_pool("%s/props/saplings"   % FOREST)
	hedge_maze_pool = _load_pool("%s/structures/hedge_maze" % FOREST)
	# Water tiles: C3 solid bed + C2 corner + C1 edge, all from ground/water_bed.
	var wb := "%s/ground/water_bed" % FOREST
	for d in ["N", "S", "E", "W"]:
		var c3: Texture2D = load("%s/Ground C3_%s.png" % [wb, d])
		if c3 != null: water_solid_pool.append(c3)
		var c2: Texture2D = load("%s/Ground C2_%s.png" % [wb, d])
		if c2 != null: water_corner_dir[d] = c2
		var c1: Texture2D = load("%s/Ground C1_%s.png" % [wb, d])
		if c1 != null: water_edge_dir[d] = c1
	# Hill cliff-edge tiles: G3 = outer convex corner, G5 = inside-fold junction,
	# G1 = straight edge, G4 = 1-wide channel, all by directional suffix.
	var hd := "%s/elevation/dirt" % FOREST
	for d in ["N", "S", "E", "W"]:
		var g3: Texture2D = load("%s/Ground G3_%s.png" % [hd, d])
		if g3 != null: hill_corner_dir[d] = g3
		var g1: Texture2D = load("%s/Ground G1_%s.png" % [hd, d])
		if g1 != null: hill_edge_dir[d] = g1
		var g5: Texture2D = load("%s/Ground G5_%s.png" % [hd, d])
		if g5 != null: hill_fold_dir[d] = g5
		var g4: Texture2D = load("%s/Ground G4_%s.png" % [hd, d])
		if g4 != null: hill_channel_dir[d] = g4
	# Ripple variants categorized by which diamond edge of the cell they decorate.
	# Asset analysis (alpha quadrant counts for frame 0001):
	#   WR1  = small bottom dot      -> "interior"
	#   WR2,4,10 = NE corner ripples -> "NE"
	#   WR3,5,11 = NW corner ripples -> "NW"
	#   WR6  = top edge (NE+NW)      -> "top"
	#   WR7  = left edge (NW+SW)     -> "left"
	#   WR8  = bottom edge (SE+SW)   -> "bottom"
	#   WR9  = right edge (NE+SE)    -> "right"
	#   WR12 = NE diagonal sweep     -> "NE"
	#   WR13 = NW diagonal sweep     -> "NW"
	const RIPPLE_BUCKETS := {
		"Ripple1":  "interior",
		"Ripple2":  "NE", "Ripple4":  "NE", "Ripple10": "NE", "Ripple12": "NE",
		"Ripple3":  "NW", "Ripple5":  "NW", "Ripple11": "NW", "Ripple13": "NW",
		"Ripple6":  "top",
		"Ripple7":  "left",
		"Ripple8":  "bottom",
		"Ripple9":  "right",
	}
	for bucket in ["interior", "NE", "NW", "SE", "SW", "top", "bottom", "left", "right"]:
		ripple_pools[bucket] = []
	var ripple_root := "%s/decor/water_ripples" % FOREST
	for sub in RIPPLE_BUCKETS.keys():
		var dir_path := "%s/%s" % [ripple_root, sub]
		var sd := DirAccess.open(dir_path)
		if sd == null:
			continue
		var names: Array = []
		sd.list_dir_begin()
		var fn: String = sd.get_next()
		while fn != "":
			if not sd.current_is_dir() and fn.ends_with(".png"):
				names.append(fn)
			fn = sd.get_next()
		sd.list_dir_end()
		names.sort()
		var frames: Array[Texture2D] = []
		for n in names:
			var t: Texture2D = load("%s/%s" % [dir_path, n])
			if t != null:
				frames.append(t)
		if frames.size() > 0:
			ripple_pools[RIPPLE_BUCKETS[sub]].append(frames)
	# SE / SW have no dedicated ripple; mirror with bottom/right etc.
	if ripple_pools["SE"].is_empty():
		ripple_pools["SE"] = ripple_pools["right"] + ripple_pools["bottom"]
	if ripple_pools["SW"].is_empty():
		ripple_pools["SW"] = ripple_pools["left"] + ripple_pools["bottom"]
	# Path edges - keep directional grouping, but each direction is now a pool.
	path_corner_dir = _load_directional_pools("%s/edges/grass_corner" % FOREST)
	path_single_dir = _load_directional_pools("%s/edges/grass_single" % FOREST)
	# Special
	tree_shadow_tex = load("%s/decor/shadows/Tree Shadow.png" % FOREST)
	print("Loaded forest pools - grass:%d dirt:%d trees(oak):%d trees(pine):%d trees(dead):%d bushes:%d tufts:%d flowers:%d tall_grass:%d stones:%d edges_corner_per_dir:[%d %d %d %d] edges_single_per_dir:[%d %d %d %d]" % [
		grass_pool.size(), dirt_pool.size(),
		oak_tree_pool.size(), pine_tree_pool.size(), dead_tree_pool.size(),
		bush_pool.size(), tuft_pool.size(), flower_pool.size(), tall_grass_pool.size(),
		scattered_stones_pool.size(),
		path_corner_dir.get("N", []).size(), path_corner_dir.get("S", []).size(),
		path_corner_dir.get("E", []).size(), path_corner_dir.get("W", []).size(),
		path_single_dir.get("N", []).size(), path_single_dir.get("S", []).size(),
		path_single_dir.get("E", []).size(), path_single_dir.get("W", []).size(),
	])

# Generic: load every .png in a folder (non-recursive) as a flat pool.
func _load_pool(folder: String) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var d := DirAccess.open(folder)
	if d == null:
		push_warning("Folder missing: %s" % folder)
		return out
	d.list_dir_begin()
	var fname: String = d.get_next()
	while fname != "":
		if not d.current_is_dir() and fname.ends_with(".png"):
			var t: Texture2D = load("%s/%s" % [folder, fname])
			if t != null:
				out.append(t)
		fname = d.get_next()
	d.list_dir_end()
	return out

# Directional pools: bucket files in `folder` by their _N/_S/_E/_W suffix.
func _load_directional_pools(folder: String) -> Dictionary:
	var out: Dictionary = {"N": [] as Array[Texture2D], "S": [] as Array[Texture2D],
						  "E": [] as Array[Texture2D], "W": [] as Array[Texture2D]}
	var d := DirAccess.open(folder)
	if d == null:
		return out
	d.list_dir_begin()
	var fname: String = d.get_next()
	while fname != "":
		if not d.current_is_dir() and fname.ends_with(".png"):
			for k in ["N", "S", "E", "W"]:
				if fname.ends_with("_%s.png" % k):
					var t: Texture2D = load("%s/%s" % [folder, fname])
					if t != null:
						out[k].append(t)
					break
		fname = d.get_next()
	d.list_dir_end()
	return out

# ---- chunk streaming --------------------------------------------------------

func _player_chunk() -> Vector2i:
	var cell := _screen_to_grid(player.position) if player else Vector2i.ZERO
	return Vector2i(int(floor(float(cell.x) / CHUNK_SIZE)), int(floor(float(cell.y) / CHUNK_SIZE)))

func _update_chunks() -> void:
	if player == null:
		return
	if BATTLE_WORLD:
		# Bounded arena: load every chunk overlapping BATTLE_RECT once, never
		# unload. The player's position is irrelevant to chunk membership.
		if not loaded_chunks.is_empty() and last_player_chunk == Vector2i(-1, -1):
			return
		last_player_chunk = Vector2i(-1, -1)
		var cx0: int = int(floor(float(BATTLE_RECT.position.x) / CHUNK_SIZE))
		var cy0: int = int(floor(float(BATTLE_RECT.position.y) / CHUNK_SIZE))
		var cx1: int = int(floor(float(BATTLE_RECT.position.x + BATTLE_RECT.size.x - 1) / CHUNK_SIZE))
		var cy1: int = int(floor(float(BATTLE_RECT.position.y + BATTLE_RECT.size.y - 1) / CHUNK_SIZE))
		for cx in range(cx0, cx1 + 1):
			for cy in range(cy0, cy1 + 1):
				var cv := Vector2i(cx, cy)
				if not loaded_chunks.has(cv):
					_load_chunk(cv)
		return
	var pc := _player_chunk()
	if pc == last_player_chunk:
		return
	last_player_chunk = pc

	# Determine desired chunk set.
	var desired: Dictionary = {}
	for dx in range(-VIEW_RADIUS_CHUNKS, VIEW_RADIUS_CHUNKS + 1):
		for dy in range(-VIEW_RADIUS_CHUNKS, VIEW_RADIUS_CHUNKS + 1):
			desired[Vector2i(pc.x + dx, pc.y + dy)] = true

	# Unload chunks no longer in range.
	for cv in loaded_chunks.keys():
		if not desired.has(cv):
			_unload_chunk(cv)

	# Load missing chunks.
	for cv in desired.keys():
		if not loaded_chunks.has(cv):
			_load_chunk(cv)

# Editor support: remove every sprite the generator placed at one cell. Returns
# the number of nodes freed. Walks only the chunk that owns the cell, so cost
# is bounded regardless of how many chunks are streamed.
# Cells the user erased in the editor. The chunk loader skips these so
# procedural generation doesn't refill empty tiles when chunks stream
# back in.
var empty_cells_override: Dictionary = {}

func erase_world_cell(cell: Vector2i) -> int:
	# Mark the cell as user-emptied so future chunk loads skip it.
	empty_cells_override[cell] = true
	var cv := Vector2i(int(floor(float(cell.x) / CHUNK_SIZE)),
					   int(floor(float(cell.y) / CHUNK_SIZE)))
	if not loaded_chunks.has(cv):
		return 0
	var target: Vector2 = grid_to_screen(cell)
	var keep: Array = []
	var removed: int = 0
	for s in loaded_chunks[cv]:
		if not is_instance_valid(s):
			continue
		# Sprites are anchored at the cell pivot via grid_to_screen(cell), so
		# Sprite2D.position is the authoritative match key.
		if s.position.distance_to(target) < 1.0:
			s.queue_free()
			removed += 1
		else:
			keep.append(s)
	loaded_chunks[cv] = keep
	if removed > 0:
		blocked.erase(cell)
		flora_at.erase(cell)
	return removed

func _unload_chunk(cv: Vector2i) -> void:
	var sprites: Array = loaded_chunks.get(cv, [])
	for s in sprites:
		if is_instance_valid(s):
			s.queue_free()
	loaded_chunks.erase(cv)
	# Drop any blocked / flora references inside this chunk.
	var origin := Vector2i(cv.x * CHUNK_SIZE, cv.y * CHUNK_SIZE)
	for x in range(CHUNK_SIZE):
		for y in range(CHUNK_SIZE):
			var c := Vector2i(origin.x + x, origin.y + y)
			blocked.erase(c)
			flora_at.erase(c)
			destructibles.erase(c)
			if terrain_lift:
				terrain_lift.unregister_tree(c)

func _load_chunk(cv: Vector2i) -> void:
	var sprites: Array = []
	# When the generator is fully disabled the chunk's still tracked so
	# unload bookkeeping works, but no procedural sprites are placed.
	# The editor restores painted tiles on startup independently.
	if NO_GEN:
		loaded_chunks[cv] = sprites
		return
	var origin := Vector2i(cv.x * CHUNK_SIZE, cv.y * CHUNK_SIZE)
	for x in range(CHUNK_SIZE):
		for y in range(CHUNK_SIZE):
			var cell := Vector2i(origin.x + x, origin.y + y)
			# Hard-bound the battle arena: cells outside BATTLE_RECT render
			# nothing, giving a clean edge to the test world.
			if BATTLE_WORLD and not BATTLE_RECT.has_point(cell):
				continue
			# User-emptied cells — left blank on purpose, never re-fill.
			if empty_cells_override.has(cell):
				continue
			# Water cells short-circuit everything else.
			if _is_water(cell):
				_place_water_cell(cell, sprites)
				continue
			# Hill cells get their own ground stack (dirt + grass + cliff edge);
			# the rest of the cell loop's tree/decor placement still runs but
			# is gated to keep props off the cliff perimeter.
			if _is_hill(cell):
				_place_hill_cell(cell, sprites)
				_finish_hill_cell(cell, sprites)
				continue
			# Layer 0: dirt base under EVERY cell. Anything on top with
			# transparent areas falls back to dirt cleanly.
			var ds := _make_sprite(_pick(dirt_pool, cell, 11), cell)
			ds.z_index = -2
			world.add_child(ds)
			sprites.append(ds)

			var has_grass := _has_grass_cover(cell)

			# Layer 1: grass on top of dirt for any non-path/non-clearing cell.
			if has_grass:
				var gs := _make_sprite(_pick(grass_pool, cell, 23), cell)
				gs.z_index = -1
				world.add_child(gs)
				sprites.append(gs)

			# Path-edge overlays only on dirt (path/clearing) cells.
			if not has_grass:
				_maybe_place_path_edges(cell, sprites)

			var biome: int = _biome_for(cell)
			var is_grass := has_grass   # alias used by helpers below
			# Tall grass: plains has scattered fields, forest cells almost
			# always have tall grass between the trees (creates a continuous
			# undergrowth carpet that solidifies the forest edge).
			var tall_grass_density: float = 0.0
			match biome:
				BIOME_PLAINS:  tall_grass_density = 0.30
				BIOME_FOREST:  tall_grass_density = 0.92
			var place_tall_grass := is_grass and tall_grass_density > 0.0 \
				and not tall_grass_pool.is_empty() \
				and _hash01(cell, 31337) < tall_grass_density \
				and not _will_be_tree(cell) \
				and not _is_on_path(cell)
			# Tufts (Ground A6/A7/A8 patches): plains only as standalone, plus
			# under tall grass in any biome to give it a base. Forests should
			# read as tall-grass-everywhere, NOT a checkerboard of small patches.
			var place_tuft := false
			if is_grass and place_tall_grass:
				place_tuft = true
			elif is_grass and biome == BIOME_PLAINS:
				place_tuft = _should_place_tuft(cell)
			# Flowers cover most of the FLOWERS biome ground; only dotted elsewhere.
			var flower_density: float = 0.7 if biome == BIOME_FLOWERS else 0.03
			var place_flower := is_grass and not place_tall_grass and not flower_pool.is_empty() and _hash01(cell, 51) < flower_density
			# Small flora dots non-flower biomes; in BIOME_FLOWERS we keep the
			# field a single flower type so DON'T fill gaps with mixed flora.
			var small_flora_density: float = 0.0 if biome == BIOME_FLOWERS else 0.06
			var place_small_flora := is_grass and not place_tall_grass and not place_flower and not flora_small_pool.is_empty() and _hash01(cell, 53) < small_flora_density
			# Scattered stones on forest floor; occasional in flower fields.
			var stone_density: float = 0.0
			match biome:
				BIOME_FOREST:  stone_density = 0.025
				BIOME_FLOWERS: stone_density = 0.012
			var place_scatter_stone := is_grass and stone_density > 0.0 \
				and not _is_on_path(cell) \
				and not scattered_stones_pool.is_empty() \
				and _hash01(cell, 57) < stone_density

			if MINIMAL_GEN:
				place_tuft = false
				place_flower = false
				place_small_flora = false
				place_scatter_stone = false

			# Tuft overlay (small grass patches) - breathes.
			if place_tuft and not tuft_pool.is_empty():
				var ts := _make_sprite(_pick(tuft_pool, cell, 31), cell)
				ts.z_index = -1
				_apply_breathe(ts, cell)
				world.add_child(ts)
				sprites.append(ts)

			# Flower decoration overlay.
			# In BIOME_FLOWERS pick from the species-pocket pool so all cells in
			# the field share ONE flower family. Elsewhere keep the random mix.
			if place_flower and not flower_pool.is_empty():
				var fpool: Array = _flower_pool_for_pocket(cell) if biome == BIOME_FLOWERS else flower_pool
				if fpool.is_empty():
					fpool = flower_pool
				var fls := _make_sprite(fpool[_hash_pick(cell, fpool.size())], cell)
				fls.z_index = -1
				_apply_breathe(fls, cell)
				world.add_child(fls)
				sprites.append(fls)

			# Small standing flora (Flora A1-A5/A7) - breathes.
			if place_small_flora and not flora_small_pool.is_empty():
				var sfs := _make_sprite(_pick(flora_small_pool, cell, 41), cell)
				sfs.z_index = -1
				_apply_breathe(sfs, cell)
				world.add_child(sfs)
				sprites.append(sfs)

			# Scattered stones - visual rock decoration anywhere except paths.
			if place_scatter_stone and not scattered_stones_pool.is_empty():
				var ss := _make_sprite(_pick(scattered_stones_pool, cell, 43), cell)
				ss.z_index = -1
				world.add_child(ss)
				sprites.append(ss)
				register_destructible(cell, ss, "stone")

			# Tall grass - taller decoration, walkable, drawn ABOVE the
			# player so the grass blades cover the character's legs when
			# they walk through it. The art's opaque pixels are bottom-
			# heavy, so a higher z_index hides only the legs visually.
			if place_tall_grass and not tall_grass_pool.is_empty():
				var fg := _make_sprite(_pick(tall_grass_pool, cell, 47), cell)
				_apply_wind_shader(fg, cell)
				world.add_child(fg)
				sprites.append(fg)
				flora_at[cell] = fg
				register_destructible(cell, fg, "tall_grass")

			# Maze biome handles its own placement (grid of hedge walls + corridors).
			if biome == BIOME_MAZE and not MINIMAL_GEN:
				_place_maze_cell(cell, sprites)
				continue

			if MINIMAL_GEN:
				continue   # skip all biome props (trees, bushes, logs, saplings)

			# Props - per-biome rules. Each biome has its own signature props.
			match biome:
				BIOME_FOREST:
					if _should_place_tree(cell, is_grass):
						if tree_shadow_tex != null:
							var sh := _make_sprite(tree_shadow_tex, cell)
							sh.z_index = -1
							sh.modulate = Color(1, 1, 1, 0.55)
							sh.add_to_group("world_props")
							sh.add_to_group("tree")
							sh.visible = props_visible
							world.add_child(sh)
							sprites.append(sh)
						var tree_pool := _tree_pool_for(cell)
						if not tree_pool.is_empty():
							var trs := _make_sprite(_pick(tree_pool, cell, 53), cell)
							_apply_breathe(trs, cell)
							trs.add_to_group("world_props")
							trs.add_to_group("tree")
							trs.visible = props_visible
							world.add_child(trs)
							sprites.append(trs)
							# Trees use pixel-level trunk-only collision
							# instead of cell-level blocking, so the player
							# can walk behind / under the foliage and be
							# stopped only when bumping into the trunk.
							terrain_lift.register_tree(cell, trs.texture.resource_path)
							register_destructible(cell, trs, "tree")
					elif _should_place_log(cell):
						_spawn_prop(log_pool, cell, sprites, true, 59)
					elif _should_place_bush(cell, is_grass):
						_spawn_prop(bush_pool, cell, sprites, false, 61)
				BIOME_PLAINS:
					if _should_place_bush(cell, is_grass) and _hash01(cell, 71) < 0.4:
						_spawn_prop(bush_pool, cell, sprites, false, 61)
					elif _should_place_sapling(cell, is_grass):
						_spawn_prop(sapling_pool, cell, sprites, false, 67)
				BIOME_FLOWERS:
					# Flower valleys: sparse single-species trees + occasional logs/saplings
					# break up the meadow without crowding it.
					if _should_place_tree(cell, is_grass):
						if tree_shadow_tex != null:
							var sh := _make_sprite(tree_shadow_tex, cell)
							sh.z_index = -1
							sh.modulate = Color(1, 1, 1, 0.55)
							sh.add_to_group("world_props")
							sh.add_to_group("tree")
							sh.visible = props_visible
							world.add_child(sh)
							sprites.append(sh)
						var tp := _tree_pool_for(cell)
						if not tp.is_empty():
							var trs := _make_sprite(_pick(tp, cell, 53), cell)
							trs.add_to_group("world_props")
							trs.add_to_group("tree")
							trs.visible = props_visible
							world.add_child(trs)
							sprites.append(trs)
							# Trees use pixel-level trunk-only collision
							# instead of cell-level blocking, so the player
							# can walk behind / under the foliage and be
							# stopped only when bumping into the trunk.
							terrain_lift.register_tree(cell, trs.texture.resource_path)
							register_destructible(cell, trs, "tree")
					elif _should_place_log(cell):
						_spawn_prop(log_pool, cell, sprites, true, 59)
					elif _should_place_sapling(cell, is_grass) and _hash01(cell, 73) < 0.3:
						_spawn_prop(sapling_pool, cell, sprites, false, 67)
	loaded_chunks[cv] = sprites
	# Keep the player at the end of the child list so on tied y_sort keys it
	# wins the tree-order tiebreak (otherwise grass at the same cell would draw
	# over the player's head).
	if player and is_instance_valid(player):
		world.move_child(player, world.get_child_count() - 1)

# Biome enum - which kind of region this cell sits in.
const BIOME_PLAINS  := 0
const BIOME_FOREST  := 1
const BIOME_FLOWERS := 2
const BIOME_MAZE    := 3

# Maze biome lives along its own noise channel so it can spawn anywhere
# without competing for biome_noise bandwidth with plains/forest/flowers.
var maze_noise := FastNoiseLite.new()

func _biome_for(cell: Vector2i) -> int:
	# Square hash-grid mazes win over any other biome on cells inside their rect.
	if _is_in_maze(cell):
		return BIOME_MAZE
	# Tighter thresholds so PLAINS is just a thin transition band - most of
	# the world is FOREST or FLOWERS instead of generic grassland.
	var v: float = biome_noise.get_noise_2d(float(cell.x), float(cell.y))
	if v > 0.05:
		return BIOME_FOREST
	if v < -0.05:
		return BIOME_FLOWERS
	return BIOME_PLAINS

# Returns true if this cell will be covered with grass (not a path/clearing).
func _has_grass_cover(cell: Vector2i) -> bool:
	return not _is_on_path(cell) and not _is_in_clearing(cell)

func _pick(pool: Array[Texture2D], cell: Vector2i, salt: int) -> Texture2D:
	if pool.is_empty():
		return null
	return pool[_hash_pick(cell, pool.size())]

func _should_place_tuft(cell: Vector2i) -> bool:
	if _is_on_path(cell):
		return false
	var d: float = tree_noise.get_noise_2d(float(cell.x) + 17.3, float(cell.y) - 9.1)
	return d > 0.45

func _should_place_tall_grass(cell: Vector2i) -> bool:
	if _is_on_path(cell):
		return false
	if _hash01(cell, 31337) > 0.22:
		return false
	# Don't stack on a cell that will become a tree.
	if _will_be_tree(cell):
		return false
	return true

func _will_be_tree(cell: Vector2i) -> bool:
	var biome: int = _biome_for(cell)
	# Trees grow in forest (dense) and flower fields (sparse), nowhere else.
	if biome != BIOME_FOREST and biome != BIOME_FLOWERS:
		return false
	if _is_in_clearing(cell) or _is_on_path(cell) or _is_water(cell):
		return false
	# Species boundary buffer with a much wider fade zone so different forest
	# types don't sit row-to-row against each other - any band within 0.18 of
	# a species threshold has trees fade out to zero, creating clear gaps.
	# Dead-species threshold pushed to -0.4 so dead-tree zones are rare.
	var s: float = species_noise.get_noise_2d(float(cell.x), float(cell.y))
	var dist_to_boundary: float = min(abs(s - 0.15), abs(s + 0.4))
	var boundary_fade: float = clamp(dist_to_boundary / 0.18, 0.0, 1.0)
	var dead_species: bool = s < -0.4
	var chance: float
	if biome == BIOME_FOREST:
		var density: float = forest_noise.get_noise_2d(float(cell.x), float(cell.y))
		chance = clamp(0.55 + density * 0.4, 0.25, 0.75)
		if dead_species:
			chance *= 0.05   # dead-tree forests are nearly empty - just a few standing trunks
	else:  # BIOME_FLOWERS
		chance = 0.06
		if dead_species:
			chance *= 0.1
	chance *= boundary_fade
	return _hash01(cell, 991) < chance

func _should_place_tree(cell: Vector2i, is_grass: bool) -> bool:
	if not is_grass or _is_on_path(cell):
		return false
	return _will_be_tree(cell)

func _tree_pool_for(cell: Vector2i) -> Array[Texture2D]:
	# A separate very-low-frequency noise picks ONE species per forest pocket
	# so all trees within a single forest biome are the same kind. Dead-tree
	# species is rare (threshold -0.4) - matches _will_be_tree's species rule.
	var s: float = species_noise.get_noise_2d(float(cell.x), float(cell.y))
	if s > 0.15 and not oak_tree_pool.is_empty():
		return oak_tree_pool
	if s < -0.4 and not dead_tree_pool.is_empty():
		return dead_tree_pool
	if not pine_tree_pool.is_empty():
		return pine_tree_pool
	# Fallbacks if a pool is empty.
	if not oak_tree_pool.is_empty(): return oak_tree_pool
	if not pine_tree_pool.is_empty(): return pine_tree_pool
	return dead_tree_pool

func _should_place_flower(cell: Vector2i) -> bool:
	if _is_on_path(cell) or flower_pool.is_empty():
		return false
	return _hash01(cell, 51) < 0.05

func _should_place_small_flora(cell: Vector2i) -> bool:
	if _is_on_path(cell) or flora_small_pool.is_empty():
		return false
	return _hash01(cell, 53) < 0.06

func _should_place_scatter_stone(cell: Vector2i) -> bool:
	if _is_on_path(cell) or scattered_stones_pool.is_empty():
		return false
	return _hash01(cell, 57) < 0.025

func _should_place_bush(cell: Vector2i, is_grass: bool) -> bool:
	if not is_grass or bush_pool.is_empty() or _is_on_path(cell):
		return false
	var density: float = forest_noise.get_noise_2d(float(cell.x), float(cell.y))
	if density < -0.1:
		return false
	return _hash01(cell, 4421) < 0.05

func _should_place_log(cell: Vector2i) -> bool:
	if log_pool.is_empty() or _is_on_path(cell):
		return false
	return _hash01(cell, 8819) < 0.012

func _should_place_sapling(cell: Vector2i, is_grass: bool) -> bool:
	if not is_grass or sapling_pool.is_empty() or _is_on_path(cell):
		return false
	return _hash01(cell, 9917) < 0.018

func _spawn_prop(pool: Array[Texture2D], cell: Vector2i, sprites: Array, blocking: bool, salt: int) -> void:
	if pool.is_empty():
		return
	var s := _make_sprite(_pick(pool, cell, salt), cell)
	_apply_breathe(s, cell)
	s.add_to_group("world_props")
	s.visible = props_visible
	world.add_child(s)
	sprites.append(s)
	if blocking:
		blocked[cell] = true

# Editor toggle: hide every tree / bush / flora sprite the generator placed
# so painting on the underlying ground is unobstructed. Visibility is also
# tracked on the flag so newly-streamed chunks honour the current state.
var props_visible: bool = true

# Terrain physics + per-cell rules now live in terrain_lift.gd. main.gd
# holds a reference and mirrors the public dict properties so existing
# callers (editor.gd, player_layered.gd) still see them on `main`.
const TerrainLiftScript := preload("res://terrain_lift.gd")
var terrain_lift: TerrainLift = null
const SLOPE_RISE_PER_TILE := 96   # mirror of TerrainLift.SLOPE_RISE_PER_TILE
# These are ALIASES of the dicts owned by terrain_lift — assigned in _ready
# so editor.gd / chunk gen can read main_ref.tile_paint_lift directly.
var tile_paint_lift: Dictionary = {}
var tile_storey: Dictionary = {}
var tile_role_lift: Dictionary = {}
var tile_blocked: Dictionary = {}
var _tile_height_maps: Dictionary = {}
var _painted_pixels: Dictionary = {}

# Destructible terrain props — each entry is { sprite, hp, kind } keyed by
# iso cell. Damaged by arrows; spawn an explosion animation and clear the
# sprite when HP hits 0. Tall grass is one-shot, trees and rocks take a
# few hits.
const _DESTRUCTIBLE_FX_ROOT := "res://assets/tilesets/Fantasy tileset - 2D Isometric V1.1/Fantasy tileset - 2D Isometric/Animations/Destructible tiles"
const _DESTRUCTIBLE_KINDS := {
	"tall_grass": {"hp": 1, "fx": "Grass explosion small"},
	"tree":       {"hp": 4, "fx": "Tree Green Explosion"},
	"stone":      {"hp": 5, "fx": "stone explosion Small"},
}
const _ExplosionAnimScript := preload("res://explosion_anim.gd")
var destructibles: Dictionary = {}

func register_destructible(cell: Vector2i, sprite: Node2D, kind: String) -> void:
	if not _DESTRUCTIBLE_KINDS.has(kind):
		return
	destructibles[cell] = {
		"sprite": sprite,
		"hp": int(_DESTRUCTIBLE_KINDS[kind]["hp"]),
		"kind": kind,
	}

# Apply `damage` to any destructible at `cell`. If the prop dies, spawn
# the matching explosion animation, free the sprite, and clear all
# registry state (procedural blocked, terrain_lift trees) so the cell is
# walkable afterwards.
func damage_destructible(cell: Vector2i, damage: int) -> bool:
	if not destructibles.has(cell):
		return false
	var entry: Dictionary = destructibles[cell]
	entry["hp"] = int(entry["hp"]) - damage
	if int(entry["hp"]) > 0:
		var spr = entry.get("sprite", null)
		if spr and is_instance_valid(spr):
			(spr as CanvasItem).modulate = Color(1.6, 0.7, 0.7, 1.0)
			var tw := create_tween()
			tw.tween_property(spr, "modulate", Color(1, 1, 1, 1), 0.15)
		return true
	# Death: spawn explosion at the cell's screen position.
	var kind: String = String(entry.get("kind", ""))
	var fx_name: String = String(_DESTRUCTIBLE_KINDS.get(kind, {}).get("fx", ""))
	if fx_name != "":
		_ExplosionAnimScript.spawn(world, grid_to_screen(cell), "%s/%s" % [_DESTRUCTIBLE_FX_ROOT, fx_name])
	var spr2 = entry.get("sprite", null)
	if spr2 and is_instance_valid(spr2):
		(spr2 as Node).queue_free()
	destructibles.erase(cell)
	# Trees / rocks were registered for collision — release that too.
	# Mirrors editor.gd's two-cell block (placement + south neighbour).
	if terrain_lift:
		terrain_lift.unregister_tree(cell)
	blocked.erase(cell)
	blocked.erase(Vector2i(cell.x + 1, cell.y + 1))
	return true

# Editor path tool. Stamps a path tile at `cell` (replacing any grass
# overlay visually) and re-runs the generator's edge logic on the cell
# itself + every neighbour. Result reads like a procedurally-spawned
# path: random base tile + autotiled A3/A4 grass-edges around it.
var _editor_path_cells: Dictionary = {}    # cell -> Sprite2D base
var _editor_path_edges: Dictionary = {}    # cell -> Array[Sprite2D]

func paint_path_at(cell: Vector2i) -> void:
	# A path is "grass overlay removed so the A1 dirt underneath shows".
	# Rules:
	#   - The cell must have an A1 (ground/dirt/) texture somewhere in
	#     its sprite stack — procedural OR painted. No A1 → no path.
	#   - We remove any grass overlays (procedural at z=-1, or painted
	#     grass on the editor's painted_base stack).
	if world == null:
		return
	var has_dirt: bool = false
	var grass_sprites: Array = []
	for child in world.get_children():
		if not (child is Sprite2D):
			continue
		if not child.has_meta("cell"):
			continue
		if Vector2i(child.get_meta("cell")) != cell:
			continue
		var spr := child as Sprite2D
		if dirt_pool.has(spr.texture):
			has_dirt = true
		if grass_pool.has(spr.texture):
			grass_sprites.append(spr)
	if not has_dirt:
		return   # no A1 ground here → no path can form
	path_cells_override[cell] = true
	for s in grass_sprites:
		(s as Sprite2D).queue_free()
	# If the editor tracked any of those grass sprites in painted_base,
	# drop them from the stack too so save/reload doesn't bring them back.
	if editor and "painted_base" in editor and editor.painted_base.has(cell):
		var keep: Array = []
		for entry in editor.painted_base[cell]:
			if entry is Dictionary and entry.has("sprite") \
					and grass_sprites.has(entry["sprite"]):
				continue
			keep.append(entry)
		if keep.is_empty():
			editor.painted_base.erase(cell)
		else:
			editor.painted_base[cell] = keep
	# Re-apply edges around cell + every neighbour so newly-bordering
	# grass cells pick up the right A3/A4 corner pieces.
	_refresh_path_edges_around(cell)

# Portal interaction. When the player presses Q while standing near a
# placed portal, swap its frame set between PortalIdle ↔ PortalOpen and
# keep playing on loop. Range is generous (a few cells) so the player
# doesn't need to be pixel-perfect.
const _PORTAL_IDLE_DIR := "res://assets/tilesets/Fantasy tileset - 2D Isometric V1.1/Fantasy tileset - 2D Isometric/Animations/Props/PortalIdle"
const _PORTAL_OPEN_DIR := "res://assets/tilesets/Fantasy tileset - 2D Isometric V1.1/Fantasy tileset - 2D Isometric/Animations/Props/PortalOpen"
const _PORTAL_RANGE_PX := 192.0
var _portal_frame_cache: Dictionary = {}    # folder -> Array[Texture2D]

# Dungeon mode: a separate Node2D world swapped in when the player
# enters via a portal. Original world is hidden (not freed), restored on
# exit. ESC inside the dungeon opens a confirm dialog.
const _DungeonScript := preload("res://dungeon.gd")
const _PortalDialogScript := preload("res://portal_dialog.gd")
var dungeon: Node2D = null
var in_dungeon: bool = false
var _saved_player_pos: Vector2 = Vector2.ZERO
var _portal_dialog_open: bool = false

func _show_portal_dialog() -> void:
	if _portal_dialog_open:
		return
	_portal_dialog_open = true
	var dlg = _PortalDialogScript.new()
	if in_dungeon:
		dlg.title_text = "Leave the dungeon?"
		dlg.confirm_text = "Leave"
	else:
		dlg.title_text = "Enter the dungeon?"
		dlg.confirm_text = "Enter"
	dlg.confirmed.connect(_on_portal_confirmed)
	dlg.cancelled.connect(_on_portal_cancelled)
	add_child(dlg)

func _on_portal_confirmed() -> void:
	_portal_dialog_open = false
	if in_dungeon:
		exit_dungeon()
	else:
		enter_dungeon()

func _on_portal_cancelled() -> void:
	_portal_dialog_open = false

func enter_dungeon() -> void:
	if in_dungeon:
		return
	if dungeon == null:
		dungeon = _DungeonScript.new()
		add_child(dungeon)
	dungeon.build()
	in_dungeon = true
	if world:
		world.visible = false
		# Pause ALL world _process / _physics_process while we're in
		# the dungeon — goblins / spiders / FX otherwise keep ticking
		# behind the curtain and hammer the frame budget.
		world.process_mode = Node.PROCESS_MODE_DISABLED
	dungeon.visible = true
	if player:
		_saved_player_pos = (player as Node2D).position
		(player as Node2D).reparent(dungeon)
		(player as Node2D).position = dungeon.player_spawn_world_pos()
	# Hide the editor's iso-grid overlay so the dungeon reads as a clean
	# layout (no debug lattice over the floor tiles).
	if editor and "overlay" in editor and editor.overlay:
		editor.overlay.visible = false

func exit_dungeon() -> void:
	if not in_dungeon:
		return
	in_dungeon = false
	if world:
		world.visible = true
		# Re-enable world processing on exit.
		world.process_mode = Node.PROCESS_MODE_INHERIT
	if player and dungeon:
		(player as Node2D).reparent(world)
		(player as Node2D).position = _saved_player_pos
	# Free the dungeon outright instead of just hiding it. Hiding left
	# child nodes (loot drops, skeletons, walls) lingering in the tree
	# at cells that overlap overworld coords; if any child overrode the
	# inherited visibility (top_level, force-on visible) it bled
	# through into the overworld view. queue_free guarantees nothing
	# leaks. enter_dungeon rebuilds fresh.
	if dungeon and is_instance_valid(dungeon):
		dungeon.queue_free()
	dungeon = null
	# Restore the editor overlay to whatever its active-state dictates.
	if editor and "overlay" in editor and editor.overlay:
		editor.overlay.visible = bool(editor.get("_active"))

# Activate the skill bound to a hotbar slot key ("rmb", "k1"…"k5").
# Looks up the slot node in combat_hud, reads its `skill_id`, fires
# the cooldown overlay, and (TODO) routes to actual skill behaviour.
func _activate_skill_slot(slot_key: String) -> void:
	if combat_hud == null:
		return
	var node_name: String = _SLOT_NODE_BY_KEY.get(slot_key, "")
	if node_name == "":
		return
	var slot: Node = combat_hud.get_node_or_null("Root/" + node_name)
	if slot == null:
		return
	if slot.has_method("is_on_cooldown") and slot.is_on_cooldown():
		return
	var sid: String = slot.get("skill_id") if "skill_id" in slot else ""
	if sid == "":
		return
	var entry: Dictionary = _SkillDB.get_skill(sid)
	var cd: float = float(entry.get("cooldown", 0.5))
	if slot.has_method("trigger_cooldown"):
		slot.trigger_cooldown(cd)
	# Load the SkillDef for this slot and tell the player to play it.
	# Falls back silently if no .tres exists yet — slot still cools
	# down so the rotation still feels live during authoring.
	var def_path: String = "res://data/skills/%s.tres" % sid
	if FileAccess.file_exists(def_path):
		var def: Resource = load(def_path)
		if def != null and player and player.has_method("play_skill"):
			player.play_skill(def)

func _on_xp_changed(current: int, needed: int) -> void:
	if combat_hud == null:
		return
	# Bar node in the scene is `Root/Stamina` — original name preserved
	# from when the same control held stamina before XP. Set its `value`
	# directly so the fill matches xp / xp_to_next.
	var bar: Node = combat_hud.get_node_or_null("Root/Stamina")
	if bar:
		var t: float = clamp(float(current) / max(float(needed), 1.0), 0.0, 1.0)
		bar.set("value", t)

func _on_hp_changed(hp: int, max_hp: int) -> void:
	if combat_hud and combat_hud.has_method("set_player_stats"):
		combat_hud.set_player_stats(hp, max_hp, stats.mp, stats.max_mp())

func _on_mp_changed(mp: int, max_mp: int) -> void:
	if combat_hud and combat_hud.has_method("set_player_stats"):
		combat_hud.set_player_stats(stats.hp, stats.max_hp(), mp, max_mp)

func _on_level_changed(new_level: int) -> void:
	# Refresh both bars on level-up so the new max HP/MP is reflected.
	if combat_hud and combat_hud.has_method("set_player_stats"):
		combat_hud.set_player_stats(stats.hp, stats.max_hp(), stats.mp, stats.max_mp())
	print("[stats] level up → ", new_level, " (", stats.unspent_stat_points,
			" attribute pts, ", stats.unspent_skill_points, " skill pts)")

func _try_open_chest_under_cursor() -> void:
	# Look for any sprite at the cell under the cursor whose texture
	# resolves to "Chest A3.png" (closed). Swap to "Chest A4.png" (open).
	if player == null:
		return
	var mouse_pos: Vector2 = (player as Node2D).get_global_mouse_position()
	var cell: Vector2i = _screen_to_grid(mouse_pos)
	var search_root: Node = dungeon if (in_dungeon and dungeon) else world
	if search_root == null:
		return
	for child in search_root.get_children():
		if not (child is Sprite2D):
			continue
		if not child.has_meta("cell"):
			continue
		if Vector2i(child.get_meta("cell")) != cell:
			continue
		var spr := child as Sprite2D
		if spr.texture == null:
			continue
		var path: String = spr.texture.resource_path
		if "Chest A3" in path:
			var open_path := path.replace("Chest A3", "Chest A4")
			if ResourceLoader.exists(open_path):
				spr.texture = load(open_path)
				spr.set_meta("chest_open", true)
				return

# Applies the transparent-wall darken tint to any enemy CanvasItem
# whose foot cell is in dungeon.transparent_walls. Restores white when
# they step off. Skips dead enemies and respects per-frame _hit_flash
# so the red damage flash isn't overridden mid-decay.
func _apply_enemy_wall_tint(n) -> void:
	# `n` left untyped because the dungeon.skeletons array can briefly
	# hold previously-freed Object references; a typed Node param fails
	# the runtime check before we can validate.
	if n == null or not is_instance_valid(n):
		return
	if not (n is Node2D):
		return
	if not (n is CanvasItem):
		return
	var n2d: Node2D = n
	# Don't fight an in-progress hit flash.
	if n2d.get("_hit_flash_left") and float(n2d._hit_flash_left) > 0.0:
		return
	# Dead enemies keep whatever fade their tween picked.
	if "dead" in n2d and bool(n2d.get("dead")):
		return
	# Treat the enemy as "behind a transparent wall" when their foot
	# cell OR any of the cells visually south on screen has a
	# transparent_wall. Foot-only check missed enemies whose torso was
	# occluded but whose feet were on a clear floor cell — those
	# skeletons stayed bright instead of fading with the wall.
	var foot_cell: Vector2i = _screen_to_grid(n2d.global_position)
	var behind_wall: bool = false
	for off in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1),
			Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)]:
		if dungeon.transparent_walls.has(foot_cell + off):
			behind_wall = true
			break
	(n2d as CanvasItem).modulate = Color(0.55, 0.55, 0.62, 1.0) if behind_wall \
			else Color(1, 1, 1, 1)

func _has_portal_in_range() -> bool:
	if player == null or editor == null or not ("painted_ripples" in editor):
		return false
	var p_pos: Vector2 = (player as Node2D).global_position
	var r2: float = _PORTAL_RANGE_PX * _PORTAL_RANGE_PX
	for cell_key in editor.painted_ripples.keys():
		for entry in editor.painted_ripples[cell_key]:
			if not (entry is Dictionary):
				continue
			if not entry.get("is_portal", false):
				continue
			var spr = entry.get("sprite", null)
			if spr == null or not is_instance_valid(spr) or not (spr is Node2D):
				continue
			if (spr as Node2D).global_position.distance_squared_to(p_pos) < r2:
				return true
	return false

func _toggle_nearby_portal() -> void:
	if player == null or editor == null or not ("painted_ripples" in editor):
		return
	var p_pos: Vector2 = (player as Node2D).global_position
	var best: AnimatedSprite2D = null
	var best_d2: float = _PORTAL_RANGE_PX * _PORTAL_RANGE_PX
	var best_entry: Dictionary = {}
	for cell_key in editor.painted_ripples.keys():
		for entry in editor.painted_ripples[cell_key]:
			if not (entry is Dictionary):
				continue
			if not entry.get("is_portal", false):
				continue
			var spr = entry.get("sprite", null)
			if spr == null or not is_instance_valid(spr) or not (spr is AnimatedSprite2D):
				continue
			var d2: float = (spr as AnimatedSprite2D).global_position.distance_squared_to(p_pos)
			if d2 < best_d2:
				best_d2 = d2
				best = spr
				best_entry = entry
	if best == null:
		return
	var open: bool = bool(best_entry.get("open", false))
	var folder: String = _PORTAL_OPEN_DIR if not open else _PORTAL_IDLE_DIR
	_apply_portal_frames(best, folder)
	best_entry["open"] = not open

func _apply_portal_frames(a: AnimatedSprite2D, folder: String) -> void:
	var frames: Array = _portal_frame_cache.get(folder, [])
	if frames.is_empty():
		var d := DirAccess.open(folder)
		if d != null:
			var names: Array = []
			d.list_dir_begin()
			var fn := d.get_next()
			while fn != "":
				if fn.ends_with(".png"):
					names.append(fn)
				fn = d.get_next()
			d.list_dir_end()
			names.sort()
			for n in names:
				var t: Texture2D = load("%s/%s" % [folder, n])
				if t != null:
					frames.append(t)
		_portal_frame_cache[folder] = frames
	if frames.is_empty():
		return
	var sf := SpriteFrames.new()
	sf.add_animation("loop")
	sf.set_animation_loop("loop", true)
	sf.set_animation_speed("loop", 12.0)
	for t in frames:
		sf.add_frame("loop", t)
	a.sprite_frames = sf
	a.animation = "loop"
	a.play("loop")

func erase_path_at(cell: Vector2i) -> bool:
	# Removes a path at `cell` regardless of source:
	#   - editor-painted (path_cells_override flag, optional stamp sprite)
	#   - procedurally generated (noise/straight road) — recorded in
	#     path_cells_force_off so the noise check is overridden
	# In all cases we add a grass overlay sprite so the cell visually
	# becomes grass (matching the surrounding terrain), and refresh the
	# edges of neighbouring cells so their A3/A4 trims stop pointing
	# at this cell.
	var was_path := _is_on_path(cell)
	if not was_path \
			and not path_cells_override.has(cell) \
			and not _editor_path_cells.has(cell) \
			and not _editor_path_edges.has(cell):
		return false
	path_cells_override.erase(cell)
	if _path_strength(cell) > 0.0 or _is_on_straight_road(cell):
		path_cells_force_off[cell] = true
	var stamped: Sprite2D = _editor_path_cells.get(cell, null)
	if stamped != null and is_instance_valid(stamped):
		stamped.queue_free()
	_editor_path_cells.erase(cell)
	# Sweep world children for orphan path stamps at this cell.
	if world:
		for child in world.get_children():
			if not (child is Sprite2D):
				continue
			if not child.has_meta("cell"):
				continue
			if Vector2i(child.get_meta("cell")) != cell:
				continue
			var spr := child as Sprite2D
			if spr.z_index == 50 and dirt_pool.has(spr.texture):
				spr.queue_free()
	var edges: Array = _editor_path_edges.get(cell, [])
	for s in edges:
		if is_instance_valid(s):
			s.queue_free()
	_editor_path_edges.erase(cell)
	# Add a grass overlay so the cell visually becomes grass — only if
	# the cell is grass-eligible AND there's no painted base (wall,
	# decor) already sitting on it. Skips re-spawn when an overlay is
	# already attached.
	var has_paint: bool = false
	if editor and "painted_base" in editor and editor.painted_base.has(cell):
		has_paint = (editor.painted_base[cell] as Array).size() > 0
	var has_grass_sprite: bool = false
	if world:
		for child in world.get_children():
			if child is Sprite2D and child.has_meta("cell") \
					and Vector2i(child.get_meta("cell")) == cell \
					and child.z_index == -1 \
					and grass_pool.has((child as Sprite2D).texture):
				has_grass_sprite = true
				break
	if not has_paint and not has_grass_sprite \
			and not grass_pool.is_empty() and _has_grass_cover(cell):
		var gs := _make_sprite(_pick(grass_pool, cell, 23), cell)
		gs.z_index = -1
		world.add_child(gs)
	_refresh_path_edges_around(cell)
	return true

func _refresh_path_edges_around(cell: Vector2i) -> void:
	for off in [Vector2i(0, 0), Vector2i(0, -1), Vector2i(1, 0),
			Vector2i(0, 1), Vector2i(-1, 0)]:
		_refresh_path_edges_for(cell + off)

func _refresh_path_edges_for(cell: Vector2i) -> void:
	# Drop previous edge sprites for this cell, re-run the edge-mask logic.
	var prev: Array = _editor_path_edges.get(cell, [])
	for s in prev:
		if is_instance_valid(s):
			s.queue_free()
	_editor_path_edges.erase(cell)
	# Edges are only drawn on non-grass cells (the path itself), where
	# at least one neighbour is grass.
	if _has_grass_cover(cell):
		return
	var sprites: Array = []
	_maybe_place_path_edges(cell, sprites)
	for s in sprites:
		if s is Sprite2D:
			(s as Sprite2D).z_index = 51    # one above the path base
			(s as Sprite2D).add_to_group("editor_paints")
	_editor_path_edges[cell] = sprites

# ---- TerrainLift delegating wrappers ---------------------------------
# main.gd keeps these thin proxies so existing callers (player_layered.gd,
# editor.gd) hit familiar names without knowing about the TerrainLift node.
# All actual logic + state live in terrain_lift.gd.
func _height_map_for(tex_path: String) -> PackedInt32Array: return terrain_lift._height_map_for(tex_path)
func register_painted_pixel_tile(cell: Vector2i, tex_path: String, y_lift: int) -> void: terrain_lift.register_painted_pixel_tile(cell, tex_path, y_lift)
func unregister_painted_pixel_tile(cell: Vector2i, tex_path: String, y_lift: int) -> void: terrain_lift.unregister_painted_pixel_tile(cell, tex_path, y_lift)
func set_tile_paint_lift(cell: Vector2i, lift_px: int, added: bool) -> void: terrain_lift.set_tile_paint_lift(cell, lift_px, added)
func set_tile_role(cell: Vector2i, role: int, added: bool) -> void: terrain_lift.set_tile_role(cell, role, added)
func cell_lift_at(pos: Vector2) -> float: return terrain_lift.cell_lift_at(pos)
func cell_lift(cell: Vector2i) -> float: return terrain_lift.cell_lift(cell)

func _apply_battle_terrain_rules() -> void:
	# Hand-authored physics rules for the BATTLE_WORLD test arena. The editor
	# can overlay extra rules per cell with the area-select + L tool, but the
	# baseline "plateau + slope from ground" used for combat tests lives here
	# so it survives without depending on a paint session.
	var storey_lift_px := HILL_LIFT * 2     # 128 px = storey 2 plateau height
	# Upper plateau: rectangle from (-42,-42) to (-25,-21) inclusive.
	for y in range(-42, -20):
		for x in range(-42, -24):
			tile_paint_lift[Vector2i(x, y)] = storey_lift_px
	# Slope: 4-step ramp leading from ground at (-22,-19) up to the plateau
	# edge at (-26,-21). Each cell holds an explicit interpolated height so
	# the bilinear corner-min interp produces a smooth grade across these
	# cells instead of a 1-cell snap at the plateau border.
	var slope_steps := [
		[Vector2i(-22, -19), 0.25],
		[Vector2i(-23, -20), 0.50],
		[Vector2i(-24, -20), 0.75],
		[Vector2i(-25, -21), 1.00],
	]
	for step in slope_steps:
		var cell: Vector2i = step[0]
		var t: float = step[1]
		tile_paint_lift[cell] = int(round(float(storey_lift_px) * t))

func set_props_visible(v: bool) -> void:
	props_visible = v
	for s in get_tree().get_nodes_in_group("world_props"):
		if is_instance_valid(s):
			s.visible = v

func _apply_breathe(sprite: Sprite2D, cell: Vector2i) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = BREATHE_SHADER
	mat.set_shader_parameter("phase", _hash01(cell, 7717) * TAU)
	mat.set_shader_parameter("speed", 0.9 + _hash01(cell, 7719) * 0.5)
	# Per-pocket HSV recolor. color_noise is very low frequency so all plants
	# in a region share the same tone; bands of noise produce purple woods,
	# yellow meadows, etc., from the same source assets.
	var hs: Vector3 = _color_shift_for(cell)
	mat.set_shader_parameter("hue_shift", hs.x)
	mat.set_shader_parameter("sat_mult", hs.y)
	mat.set_shader_parameter("val_mult", hs.z)
	sprite.material = mat

func _color_shift_for(_cell: Vector2i) -> Vector3:
	# Biome recolors disabled: every cell stays at the texture's base
	# colors. Re-enable later by restoring the noise-banded HSV picks.
	return Vector3(0.0, 1.0, 1.0)

# Pick the SAME flower family across a whole BIOME_FLOWERS pocket via species_noise.
func _flower_pool_for_pocket(cell: Vector2i) -> Array:
	if flower_families.is_empty():
		return flower_pool
	var s: float = species_noise.get_noise_2d(float(cell.x), float(cell.y))
	var idx: int = int((s + 1.0) * 0.5 * float(flower_families.size())) % flower_families.size()
	return flower_families[idx]

# ---- Square maze layout (hash-grid of fixed-size mazes) ----------------------
# Mazes spawn at a jittered grid of slots. Each maze is a fixed-size axis-
# aligned rectangle so the boundary is always a clean square frame around the
# corridor pattern. The path cuts an entrance when it crosses the perimeter.

const MAZE_BLOCK := 90       # cells between potential maze seeds
const MAZE_SIZE := 17        # fixed maze side length (odd so corner posts align)
const MAZE_CHANCE := 0.4     # fraction of grid blocks that host a maze

func _maze_rect_for_block(bx: int, by: int) -> Rect2i:
	# Returns Rect2i.size.x == 0 if no maze exists in this grid block.
	var key := Vector2i(bx, by)
	if _hash01(key, 7777) > MAZE_CHANCE:
		return Rect2i(0, 0, 0, 0)
	# Jitter the maze inside its block, but leave a margin so it never touches
	# the block boundary (avoids two adjacent mazes merging into one).
	var slack: int = MAZE_BLOCK - MAZE_SIZE - 4
	var ox: int = int(_hash01(key, 7778) * float(slack)) + 2
	var oy: int = int(_hash01(key, 7779) * float(slack)) + 2
	var origin := Vector2i(bx * MAZE_BLOCK + ox, by * MAZE_BLOCK + oy)
	return Rect2i(origin, Vector2i(MAZE_SIZE, MAZE_SIZE))

func _maze_rect_for(cell: Vector2i) -> Rect2i:
	var bx: int = int(floor(float(cell.x) / float(MAZE_BLOCK)))
	var by: int = int(floor(float(cell.y) / float(MAZE_BLOCK)))
	# Check this block and 1 neighbor each way in case the maze straddles the
	# block boundary (it shouldn't given the margin, but cheap to be safe).
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var r := _maze_rect_for_block(bx + dx, by + dy)
			if r.size.x > 0 and r.has_point(cell):
				return r
	return Rect2i(0, 0, 0, 0)

func _is_in_maze(cell: Vector2i) -> bool:
	if BATTLE_WORLD:
		return false   # no procedural mazes in the bounded battle arena
	return _maze_rect_for(cell).size.x > 0

# Hand-authored water layout for BATTLE_WORLD: a meandering river that enters
# the world from the top-right corner, flows south along the east side of the
# top half, and curves out the right edge. Bay-fill smoothing widens it
# slightly so the curves read cleanly with the existing C-tile autotiling.
func _battle_is_water(cell: Vector2i) -> bool:
	if not BATTLE_RECT.has_point(cell):
		return false
	# River core: top-right quadrant, a 5-wide stripe meandering south.
	# Centerline x = 22 + 4*sin(y * 0.18), y range [-40, -2].
	if cell.y < -40 or cell.y > -2:
		return false
	var center_x: float = 22.0 + 4.0 * sin(float(cell.y) * 0.18)
	if abs(float(cell.x) - center_x) <= 2.0:
		return true
	# East-edge spur where the river exits the world.
	if cell.y >= -8 and cell.y <= -2 and cell.x >= int(center_x) and cell.x <= 39:
		return true
	return false

# ---- Water -------------------------------------------------------------------

func _is_ocean(cell: Vector2i) -> bool:
	return ocean_noise.get_noise_2d(float(cell.x), float(cell.y)) > 0.45

func _is_river(cell: Vector2i) -> bool:
	# Wider band than before -> rivers are a continuous 4-5 cell stripe so
	# curve cells (boundary) are surrounded by interior water and the rounded
	# C-tile edges meet less often.
	return abs(river_noise.get_noise_2d(float(cell.x), float(cell.y))) < 0.058

func _is_water(cell: Vector2i) -> bool:
	if BATTLE_WORLD:
		return _battle_is_water(cell)
	# No water inside maze rectangles - keeps mazes clean.
	if _is_in_maze(cell):
		return false
	if _is_ocean(cell) or _is_river(cell):
		return true
	# Bay-fill smoothing — single non-recursive pass over raw is_ocean/is_river.
	# Land cell becomes water if 3+ of its 8 neighbors are raw water. Catches
	# concave bays, 1-cell gaps in curving 2-wide ribbons, and inside corners
	# of wider bodies. Genuine 1-cell streams (cardinals only, no diagonals)
	# stop at 2 raw water neighbors so they stay narrow.
	var n: int = 0
	var offsets := [
		Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),       # cardinals
		Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1),     # diagonals
	]
	for off in offsets:
		var nb: Vector2i = cell + off
		if _is_in_maze(nb):
			continue
		if _is_ocean(nb) or _is_river(nb):
			n += 1
	return n >= 3

# Public alias so player.gd can probe water cells.
func is_water_cell(cell: Vector2i) -> bool:
	return _is_water(cell)

# --- Hills ------------------------------------------------------------------
# Hills are RECTANGULAR plateaus placed on a deterministic hash-grid (same
# pattern as mazes). Each grid block may host one rectangle of randomised
# size; rectangles never touch each other or block boundaries so neighbouring
# hills can't merge. Cells outside any rectangle aren't hill cells.
const HILL_BLOCK := 80         # cells between potential hill seeds
const HILL_MIN := 8            # smallest hill side
const HILL_MAX := 22           # largest hill side
const HILL_CHANCE := 0.45      # fraction of blocks that spawn a hill

func _hill_rect_for_block(bx: int, by: int) -> Rect2i:
	var key := Vector2i(bx, by)
	if _hash01(key, 8881) > HILL_CHANCE:
		return Rect2i(0, 0, 0, 0)
	var w: int = HILL_MIN + int(_hash01(key, 8882) * float(HILL_MAX - HILL_MIN + 1))
	var h: int = HILL_MIN + int(_hash01(key, 8883) * float(HILL_MAX - HILL_MIN + 1))
	# Leave a 2-cell margin from block boundaries so adjacent hills don't fuse.
	var slack_x: int = HILL_BLOCK - w - 4
	var slack_y: int = HILL_BLOCK - h - 4
	if slack_x < 0 or slack_y < 0:
		return Rect2i(0, 0, 0, 0)
	var ox: int = int(_hash01(key, 8884) * float(slack_x)) + 2
	var oy: int = int(_hash01(key, 8885) * float(slack_y)) + 2
	var origin := Vector2i(bx * HILL_BLOCK + ox, by * HILL_BLOCK + oy)
	return Rect2i(origin, Vector2i(w, h))

func _hill_rect_for(cell: Vector2i) -> Rect2i:
	if BATTLE_WORLD:
		for hr in [Rect2i(-30, 5, 12, 10), Rect2i(0, -8, 10, 9)]:
			if hr.has_point(cell):
				return hr
		return Rect2i(0, 0, 0, 0)
	var bx: int = int(floor(float(cell.x) / float(HILL_BLOCK)))
	var by: int = int(floor(float(cell.y) / float(HILL_BLOCK)))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var r := _hill_rect_for_block(bx + dx, by + dy)
			if r.size.x > 0 and r.has_point(cell):
				return r
	return Rect2i(0, 0, 0, 0)

# Per-hill silhouette carving: the bounding rect is the *envelope*, but cells
# in carved corners are excluded so the outline has L / T / U bends instead
# of every hill being a perfect rectangle. Carving is deterministic — the
# carve mask + bite size both hash off the rect's origin so neighbouring
# chunks see the same shape and the cliff picker resolves cleanly across
# chunk boundaries.
# Multi-cell corner bites for varied silhouettes. The bite size is bounded so
# the remaining shape always stays at least 3 cells thick along every axis —
# guarantees we never produce a 1-cell-wide arm that the cliff art can't
# render cleanly. Each carved corner exposes interior cells with a missing
# diagonal, which the fold detector picks up as G5 inside-corner cliffs.
func _hill_cell_in_shape(cell: Vector2i, rect: Rect2i) -> bool:
	if not rect.has_point(cell):
		return false
	if rect.size.x <= 4 or rect.size.y <= 4:
		return true
	var carve_bits: int = int(_hash01(rect.position, 9111) * 16.0)
	# Cap each dimension's bite at floor((side-3)/2) so opposite-corner carves
	# leave a central strip ≥ 3 cells wide, no thin arms possible.
	var max_bx: int = max(1, (rect.size.x - 3) / 2)
	var max_by: int = max(1, (rect.size.y - 3) / 2)
	var cw: int = 1 + int(_hash01(rect.position, 9112) * float(max_bx))
	var ch: int = 1 + int(_hash01(rect.position, 9113) * float(max_by))
	var lx: int = rect.position.x
	var ty: int = rect.position.y
	var rx: int = rect.position.x + rect.size.x - 1
	var by: int = rect.position.y + rect.size.y - 1
	if (carve_bits & 1) != 0 and cell.x < lx + cw and cell.y < ty + ch:    # NW
		return false
	if (carve_bits & 2) != 0 and cell.x > rx - cw and cell.y < ty + ch:    # NE
		return false
	if (carve_bits & 4) != 0 and cell.x > rx - cw and cell.y > by - ch:    # SE
		return false
	if (carve_bits & 8) != 0 and cell.x < lx + cw and cell.y > by - ch:    # SW
		return false
	return true

func _is_hill(cell: Vector2i) -> bool:
	if _is_in_maze(cell):
		return false
	if _is_water(cell):
		return false
	if BATTLE_WORLD:
		# Two hand-placed hills in the arena: one in the south-west for
		# climb / fall physics, one to the right of center for cover during
		# combat tests. Both stay clear of the river area.
		for hr in [Rect2i(-30, 5, 12, 10), Rect2i(0, -8, 10, 9)]:
			if hr.has_point(cell):
				return _hill_cell_in_shape(cell, hr)
		return false
	var r := _hill_rect_for(cell)
	if r.size.x == 0:
		return false
	return _hill_cell_in_shape(cell, r)

# An interior cell (mask 15) becomes a "fold" cell when one of its diagonal
# neighbours is non-hill — that means the hill silhouette has a concave bend
# and the cell sits on the inside of it. We render a G5 fold cliff at the
# fold, with no plateau dirt/grass on top so the diamond doesn't overhang
# the carved-out grass cell. Variant letter matches the open quadrant.
const _FOLD_VARIANT := {
	Vector2i(-1, -1): "E",   # NW diagonal open
	Vector2i( 1, -1): "S",   # NE diagonal open
	Vector2i( 1,  1): "W",   # SE diagonal open
	Vector2i(-1,  1): "N",   # SW diagonal open
}

func _hill_fold_variant(cell: Vector2i) -> String:
	for off in _FOLD_VARIANT.keys():
		if not _is_hill(cell + off):
			return _FOLD_VARIANT[off]
	return ""

# Pick one south-edge perimeter cell per hill to act as a ramp — the cell is
# walkable (not blocked) and the player's lift ramps from 0 at the south edge
# to HILL_LIFT at the north edge as they cross it. Choosing the south side so
# the player approaches the hill from in front of the camera.
func _hill_ramp_cell_for(rect: Rect2i) -> Vector2i:
	if rect.size.x == 0:
		return Vector2i(0, 0)
	# Pick a column inside the south edge (skip corners) deterministically.
	var min_col: int = rect.position.x + 1
	var max_col: int = rect.position.x + rect.size.x - 2
	if max_col < min_col:
		max_col = min_col
	var col: int = min_col + int(_hash01(rect.position, 9301) * float(max_col - min_col + 1))
	var row: int = rect.position.y + rect.size.y - 1
	return Vector2i(col, row)

func is_hill_ramp(cell: Vector2i) -> bool:
	if not _is_hill(cell):
		return false
	var r := _hill_rect_for(cell)
	if r.size.x == 0:
		return false
	# A ramp cell must be the picked ramp AND its silhouette must keep it on
	# the south-edge perimeter (so a corner carve hasn't removed the ramp).
	var ramp_cell := _hill_ramp_cell_for(r)
	if ramp_cell != cell:
		return false
	if not _hill_cell_in_shape(cell, r):
		return false
	# Must have a non-hill neighbour to the south (open to ground access).
	return not _is_hill(cell + Vector2i(0, 1))

# Returns the lift in pixels for a player at world position `pos`. 0 on flat
# ground, HILL_LIFT on a plateau, and a smooth interpolation across the ramp
# cell so the player visibly walks up the slope.
func hill_lift_at(pos: Vector2) -> float:
	var cell: Vector2i = _screen_to_grid(pos)
	if is_hill_interior(cell):
		return float(HILL_LIFT)
	if is_hill_ramp(cell):
		# Lerp by how far across the cell's iso diamond the player is on the
		# south→north axis. Cell's iso center is grid_to_screen(cell); going
		# north shifts screen.y by -32, going east by +64 (TILE_W/2).
		var cell_center: Vector2 = grid_to_screen(cell)
		# Project pos onto the iso "north axis" (cell+1 north - cell+1 south).
		# Going north → screen delta (-64, -32). Going south → (+64, +32).
		# In screen space the south→north unit vector is (-64,-32)/72 ≈ (-0.894,-0.447).
		# Half-cell distance along that axis ≈ 32 px (TILE_H).
		var d: Vector2 = pos - cell_center
		var t: float = clamp(0.5 - (d.x / 128.0 + d.y / 64.0) * 0.5, 0.0, 1.0)
		return float(HILL_LIFT) * t
	return 0.0

func _hill_neighbor_mask(cell: Vector2i) -> int:
	var m: int = 0
	if _is_hill(cell + Vector2i(0, -1)): m |= 1   # N
	if _is_hill(cell + Vector2i(1,  0)): m |= 2   # E
	if _is_hill(cell + Vector2i(0,  1)): m |= 4   # S
	if _is_hill(cell + Vector2i(-1, 0)): m |= 8   # W
	return m

# Procedural hills are rectangles (optionally corner-carved) — they only
# produce convex outer corners (G3) and straight edges (G1). The fold (G5)
# and channel (G4) tiles only make sense for hand-built shapes with thin
# 1-cell arms, which the editor's auto-fit brush can produce. Keeping the
# procedural picker simple avoids placing G5 where G3 belongs.
const _HILL_TILE_TABLE := {
	# Outer corners (G3) — 2 adjacent cardinal hill neighbours
	6:  ["N", true],   # E+S hill -> NW corner -> G3_N
	12: ["E", true],   # S+W hill -> NE corner -> G3_E
	9:  ["S", true],   # N+W hill -> SE corner -> G3_S
	3:  ["W", true],   # N+E hill -> SW corner -> G3_W
	# Edges (G1) — 3 cardinal hill neighbours
	14: ["E", false],
	13: ["S", false],
	11: ["W", false],
	7:  ["N", false],
}

func _pick_hill_tile(cell: Vector2i) -> Texture2D:
	var m := _hill_neighbor_mask(cell)
	if not _HILL_TILE_TABLE.has(m):
		return null
	var entry: Array = _HILL_TILE_TABLE[m]
	var sfx: String = entry[0]
	var is_corner: bool = entry[1]
	if is_corner:
		return hill_corner_dir.get(sfx, null)
	return hill_edge_dir.get(sfx, null)

# Cache of ripple-art centroid offsets so each player ripple lines up on
# the player's iso pivot regardless of where the source PNG draws its art.
var _player_ripple_offset_cache: Dictionary = {}   # texture_rid -> Vector2

func _ripple_centroid_offset_for(tex: Texture2D) -> Vector2:
	if tex == null:
		return Vector2.ZERO
	var key := tex.get_rid().get_id()
	if _player_ripple_offset_cache.has(key):
		return _player_ripple_offset_cache[key]
	var img: Image = tex.get_image()
	if img == null:
		_player_ripple_offset_cache[key] = Vector2.ZERO
		return Vector2.ZERO
	var w := img.get_width()
	var h := img.get_height()
	var cx: float = 0.0
	var cy: float = 0.0
	var n: int = 0
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a > 0.1:
				cx += float(x); cy += float(y); n += 1
	var off := Vector2.ZERO
	if n > 0:
		off = Vector2(float(w) * 0.5 - cx / float(n), float(h) * 0.5 - cy / float(n))
	_player_ripple_offset_cache[key] = off
	return off

# Spawns a fading expanding-ripple sprite at the given world position.
# Used by the player when walking on water. The ripple's art centroid is
# placed exactly at world_pos (i.e. the player's iso pivot) - we don't
# use SPRITE_Y_OFFSET here because that's for ground tiles whose pivot
# is different from the ripple art's centroid.
func spawn_player_ripple(world_pos: Vector2) -> void:
	if ripple_pools.is_empty():
		return
	# Small interior ripple (WR1 = bottom dot) for a subtle splash.
	var pool: Array = ripple_pools.get("interior", [])
	if pool.is_empty():
		for k in ripple_pools.keys():
			if ripple_pools[k].size() > 0:
				pool = ripple_pools[k]
				break
	if pool.is_empty():
		return
	var frames: Array = pool[0]
	if frames.is_empty():
		return
	var sf := SpriteFrames.new()
	sf.add_animation("loop")
	sf.set_animation_loop("loop", false)
	sf.set_animation_speed("loop", 14.0)
	for t in frames:
		sf.add_frame("loop", t)
	var a := AnimatedSprite2D.new()
	a.sprite_frames = sf
	a.animation = "loop"
	a.play("loop")
	a.centered = true
	a.offset = _ripple_centroid_offset_for(frames[0])
	a.position = world_pos
	a.z_index = 2
	var froth_mat := ShaderMaterial.new()
	froth_mat.shader = FROTH_SHADER
	froth_mat.set_shader_parameter("froth_color", Color(0.95, 1.0, 1.0, 0.45))
	a.material = froth_mat
	world.add_child(a)
	var dur: float = float(frames.size()) / 14.0 + 0.1
	get_tree().create_timer(dur).timeout.connect(func():
		if is_instance_valid(a):
			a.queue_free()
	)

func _water_neighbor_mask(cell: Vector2i) -> int:
	var m: int = 0
	if _is_water(cell + Vector2i(0, -1)): m |= 1
	if _is_water(cell + Vector2i(1, 0)):  m |= 2
	if _is_water(cell + Vector2i(0, 1)):  m |= 4
	if _is_water(cell + Vector2i(-1, 0)): m |= 8
	return m

# C/A pairings derived from the user's hand-painted reference draft:
#   C2 corner pieces pair with A3 of the SAME suffix.
#   C1 single pieces pair with A4 of a rotated suffix (N->E, E->S, S->W, W->N).
const _C1_TO_A4_PAIR := {"N":"E", "E":"S", "S":"W", "W":"N"}

# Returns {"tex", "kind", "suffix"} for the chosen water tile, or {} if none.
# kind: "solid" | "corner" | "single"
func _pick_water_tile_info(cell: Vector2i) -> Dictionary:
	var m: int = _water_neighbor_mask(cell)
	# All four neighbors are water -> solid bed (C3).
	if m == 15 and not water_solid_pool.is_empty():
		return {"tex": _pick(water_solid_pool, cell, 8101), "kind": "solid", "suffix": ""}
	# 2 adjacent water neighbors -> C2 corner. Suffix is the dry direction
	# rotated 90 degrees CCW (per draft-20 analysis: every mask 3/6/9/12 cell
	# the user painted got C2 with this suffix mapping, regardless of whether
	# adjacent water cells were "interior" or "boundary").
	if m in [3, 6, 12, 9] and not water_corner_dir.is_empty():
		var sfx := ""
		match m:
			3:  sfx = "S"   # water at N+E -> dry at SW screen -> W rotated CCW = S
			6:  sfx = "W"   # water at E+S -> dry at N screen  -> N rotated CCW = W
			12: sfx = "N"   # water at S+W -> dry at NE screen -> E rotated CCW = N
			9:  sfx = "E"   # water at W+N -> dry at S screen  -> S rotated CCW = E
		var t = water_corner_dir.get(sfx, null)
		if t != null:
			return {"tex": t, "kind": "corner", "suffix": sfx}
# Single water neighbor -> C1 edge. EXCEPT: if that lone water neighbor is
	# itself fully interior (C3 solid, mask 15), the boundary between a 1-edge
	# cutoff and a solid bed reads as jagged. Per the draft-16 rule, upgrade to
	# the matching C2 corner instead so the transition wraps smoothly.
	if m in [1, 2, 4, 8]:
		var sfx2 := ""
		var nbr_off := Vector2i.ZERO
		match m:
			1: sfx2 = "E"; nbr_off = Vector2i(0, -1)
			2: sfx2 = "S"; nbr_off = Vector2i(1, 0)
			4: sfx2 = "W"; nbr_off = Vector2i(0, 1)
			8: sfx2 = "N"; nbr_off = Vector2i(-1, 0)
		if _water_neighbor_mask(cell + nbr_off) == 15 and not water_corner_dir.is_empty():
			var tc = water_corner_dir.get(sfx2, null)
			if tc != null:
				return {"tex": tc, "kind": "corner", "suffix": sfx2}
		if not water_edge_dir.is_empty():
			var t2 = water_edge_dir.get(sfx2, null)
			if t2 != null:
				return {"tex": t2, "kind": "single", "suffix": sfx2}
	# Opposite-cardinal water. Two interpretations distinguished by diagonals:
	#   (a) 0-1 water diagonals  -> genuine 1-cell-wide stream segment (C1)
	#   (b) 2+ water diagonals    -> the cell is inside a curving wider body
	#                                where opposite-side water is just the
	#                                ribbon flowing past on both sides (C3)
	# Draft 15's tributary at x=-4 is case (a); draft 26's flagged cells at
	# (39,-7)/(39,6) are case (b).
	if m == 5 or m == 10:
		var diag_count: int = 0
		if _is_water(cell + Vector2i(1, -1)): diag_count += 1
		if _is_water(cell + Vector2i(1,  1)): diag_count += 1
		if _is_water(cell + Vector2i(-1, 1)): diag_count += 1
		if _is_water(cell + Vector2i(-1,-1)): diag_count += 1
		if diag_count >= 2 and not water_solid_pool.is_empty():
			return {"tex": _pick(water_solid_pool, cell, 8401), "kind": "solid", "suffix": ""}
		if not water_edge_dir.is_empty():
			var sfx5 := "S" if m == 5 else "E"
			var t5 = water_edge_dir.get(sfx5, null)
			if t5 != null:
				return {"tex": t5, "kind": "single", "suffix": sfx5}
	# Three cardinal water neighbors: with the bay-fill smoothing in _is_water,
	# concave bays (1-cell land fingers poking into a wide body) are now filled
	# automatically — so most cells that would have been mask 7/11/13/14 are
	# now mask 15 (interior) instead. The few remaining cells with this mask
	# are on a truly straight edge of a wide body where C3 reads cleanly.
	if m in [7, 11, 13, 14] and not water_solid_pool.is_empty():
		return {"tex": _pick(water_solid_pool, cell, 8201), "kind": "solid", "suffix": ""}
	# Mask 0 — no cardinal water neighbors, but the eye reads the cell as part
	# of a 2-cell-wide ribbon if a screen-diagonal grid neighbor is water. Per
	# draft 18:
	#   water at grid (+1,+1) i.e. screen-S       -> C2_W   (top bank of E-W ribbon)
	#   water at grid (-1,-1) i.e. screen-N       -> C2_E   (bottom bank)
	#   water at grid (+1,-1) i.e. screen-E only  -> C2_W   (cell sits on west edge of N-S ribbon)
	#   water at grid (-1,+1) i.e. screen-W only  -> C2_E
	# Falls through to the C3 fallback if the cell has no diagonal water either.
	if m == 0 and not water_corner_dir.is_empty():
		var s_water: bool = _is_water(cell + Vector2i(1, 1))
		var n_water: bool = _is_water(cell + Vector2i(-1, -1))
		var e_water: bool = _is_water(cell + Vector2i(1, -1))
		var w_water: bool = _is_water(cell + Vector2i(-1, 1))
		var sfx0 := ""
		if s_water and not n_water:
			sfx0 = "W"
		elif n_water and not s_water:
			sfx0 = "E"
		elif e_water and not w_water:
			sfx0 = "W"
		elif w_water and not e_water:
			sfx0 = "E"
		if sfx0 != "":
			var tcorner = water_corner_dir.get(sfx0, null)
			if tcorner != null:
				return {"tex": tcorner, "kind": "corner", "suffix": sfx0}
	# Fallback for genuinely isolated water cells: C3 solid.
	if not water_solid_pool.is_empty():
		return {"tex": _pick(water_solid_pool, cell, 8201), "kind": "solid", "suffix": ""}
	return {}

func _place_hill_cell(cell: Vector2i, sprites: Array) -> void:
	# A hill cell stacks:
	#   - all hill cells: a ground-level A1 dirt diamond at z=-1, so the cell
	#     has a proper ground footprint flush with adjacent non-hill ground.
	#     The cliff art (G1/G3/...) only paints the vertical wall and top edge,
	#     not a full diamond, so without this base the cell would be empty
	#     beneath the cliff and you'd see a hole next to surrounding dirt.
	#   - perimeter cells: cliff face (G1/G3) overlaid at z=0.
	#   - interior cells: plateau top lifted by HILL_LIFT, with a per-hill
	#     coin flip choosing dirt-only vs dirt+grass top.
	if not dirt_pool.is_empty():
		var bds := _make_sprite(_pick(dirt_pool, cell, 11), cell)
		bds.z_index = -1
		world.add_child(bds)
		sprites.append(bds)
	var m := _hill_neighbor_mask(cell)
	if m == 15:
		# INTERIOR cell — but if a diagonal neighbour is missing, this is the
		# inside of a carved corner. Render a G5 fold cliff and skip the
		# plateau top, so the dirt diamond doesn't overhang the carved grass.
		var fold_sfx := _hill_fold_variant(cell)
		if fold_sfx != "":
			var ft: Texture2D = hill_fold_dir.get(fold_sfx, null)
			if ft != null:
				var fs := _make_sprite(ft, cell)
				fs.z_index = 0
				world.add_child(fs)
				sprites.append(fs)
			_block_wall_cell(cell)
			return
		# Genuine interior — plateau top.
		var rect := _hill_rect_for(cell)
		var grass_top: bool = _hash01(rect.position, 9201) < 0.55
		if not dirt_pool.is_empty():
			var ds := _make_sprite(_pick(dirt_pool, cell, 13), cell)
			ds.offset = Vector2(0, SPRITE_Y_OFFSET - PLATEAU_VISUAL_LIFT)
			ds.z_index = 0
			world.add_child(ds)
			sprites.append(ds)
		if grass_top and not grass_pool.is_empty():
			var gs := _make_sprite(_pick(grass_pool, cell, 23), cell)
			gs.offset = Vector2(0, SPRITE_Y_OFFSET - PLATEAU_VISUAL_LIFT)
			gs.z_index = 0
			world.add_child(gs)
			sprites.append(gs)
	elif is_hill_ramp(cell):
		# Ramp cell — keep walkable (not blocked) and show plain dirt so the
		# player can stride from ground level up onto the plateau without a
		# cliff in their way. Lift is interpolated across the cell in
		# hill_lift_at(), and the player_layered.gd applies it visually.
		pass
	else:
		# PERIMETER cell — cliff face overlay on top of the ground base.
		# Blocked so the player can't walk through the wall of the hill.
		var ht := _pick_hill_tile(cell)
		if ht != null:
			var cs := _make_sprite(ht, cell)
			cs.z_index = 0
			world.add_child(cs)
			sprites.append(cs)
		_block_wall_cell(cell)

# Public alias so player.gd can lift its sprite when standing on a hill top.
func is_hill_interior(cell: Vector2i) -> bool:
	return _is_hill(cell) and _hill_neighbor_mask(cell) == 15

const HILL_LIFT := 64   # pixels the plateau top sits above ground level
const PLATEAU_VISUAL_LIFT := HILL_LIFT

# After ground layers, allow trees / decor for INTERIOR hill cells only. Cliff
# perimeter cells stay clear so trees don't spawn on the edge of a drop.
func _finish_hill_cell(cell: Vector2i, sprites: Array) -> void:
	if _hill_neighbor_mask(cell) != 15:
		return   # perimeter cell, leave bare
	# Props on the plateau also need the HILL_LIFT offset so they sit on the
	# raised surface, not the ground beneath the cliff.
	var lift_off := Vector2(0, SPRITE_Y_OFFSET - PLATEAU_VISUAL_LIFT)
	if _should_place_tree(cell, true):
		if tree_shadow_tex != null:
			var sh := _make_sprite(tree_shadow_tex, cell)
			sh.offset = lift_off
			sh.z_index = -1
			sh.modulate = Color(1, 1, 1, 0.55)
			sh.add_to_group("world_props")
			sh.add_to_group("tree")
			sh.visible = props_visible
			world.add_child(sh)
			sprites.append(sh)
		var tp := _tree_pool_for(cell)
		if not tp.is_empty():
			var trs := _make_sprite(_pick(tp, cell, 53), cell)
			trs.offset = lift_off
			_apply_breathe(trs, cell)
			trs.add_to_group("world_props")
			trs.visible = props_visible
			world.add_child(trs)
			sprites.append(trs)
			blocked[cell] = true
	elif _should_place_bush(cell, true):
		# Spawn bush via _make_sprite directly so we can override the offset.
		if not bush_pool.is_empty():
			var bs := _make_sprite(_pick(bush_pool, cell, 61), cell)
			bs.offset = lift_off
			_apply_breathe(bs, cell)
			bs.add_to_group("world_props")
			bs.visible = props_visible
			world.add_child(bs)
			sprites.append(bs)

func _place_water_cell(cell: Vector2i, sprites: Array) -> void:
	var info: Dictionary = _pick_water_tile_info(cell)
	if info.is_empty():
		return
	# Dirt base under everything (also fills the "lighter" portion of C1/C2).
	if not dirt_pool.is_empty():
		var base := _make_sprite(_pick(dirt_pool, cell, 11), cell)
		base.z_index = -2
		world.add_child(base)
		sprites.append(base)
	# Water tile with the wave shader at z = -1 (y-sorts with grass).
	var s := _make_sprite(info.tex, cell)
	s.z_index = -1
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	s.material = mat
	world.add_child(s)
	sprites.append(s)
	# Per the user's reference draft: layer the matching grass-edge tile ON
	# TOP of C1/C2 water cells so the dirt portion of the C-tile reads as
	# grass-bordering-water. C2 pairs with A3 of the SAME suffix; C1 pairs
	# with A4 of a rotated suffix (N->E, E->S, S->W, W->N).
	if info.kind == "corner":
		var a3_pool: Array = path_corner_dir.get(info.suffix, [])
		if not a3_pool.is_empty():
			var a3_tex: Texture2D = a3_pool[_hash_pick(cell, a3_pool.size())]
			var a3 := _make_sprite(a3_tex, cell)
			a3.z_index = -1
			world.add_child(a3)
			sprites.append(a3)
	elif info.kind == "single":
		var a4_suffix: String = _C1_TO_A4_PAIR.get(info.suffix, info.suffix)
		var a4_pool: Array = path_single_dir.get(a4_suffix, [])
		if not a4_pool.is_empty():
			var a4_tex: Texture2D = a4_pool[_hash_pick(cell, a4_pool.size())]
			var a4 := _make_sprite(a4_tex, cell)
			a4.z_index = -1
			world.add_child(a4)
			sprites.append(a4)
	# blocked[cell] = true   (re-enable to make water blocking)

func _ripple_bucket_for(cell: Vector2i) -> String:
	# Which diamond edge of this cell faces a LAND neighbor? Pick the ripple
	# variant that sits on that edge so ripples decorate the water-meets-land
	# boundary rather than the water interior.
	var land: int = 0
	if not _is_water(cell + Vector2i(0, -1)): land |= 1   # NE land
	if not _is_water(cell + Vector2i(1, 0)):  land |= 2   # SE
	if not _is_water(cell + Vector2i(0, 1)):  land |= 4   # SW
	if not _is_water(cell + Vector2i(-1, 0)): land |= 8   # NW
	# Two adjacent land bits = a whole edge of the diamond is land.
	match land:
		9:  return "top"     # NE + NW land -> water meets land along the top edge
		6:  return "bottom"  # SE + SW
		3:  return "right"   # NE + SE
		12: return "left"    # SW + NW
		1:  return "NE"
		2:  return "SE"
		4:  return "SW"
		8:  return "NW"
		0:  return "interior"
		_:  return "interior"   # 3-land cases fall through to small interior ripple

func _spawn_ripple(cell: Vector2i, sprites: Array) -> void:
	# One ripple per water cell, centered on the cell, NO jitter (jitter caused
	# ripples to leak into neighboring grass/dirt cells). Bucket is chosen by
	# which diamond edge faces a land neighbor so the ripple decorates the
	# water-meets-land boundary; interior cells get a small non-directional one.
	var bucket: String = _ripple_bucket_for(cell)
	var pool: Array = ripple_pools.get(bucket, [])
	if pool.is_empty():
		pool = ripple_pools.get("interior", [])
		if pool.is_empty():
			return
	var frames: Array = pool[_hash_pick(cell, pool.size())]
	if frames.is_empty():
		return
	var sf := SpriteFrames.new()
	sf.add_animation("ripple")
	sf.set_animation_loop("ripple", true)
	sf.set_animation_speed("ripple", 10.0)
	for t in frames:
		sf.add_frame("ripple", t)
	var a := AnimatedSprite2D.new()
	a.sprite_frames = sf
	a.animation = "ripple"
	a.play("ripple")
	a.centered = true
	a.offset = Vector2(0, SPRITE_Y_OFFSET)
	a.position = grid_to_screen(cell) + Vector2(0, float(cell.y) * 0.001)
	a.frame = _hash_pick(cell, max(1, frames.size()))
	# Froth shader recolors the cyan ripple sprite to white foam. Alpha is set
	# via the shader's froth_color uniform (more reliable than modulate.a for
	# canvas_item shaders). Almost-transparent so it reads as sub-surface foam.
	var froth_mat := ShaderMaterial.new()
	froth_mat.shader = FROTH_SHADER
	froth_mat.set_shader_parameter("froth_color", Color(0.95, 1.0, 1.0, 0.08))
	a.material = froth_mat
	a.modulate = Color(1, 1, 1, 1)
	world.add_child(a)
	sprites.append(a)

# ---- Maze biome --------------------------------------------------------------
# 2-cell-pitch grid: (even, even) = posts, (odd, odd) = rooms (walkable),
# mixed parity = wall edges. Each room deterministically picks ONE of its
# 4 walls to open as a corridor, guaranteeing every room has at least one
# exit. The biome border becomes solid hedge except where the path crosses
# (the path acts as an entrance).

const _MAZE_DIR_N := 0
const _MAZE_DIR_E := 1
const _MAZE_DIR_S := 2
const _MAZE_DIR_W := 3

func _maze_room_open_dir(room_cell: Vector2i) -> int:
	# Deterministic 0..3 picking which wall of this room is open.
	return int(_hash01(room_cell, 50001) * 4) % 4

func _maze_wall_is_open(wall_cell: Vector2i) -> bool:
	# Wall cells have one even coord and one odd coord. Find the two adjacent
	# rooms and check whether either of them picked this wall direction.
	var ex: bool = (wall_cell.x % 2 + 2) % 2 == 0
	var ey: bool = (wall_cell.y % 2 + 2) % 2 == 0
	if ex and ey:
		return false  # post
	if (not ex) and (not ey):
		return true   # room
	if ex:
		# Vertical wall between west room and east room.
		var west_room := wall_cell + Vector2i(-1, 0)
		var east_room := wall_cell + Vector2i(1, 0)
		if _maze_room_open_dir(west_room) == _MAZE_DIR_E: return true
		if _maze_room_open_dir(east_room) == _MAZE_DIR_W: return true
	else:
		# Horizontal wall between north room and south room.
		var north_room := wall_cell + Vector2i(0, -1)
		var south_room := wall_cell + Vector2i(0, 1)
		if _maze_room_open_dir(north_room) == _MAZE_DIR_S: return true
		if _maze_room_open_dir(south_room) == _MAZE_DIR_N: return true
	return false

func _is_maze_boundary(cell: Vector2i) -> bool:
	# True if this maze cell has at least one cardinal neighbor outside the maze biome.
	for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		if _biome_for(cell + d) != BIOME_MAZE:
			return true
	return false

func _place_maze_cell(cell: Vector2i, sprites: Array) -> void:
	if hedge_maze_pool.is_empty():
		return
	# The path slices through everything (acts as the maze entrance).
	if _is_on_path(cell):
		return
	# Solid boundary - any cell touching the outside world becomes a hedge wall.
	if _is_maze_boundary(cell):
		var bs := _make_sprite(_pick(hedge_maze_pool, cell, 99004), cell)
		world.add_child(bs)
		sprites.append(bs)
		_block_wall_cell(cell)
		return
	# Interior layout.
	var ex: bool = (cell.x % 2 + 2) % 2 == 0
	var ey: bool = (cell.y % 2 + 2) % 2 == 0
	var is_room: bool = (not ex) and (not ey)
	if is_room:
		return  # walkable
	var is_post: bool = ex and ey
	if not is_post:
		# Wall edge - opened only if a neighboring room picked this direction.
		if _maze_wall_is_open(cell):
			return
	var s := _make_sprite(_pick(hedge_maze_pool, cell, 99003), cell)
	world.add_child(s)
	sprites.append(s)
	_block_wall_cell(cell)

# --- Path edges --------------------------------------------------------------
#
# Ground A3_*  paint two adjacent diamond edges each (corner pieces):
#   A3_N -> right side  (NE + SE neighbors are grass)
#   A3_E -> bottom      (SE + SW)
#   A3_S -> left side   (SW + NW)
#   A3_W -> top         (NW + NE)
#
# We compute a 4-bit neighbor mask and look up the matching tile. Cells with
# only one grass neighbor (single-edge case) are skipped until we wire G6
# straight-edge tiles in the next pass.

const _NEIGHBOR_NE := Vector2i(0, -1)   # gy-1, top-right diamond edge
const _NEIGHBOR_SE := Vector2i(1, 0)    # gx+1, bottom-right
const _NEIGHBOR_SW := Vector2i(0, 1)    # gy+1, bottom-left
const _NEIGHBOR_NW := Vector2i(-1, 0)   # gx-1, top-left

const _MASK_NE := 1
const _MASK_SE := 2
const _MASK_SW := 4
const _MASK_NW := 8

func _natural_ground_is_grass(cell: Vector2i) -> bool:
	# Every cell that isn't a path or a clearing counts as grass for the
	# edge-neighbor check (matches _has_grass_cover).
	return _has_grass_cover(cell)

func _grass_neighbor_mask(cell: Vector2i) -> int:
	var m: int = 0
	if _natural_ground_is_grass(cell + _NEIGHBOR_NE): m |= _MASK_NE
	if _natural_ground_is_grass(cell + _NEIGHBOR_SE): m |= _MASK_SE
	if _natural_ground_is_grass(cell + _NEIGHBOR_SW): m |= _MASK_SW
	if _natural_ground_is_grass(cell + _NEIGHBOR_NW): m |= _MASK_NW
	return m

const _CORNER_FOR_MASK := {
	3:  "N",   # NE + SE -> right
	6:  "E",   # SE + SW -> bottom
	12: "S",   # SW + NW -> left
	9:  "W",   # NW + NE -> top
}

# A4 single-edge: bit -> tile suffix.
const _SINGLE_FOR_BIT := {
	1: "N",    # NE
	2: "E",    # SE
	4: "S",    # SW
	8: "W",    # NW
}

func _maybe_place_path_edges(cell: Vector2i, sprites: Array) -> void:
	var mask: int = _grass_neighbor_mask(cell)
	if mask == 0:
		return
	# Single grass neighbor -> A4 single-edge tile.
	if mask in [1, 2, 4, 8]:
		_place_single_edge(cell, _SINGLE_FOR_BIT[mask], sprites)
		return
	# Two adjacent grass neighbors -> A3 corner tile.
	if mask in [3, 6, 12, 9]:
		_place_corner_edge(cell, _CORNER_FOR_MASK[mask], sprites)
		return
	# Two opposite grass neighbors (NE+SW or SE+NW) -> stack two A4 singles.
	if mask == 5:        # NE + SW
		_place_single_edge(cell, "N", sprites)
		_place_single_edge(cell, "S", sprites)
		return
	if mask == 10:       # SE + NW
		_place_single_edge(cell, "E", sprites)
		_place_single_edge(cell, "W", sprites)
		return
	# Three-edge peninsula -> dominant pair as a corner + the leftover bit as a single.
	match mask:
		7:                                           # NE+SE+SW -> corner E + single N
			_place_corner_edge(cell, "E", sprites)
			_place_single_edge(cell, "N", sprites)
		14:                                          # SE+SW+NW -> corner S + single E
			_place_corner_edge(cell, "S", sprites)
			_place_single_edge(cell, "E", sprites)
		13:                                          # SW+NW+NE -> corner W + single S
			_place_corner_edge(cell, "W", sprites)
			_place_single_edge(cell, "S", sprites)
		11:                                          # NW+NE+SE -> corner N + single W
			_place_corner_edge(cell, "N", sprites)
			_place_single_edge(cell, "W", sprites)
		15:                                          # All four (isolated dirt cell) -> two opposite corners.
			_place_corner_edge(cell, "N", sprites)
			_place_corner_edge(cell, "S", sprites)

func _place_corner_edge(cell: Vector2i, dir_key: String, sprites: Array) -> void:
	var pool: Array = path_corner_dir.get(dir_key, [])
	if pool.is_empty():
		return
	var tex: Texture2D = pool[_hash_pick(cell, pool.size())]
	var s := _make_sprite(tex, cell)
	s.z_index = -1
	world.add_child(s)
	sprites.append(s)

func _place_single_edge(cell: Vector2i, dir_key: String, sprites: Array) -> void:
	var pool: Array = path_single_dir.get(dir_key, [])
	if pool.is_empty():
		# Fall back to corner tiles if singles are missing.
		pool = path_corner_dir.get(dir_key, [])
		if pool.is_empty():
			return
	var tex: Texture2D = pool[_hash_pick(cell, pool.size())]
	var s := _make_sprite(tex, cell)
	s.z_index = -1
	world.add_child(s)
	sprites.append(s)

func _make_sprite(tex: Texture2D, cell: Vector2i) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = true
	s.offset = Vector2(0, SPRITE_Y_OFFSET)
	# Tiebreak y-sort along the iso anti-diagonal so SW cells (higher row,
	# closer to the camera) draw IN FRONT of NE cells at the same screen.y.
	# Cells with col+row equal share screen.y; nudging by row * 0.001 gives
	# the south-west one a microscopic y bump that tips the y-sort the right
	# way without any visible position shift.
	var p: Vector2 = grid_to_screen(cell)
	p.y += float(cell.y) * 0.001
	s.position = p
	s.set_meta("cell", cell)
	return s

# Deterministic hash helpers ---------------------------------------------------

func _hash01(cell: Vector2i, salt: int) -> float:
	var h: int = (cell.x * 374761393) ^ (cell.y * 668265263) ^ (salt * 1274126177)
	h = (h ^ (h >> 13)) * 1274126177
	h = h & 0x7fffffff
	return float(h % 100000) / 100000.0

func _hash_pick(cell: Vector2i, count: int) -> int:
	if count <= 0:
		return 0
	return int(_hash01(cell, 7) * count) % count

# ---- shader / fx ------------------------------------------------------------

func _apply_wind_shader(sprite: Sprite2D, cell: Vector2i) -> void:
	# Each grass clump gets its own ShaderMaterial so we can vary the phase
	# uniform per-instance without affecting neighbors.
	var mat := ShaderMaterial.new()
	mat.shader = FLORA_SHADER
	mat.set_shader_parameter("phase", _hash01(cell, 13) * TAU)
	# Same per-pocket recolor as the breathe shader so tall grass shifts with
	# the surrounding plants.
	var hs: Vector3 = _color_shift_for(cell)
	mat.set_shader_parameter("hue_shift", hs.x)
	mat.set_shader_parameter("sat_mult", hs.y)
	mat.set_shader_parameter("val_mult", hs.z)
	sprite.material = mat

# ---- attack -----------------------------------------------------------------

const _ArrowScript := preload("res://arrow.gd")

# True when the player's currently-equipped mainhand is a ranged weapon
# (bow). Drives the attack_at branch that spawns an arrow projectile
# instead of doing a melee cone sweep.
func _player_is_ranged() -> bool:
	if player == null or not "_loadout" in player:
		return false
	return int(player._loadout.get("mainhand_class", ItemsDB.WeaponClass.NONE)) == ItemsDB.WeaponClass.RANGED

# Spawn an arrow toward the cursor with the rolled per-swing damage.
# Mirrors skeleton.gd's _fire_arrow_at_player except aimed at the
# mouse and not flagged from_enemy.
func _fire_player_arrow(origin: Vector2, dmg: int, facing: Vector2 = Vector2.ZERO) -> void:
	# Arrow direction is the player's facing vector — passed in from
	# attack_at so we use the same coords (subviewport / world space)
	# the player itself lives in. Calling `get_global_mouse_position`
	# from main.gd would query the WINDOW viewport (different coord
	# system than the player's SubViewport), aiming the arrow into a
	# wrong space.
	var dir_v: Vector2 = facing.normalized() if facing.length() > 0.01 else Vector2(1, 0)
	# Parent the arrow to the player's IMMEDIATE parent so the arrow
	# shares its coordinate space exactly. `world` (two levels up) and
	# the painted-world's TileMapLayer hierarchy in between can have
	# transforms that make `global_position = origin` land at the wrong
	# spot when the player isn't strictly at (0, 0) of every ancestor.
	var parent_node: Node = null
	if in_dungeon and dungeon:
		parent_node = dungeon
	elif player and player.get_parent():
		parent_node = player.get_parent()
	else:
		parent_node = world if world else self
	var arrow := _ArrowScript.new()
	arrow.direction = dir_v
	arrow.aim_target_pos = origin + dir_v * 2000.0
	arrow.damage = dmg
	parent_node.add_child(arrow)
	arrow.global_position = origin

func attack_at(origin: Vector2, dir_vec: Vector2) -> void:
	if dir_vec.length() < 0.01:
		return
	var facing := dir_vec.normalized()
	var hits: Array[Vector2i] = []
	for cell in flora_at.keys():
		var sprite: Sprite2D = flora_at[cell]
		if not is_instance_valid(sprite):
			continue
		var to_flora: Vector2 = sprite.position - origin
		var dist: float = to_flora.length()
		if dist > ATTACK_RADIUS or dist < 1.0:
			continue
		var ang: float = acos(clamp(to_flora.normalized().dot(facing), -1.0, 1.0))
		if ang > ATTACK_HALF_ANGLE:
			continue
		hits.append(cell)
	for cell in hits:
		_destroy_flora(cell)
	# Compute one swing's damage via combat.gd: equipped-weapon range +
	# affixes + Strength bonus. Same value applies to every enemy hit
	# in the cone so a single click reads consistently.
	var loadout: Dictionary = {}
	if player and "_loadout" in player:
		loadout = player._loadout
	var scaled_dmg: int = _CombatScript.compute_player_damage(stats, loadout)
	# If an active skill is firing, override radius / half-angle / damage
	# multiplier with what the SkillDef requested. Otherwise basic-attack
	# defaults stand. Single-target / circle / none shapes are handled
	# below; here we just compute the per-swing effective bounds.
	var radius: float = ATTACK_RADIUS
	var half_angle: float = ATTACK_HALF_ANGLE
	var skill_shape: String = "cone"
	var skill: Resource = (player.active_skill if player and "active_skill" in player else null)
	if skill != null:
		scaled_dmg = int(round(float(scaled_dmg) * float(skill.damage_mult)))
		radius = float(skill.damage_range)
		half_angle = deg_to_rad(float(skill.damage_angle_deg) * 0.5)
		skill_shape = String(skill.damage_shape)
		if skill_shape == "circle":
			half_angle = PI                       # all directions
		elif skill_shape == "none":
			return                                # self-buff, no damage
		# Apply per-skill damage_offset so cone / circle / single hitboxes
		# can land in front of / beside / behind the caster instead of
		# always centered on the body. Offset is in world px relative to
		# the player's facing direction (x = forward, y = strafe).
		if "damage_offset" in skill:
			var off: Vector2 = skill.damage_offset
			# Rotate the offset into the player's facing frame so a
			# slam authored as "40 px forward" lands forward from the
			# player regardless of which direction they're facing.
			var fwd_angle: float = facing.angle()
			origin = origin + off.rotated(fwd_angle)
	# Ranged weapon: spawn an arrow toward cursor + skip melee cone.
	# The arrow handles its own collision + damage on impact via
	# arrow.gd, so we just hand off the rolled damage value.
	if _player_is_ranged() and skill == null:
		_fire_player_arrow(origin, scaled_dmg, facing)
		return
	# Damage any skeletons caught in the cone (dungeon mode + overworld).
	var _skel_pool: Array = []
	if in_dungeon and dungeon and "skeletons" in dungeon:
		_skel_pool.append_array(dungeon.skeletons)
	_skel_pool.append_array(overworld_skeletons)
	if _skel_pool.size() > 0:
		var skel_dmg: int = scaled_dmg
		# Single-target shape: collect every valid hit, then keep only
		# the nearest one. Cone / circle hit everyone in range.
		var single_best: Node = null
		var single_best_d: float = INF
		for sk in _skel_pool:
			if sk == null or not is_instance_valid(sk) or sk.dead:
				continue
			var ground_d: float = (sk.global_position - origin).length()
			if ground_d > radius or ground_d < 1.0:
				continue
			var ang_s: float = acos(clamp((sk.global_position - origin).normalized().dot(facing), -1.0, 1.0))
			if ang_s > half_angle:
				continue
			if skill_shape == "single":
				if ground_d < single_best_d:
					single_best_d = ground_d
					single_best = sk
				continue
			if sk.has_method("take_damage"):
				sk.take_damage(skel_dmg)
				_spawn_damage_number(sk.global_position + Vector2(0, -32), skel_dmg)
		# Single-target preference: if the player is currently HOVERED
		# over a valid enemy that's also inside the cone, hit that one
		# instead of the closest. Lets the player aim — Diablo-style —
		# rather than always being forced onto the nearest target.
		if skill_shape == "single":
			var pick: Node = single_best
			if _hovered_enemy != null and is_instance_valid(_hovered_enemy) \
					and not _hovered_enemy.dead \
					and _skel_pool.has(_hovered_enemy):
				var hd: float = (_hovered_enemy.global_position - origin).length()
				if hd <= radius and hd >= 1.0:
					var hang: float = acos(clamp((_hovered_enemy.global_position - origin).normalized().dot(facing), -1.0, 1.0))
					if hang <= half_angle:
						pick = _hovered_enemy
			if pick != null and pick.has_method("take_damage"):
				pick.take_damage(skel_dmg)
				_spawn_damage_number(pick.global_position + Vector2(0, -32), skel_dmg)
	# Damage any aggressive monsters caught in the same cone.
	for m in active_spiders:
		if not is_instance_valid(m) or m.dead:
			continue
		var to_m: Vector2 = m.position - origin
		var d: float = to_m.length()
		if d > radius or d < 1.0:
			continue
		var ang: float = acos(clamp(to_m.normalized().dot(facing), -1.0, 1.0))
		if ang > half_angle:
			continue
		m.take_damage(scaled_dmg)
		# Diablo-feel feedback: knockback, damage number, screen shake.
		var push: Vector2 = (m.position - origin).normalized() * 28.0
		if "knockback_pending" in m:
			m.knockback_pending = push
		else:
			m.set_meta("knockback_pending", push)
		_spawn_damage_number(m.position + Vector2(0, -32), scaled_dmg)
		_camera_shake(4.0, 0.18)
	# Single-target swing: only the NEAREST goblin in the cone takes the
	# hit. Cleaver swings shouldn't damage every goblin in a 90° arc at
	# once — that one-shots the whole pack from a single click.
	var best_goblin: Node2D = null
	var best_d: float = radius + 1.0
	for g in goblins:
		if not is_instance_valid(g) or g.dead:
			continue
		var to_g: Vector2 = g.global_position - origin
		var dg: float = to_g.length()
		if dg > radius or dg < 1.0:
			continue
		var ang_g: float = acos(clamp(to_g.normalized().dot(facing), -1.0, 1.0))
		if ang_g > half_angle:
			continue
		if dg < best_d:
			best_d = dg
			best_goblin = g
	if best_goblin:
		best_goblin.take_damage(scaled_dmg)
		_spawn_damage_number(best_goblin.global_position + Vector2(0, -32), scaled_dmg)
		_camera_shake(4.0, 0.18)

var _shake_amp: float = 0.0
var _shake_left: float = 0.0
var _camera_base_offset: Vector2 = Vector2.ZERO
var _hovered_enemy: Node2D = null
var _hover_throttle: float = 0.0
const HOVER_PICK_RADIUS := 90.0
const HOVER_UPDATE_INTERVAL := 0.08

const PICKUP_RADIUS := 96.0

# Nearest-LootDrop pickup: scan the active container for any node in
# the "loot_drop" group within PICKUP_RADIUS, take its rolled item_id,
# resolve to the items_db entry, and equip it onto the player. Slots
# auto-equip — player has no inventory UI yet, so the choice is
# "wear the dropped piece or skip."
func _try_pickup_nearest_drop() -> void:
	if player == null or not is_instance_valid(player):
		return
	var origin: Vector2 = player.global_position
	var nearest: Node2D = null
	var best_d2: float = PICKUP_RADIUS * PICKUP_RADIUS
	for node in get_tree().get_nodes_in_group("loot_drop"):
		if node == null or not is_instance_valid(node):
			continue
		var d2: float = (node.global_position - origin).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			nearest = node
	if nearest != null:
		_pickup_drop(nearest)

# Click-on-icon entry point (called by LootDrop's Area2D input_event).
# Same logic as the E-key path: take the rolled identity, equip onto
# the player, despawn the visual.
func _pickup_drop(drop: Node) -> void:
	if drop == null or not is_instance_valid(drop) or not drop.has_method("pickup"):
		return
	var data: Dictionary = drop.pickup()
	var item_id: String = String(data.get("item_id", ""))
	if item_id == "":
		return
	# Route pickups into the inventory instead of auto-equipping. The
	# player opens the inventory panel to choose what to wear.
	if player and "_loadout" in player:
		var Inv := preload("res://inventory.gd")
		Inv.add_item(player._loadout, item_id)
		var L := preload("res://loadout.gd")
		L.save(player._loadout)

# Apply an item_id to the player's loadout: look up sheet folder + slot
# in items_db, push into loadout dict, equip on the LayeredCharacter,
# save profile so the change persists across sessions.
func _equip_item_id(item_id: String) -> void:
	var entry: Dictionary = {}
	for e in ItemsDB.build_catalog():
		if String(e["id"]) == item_id:
			entry = e
			break
	if entry.is_empty():
		return
	var slot_id: int = int(entry["slot"])
	var folder: String = String(entry["folder"])
	var layer: String = String(ItemsDB.SLOT_LAYER.get(slot_id, ""))
	if layer == "":
		return
	if player and "_loadout" in player:
		player._loadout[layer] = folder
		if slot_id == ItemsDB.Slot.MAINHAND:
			player._loadout["mainhand_class"] = int(entry["weapon_class"])
		Loadout.save(player._loadout)
	if player and player.has_method("reload_loadout"):
		player.reload_loadout()

func _camera_shake(amp: float, dur: float) -> void:
	_shake_amp = max(_shake_amp, amp)
	_shake_left = max(_shake_left, dur)

func _update_hovered_enemy() -> void:
	var mouse_pos: Vector2 = world.get_local_mouse_position()
	var nearest: Node2D = nearest_enemy_target(mouse_pos, HOVER_PICK_RADIUS)
	# Clear old hover if it changed.
	if _hovered_enemy != nearest and _hovered_enemy and is_instance_valid(_hovered_enemy):
		var old_spr := _enemy_sprite(_hovered_enemy)
		if old_spr and not (_hovered_enemy.get("_hit_flash") and float(_hovered_enemy._hit_flash) > 0.0):
			old_spr.modulate = Color.WHITE
		# Skeletons own their highlight sprite — clear it on hover loss.
		if _hovered_enemy.has_method("_clear_highlight"):
			_hovered_enemy._clear_highlight()
	_hovered_enemy = nearest
	# Always re-apply each tick so monster.gd's _hit_flash burst doesn't leave
	# us at white after it decays.
	if _hovered_enemy:
		var spr := _enemy_sprite(_hovered_enemy)
		if spr and not (_hovered_enemy.get("_hit_flash") and float(_hovered_enemy._hit_flash) > 0.0):
			spr.modulate = Color(1.5, 1.05, 1.05)
		# Skeletons: spawn the asset-based highlight ring on hover.
		if _hovered_enemy.has_method("_ensure_highlight"):
			_hovered_enemy._ensure_highlight()

func _enemy_sprite(enemy: Node) -> Sprite2D:
	for c in enemy.get_children():
		if c is Sprite2D:
			return c
	return null

func nearest_enemy_target(from: Vector2, max_dist: float) -> Node2D:
	var best: Node2D = null
	var best_d: float = max_dist
	for m in active_spiders:
		if not is_instance_valid(m) or m.dead:
			continue
		var d: float = (m.position - from).length()
		if d < best_d:
			best_d = d
			best = m
	# Goblins are also valid hover targets for the cursor pick.
	for g in goblins:
		if not is_instance_valid(g) or g.dead:
			continue
		var dg: float = (g.global_position - from).length()
		if dg < best_d:
			best_d = dg
			best = g
	# Skeletons (dungeon mode) also hoverable.
	if in_dungeon and dungeon and "skeletons" in dungeon:
		for sk in dungeon.skeletons:
			if not is_instance_valid(sk) or sk.dead:
				continue
			var ds: float = (sk.global_position - from).length()
			if ds < best_d:
				best_d = ds
				best = sk
	# Overworld test skeletons (painted-world spawn) — same hover rules.
	for sk2 in overworld_skeletons:
		if not is_instance_valid(sk2) or sk2.dead:
			continue
		var d2: float = (sk2.global_position - from).length()
		if d2 < best_d:
			best_d = d2
			best = sk2
	return best

func _spawn_damage_number(world_pos: Vector2, amount: int) -> void:
	# Parent into whichever container is active right now: dungeon when
	# we're in one (world is PROCESS_MODE_DISABLED in dungeon mode and
	# was hiding the numbers), otherwise the overworld root.
	var dn: Node2D = _DamageNumber.new()
	dn.set("amount", amount)
	dn.z_index = 4096
	var parent_node: Node = self
	if in_dungeon and dungeon:
		parent_node = dungeon
	elif world:
		parent_node = world
	parent_node.add_child(dn)
	# Absolute world coords — independent of parent transform.
	dn.global_position = world_pos + Vector2(randf_range(-12, 12), 0)

class _DamageNumber extends Node2D:
	var amount: int = 0
	var _life: float = 0.8
	var _t: float = 0.0
	var _font: Font
	func _ready() -> void:
		_font = ThemeDB.fallback_font
		# Absolute z-index so we never render behind a tile or wall.
		z_as_relative = false
		z_index = 4096
		# Don't y_sort with the world — pin to top.
		y_sort_enabled = false
		set_process(true)
		queue_redraw()
	func _process(delta: float) -> void:
		_t += delta
		position.y -= delta * 60.0
		modulate.a = clampf(1.0 - max(0.0, (_t - 0.3)) / max(0.001, _life - 0.3), 0.0, 1.0)
		if _t >= _life:
			queue_free()
	func _draw() -> void:
		if _font == null:
			_font = ThemeDB.fallback_font
		if _font == null:
			return
		var s: String = str(amount)
		var size: int = 22
		var col: Color = Color(1, 0.85, 0.4)
		# Manual outline via 8 offset draws so the number reads on any background.
		for ox in [-2, 0, 2]:
			for oy in [-2, 0, 2]:
				if ox == 0 and oy == 0: continue
				draw_string(_font, Vector2(ox, oy), s, HORIZONTAL_ALIGNMENT_CENTER, -1, size, Color(0, 0, 0))
		draw_string(_font, Vector2.ZERO, s, HORIZONTAL_ALIGNMENT_CENTER, -1, size, col)

func _destroy_flora(cell: Vector2i) -> void:
	var sprite: Sprite2D = flora_at.get(cell, null)
	if sprite == null or not is_instance_valid(sprite):
		flora_at.erase(cell)
		return
	var pos: Vector2 = sprite.position
	# Remove from chunk's sprite list so we don't try to free it twice on unload.
	for cv in loaded_chunks.keys():
		var arr: Array = loaded_chunks[cv]
		arr.erase(sprite)
	flora_at.erase(cell)
	sprite.queue_free()
	_spawn_grass_burst(pos)

func _spawn_grass_burst(world_pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.position = world_pos + Vector2(0, -16)
	p.emitting = true
	p.one_shot = true
	p.amount = 36
	p.lifetime = 0.9
	p.explosiveness = 1.0
	p.direction = Vector2(0, -0.4)
	p.spread = 160.0
	p.initial_velocity_min = 110.0
	p.initial_velocity_max = 230.0
	p.gravity = Vector2(0, 480)
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.scale_amount_min = 1.6
	p.scale_amount_max = 3.4
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.5, 0.78, 0.28, 1.0))
	gradient.add_point(0.7, Color(0.35, 0.55, 0.18, 0.9))
	gradient.set_color(1, Color(0.22, 0.4, 0.12, 0.0))
	p.color_ramp = gradient
	world.add_child(p)
	var t := get_tree().create_timer(p.lifetime + 0.2)
	t.timeout.connect(func(): if is_instance_valid(p): p.queue_free())

# Helpers exposed to the player script so it can call the attack with its
# current facing index without re-deriving the math here.
const DIR_VECS := [
	Vector2(1, 0),
	Vector2(0.7071, 0.7071),
	Vector2(0, 1),
	Vector2(-0.7071, 0.7071),
	Vector2(-1, 0),
	Vector2(-0.7071, -0.7071),
	Vector2(0, -1),
	Vector2(0.7071, -0.7071),
]

func dir_to_vec(dir: int) -> Vector2:
	return DIR_VECS[dir % 8]
