extends RefCounted
class_name IconAtlas

# Wraps the 64×64 icon spritesheet so any UI element (HUD buttons,
# inventory slots, ability bar, tooltips) can grab a single icon by
# (col, row) or linear index without re-cropping the sheet manually.
#
# Sheet:    res://assets/ui/Icons/64X64 DARK.png
# Cell:     64 × 64 px
# Layout:   16 columns × N rows (N depends on sheet height; computed
#           from texture size on first request).

const SHEET_PATH := "res://assets/ui/Icons/64X64 DARK.png"
const CELL := 64
const COLS := 16

# The PNG is 1024×22464 — way past the GPU's 16384-px texture limit on
# many cards (AMD RX 7000 series). Loading it as a plain Texture2D
# fails (uninitialised RID errors). Instead we keep an Image on the
# CPU side and slice each 64×64 cell into its own tiny ImageTexture
# on demand. The GPU never sees the giant sheet — only the small
# per-icon textures.
static var _sheet_img: Image = null
static var _cache: Dictionary = {}   # "col,row" -> ImageTexture
# Latches true after the first failed load attempt so we don't retry
# every frame. Without this the @tool scripts on every button were
# hammering FileAccess + flooding error logs until Godot froze.
static var _load_failed: bool = false

static func _ensure_image() -> Image:
	if _sheet_img != null:
		return _sheet_img
	if _load_failed:
		return null
	# Read the raw PNG bytes via FileAccess and decode into an Image
	# on the CPU — avoids the GPU upload that fails for the giant sheet.
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(SHEET_PATH)
	if bytes.is_empty():
		_load_failed = true
		push_warning("[IconAtlas] Could not read %s — icons disabled." % SHEET_PATH)
		return null
	var img := Image.new()
	var err: int = img.load_png_from_buffer(bytes)
	if err != OK or img.get_width() <= 0 or img.get_height() <= 0:
		_load_failed = true
		push_warning("[IconAtlas] Failed to decode sheet PNG (err=%d) — icons disabled." % err)
		return null
	# Force standard 8-bit RGBA. PNGs decoded to other formats can break
	# get_region / ImageTexture.create_from_image on some Godot builds,
	# producing tiny "zero-RID" textures that spam draw errors.
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	# Smoke-test: try to crop one cell and build a texture from it. If
	# that fails we never want to attempt slicing again — latch off.
	var probe: Image = img.get_region(Rect2i(0, 0, CELL, CELL))
	if probe == null or probe.get_width() != CELL:
		_load_failed = true
		push_warning("[IconAtlas] get_region probe failed — icons disabled.")
		return null
	var probe_tex: ImageTexture = ImageTexture.create_from_image(probe)
	if probe_tex == null or probe_tex.get_width() != CELL:
		_load_failed = true
		push_warning("[IconAtlas] ImageTexture probe failed — icons disabled.")
		return null
	_sheet_img = img
	return _sheet_img

static func rows() -> int:
	var img: Image = _ensure_image()
	if img == null:
		return 0
	return int(floor(float(img.get_height()) / float(CELL)))

# Returns an ImageTexture cropping the icon at (col, row). Cached.
static func at(col: int, row: int) -> Texture2D:
	if col < 0 or row < 0:
		return null
	var img: Image = _ensure_image()
	if img == null:
		return null
	var key := "%d,%d" % [col, row]
	# Cache hits get an extra validity check — a hot-reload could have
	# left a stale ImageTexture with an uninitialized RID in here.
	if _cache.has(key):
		var existing: Texture2D = _cache[key]
		if existing != null and is_instance_valid(existing) and existing.get_width() > 0:
			return existing
		_cache.erase(key)
	var x: int = col * CELL
	var y: int = row * CELL
	if x + CELL > img.get_width() or y + CELL > img.get_height():
		return null
	var sub: Image = img.get_region(Rect2i(x, y, CELL, CELL))
	if sub == null or sub.is_empty():
		return null
	var tex := ImageTexture.create_from_image(sub)
	if tex == null:
		return null
	_cache[key] = tex
	return tex

# Linear index helper — `n` left to right, top to bottom across the sheet.
static func at_index(n: int) -> Texture2D:
	if n < 0:
		return null
	return at(n % COLS, n / COLS)
