extends Node2D
class_name ExplosionAnim

# One-shot frame-sequence animation for destructible-tile explosions
# (Fantasy tileset Animations/Destructible tiles/...). Loads every PNG
# in the given folder, plays them in order at FPS, queue_frees on end.

const FPS := 24.0

static var _frame_cache: Dictionary = {}   # folder_path -> Array[Texture2D]

var _frames: Array[Texture2D] = []
var _frame_t: float = 0.0
var _sprite: Sprite2D

static func _load_frames(folder: String) -> Array[Texture2D]:
	if _frame_cache.has(folder):
		return _frame_cache[folder]
	var out: Array[Texture2D] = []
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
				out.append(t)
	_frame_cache[folder] = out
	return out

static func spawn(parent: Node, world_pos: Vector2, folder: String) -> Node2D:
	var script: Script = load("res://explosion_anim.gd")
	var a: Node2D = script.new()
	a.position = world_pos
	a.set("_frames", _load_frames(folder))
	parent.add_child(a)
	return a

func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = true
	_sprite.offset = Vector2(0, -42)
	if not _frames.is_empty():
		_sprite.texture = _frames[0]
	add_child(_sprite)
	z_index = 700

func _process(delta: float) -> void:
	if _frames.is_empty():
		queue_free()
		return
	_frame_t += delta * FPS
	var idx: int = int(floor(_frame_t))
	if idx >= _frames.size():
		queue_free()
		return
	_sprite.texture = _frames[idx]
