extends RefCounted
class_name ArpgUI

# Sci-fi dark-navy / cyan theme — Blue panel set + Red bars for HP, Blue
# bars for MP. Pixel-art assets are rendered with nearest-neighbour and
# stretched via NinePatchRect (no manual `scale` multiplications).

const UI := "res://assets/ui/Sprites"

# Sci-fi palette: deep navy with electric cyan accents.
const COL_BG := Color(0.05, 0.07, 0.12, 1.0)
const COL_PANEL_RIM := Color(0.30, 0.85, 1.00, 1.0)
const COL_TEXT := Color(0.75, 0.95, 1.00, 1.0)
const COL_TEXT_DIM := Color(0.45, 0.60, 0.78, 1.0)
const COL_ACCENT := Color(0.30, 0.85, 1.00, 1.0)        # cyan
const COL_ACCENT_HI := Color(0.90, 0.50, 1.00, 1.0)     # magenta secondary
const COL_HP := Color(0.95, 0.20, 0.30, 1.0)
const COL_HP_GLOW := Color(1.00, 0.55, 0.55, 1.0)
const COL_MP := Color(0.30, 0.65, 1.00, 1.0)
const COL_MP_GLOW := Color(0.55, 0.85, 1.00, 1.0)
const COL_XP := Color(0.30, 0.85, 1.00, 1.0)
const COL_BOSS := Color(0.95, 0.20, 0.30, 1.0)

# Sci-fi panel kit (Blue).
const TEX_PANEL          := UI + "/Panels/Blue/Window.png"
const TEX_PANEL_INNER    := UI + "/Panels/Blue/PanelDigital.png"
const TEX_PANEL_LARGE    := UI + "/Panels/Blue/PanelLarge.png"
const TEX_PANEL_OUTLINED := UI + "/Panels/Blue/PanelOutlined.png"
const TEX_GRID_SLOT      := UI + "/Panels/Blue/GridPanel.png"
const TEX_GRID_SLOT_FRM  := UI + "/Panels/Blue/GridPanelFrame.png"
const TEX_FRAME_DIGITAL  := UI + "/Panels/Blue/FrameDigitalA.png"

# Bars: HP red, MP/boss/enemy blue.
const TEX_HP_BG     := UI + "/ValueBars/Red/RegularBarABackground.png"
const TEX_HP_FILL   := UI + "/ValueBars/Red/RegularBarAFill.png"
const TEX_HP_FRAME  := UI + "/ValueBars/Red/RegularBarAForeground.png"
const TEX_MP_BG     := UI + "/ValueBars/Blue/RegularBarABackground.png"
const TEX_MP_FILL   := UI + "/ValueBars/Blue/RegularBarAFill.png"
const TEX_MP_FRAME  := UI + "/ValueBars/Blue/RegularBarAForeground.png"
const TEX_BOSS_BG   := UI + "/ValueBars/Blue/BossBarABackground.png"
const TEX_BOSS_FILL := UI + "/ValueBars/Blue/BossBarAFill.png"
const TEX_BOSS_FRM  := UI + "/ValueBars/Blue/BossBarAForeground.png"
const TEX_ENEMY_BG  := UI + "/ValueBars/Red/MinimalBarBackground.png"
const TEX_ENEMY_FL  := UI + "/ValueBars/Red/MinimalBarFill.png"
const TEX_ENEMY_FRM := UI + "/ValueBars/Red/MinimalBarForeground.png"

const TEX_PORTRAIT_PLAYER := UI + "/Portraits/PlayerLarge.png"
const TEX_PORTRAIT_PLAYER_SMALL := UI + "/Portraits/PlayerSmall.png"
const TEX_PORTRAIT_FRAME  := UI + "/Portraits/PlayerSmallFrame.png"
const TEX_PORTRAIT_ENEMY  := UI + "/Portraits/EnemySmall.png"
const TEX_PORTRAIT_ENEMY_FRM := UI + "/Portraits/EnemySmallFrame.png"
const TEX_BANNER   := UI + "/Banners/Blue/BannerA.png"
const TEX_BANNER_TITLE := UI + "/Banners/Blue/TitleBanner.png"

# Skill tree.
const TEX_SKILL_SLOT      := UI + "/SkillTree/Blue/SkillSlotSharp.png"
const TEX_SKILL_SLOT_PH   := UI + "/SkillTree/Blue/SkillSlotSharpPlaceholder.png"
const TEX_SKILL_SELECTOR  := UI + "/SkillTree/Blue/SelectorSharp.png"

# Hotbar slot.
const TEX_HOTBAR_SLOT := UI + "/Panels/Blue/GridPanel.png"
const TEX_HOTBAR_FRAME := UI + "/Panels/Blue/GridPanelFrame.png"

# 9-patch margins per asset family.
const PANEL_PATCH := 12
const SLOT_PATCH := 5

# Per-bar 9-slice config taken from the Unity demo's .meta files
# (spriteBorder: {x:L, y:B, z:R, w:T}).
const _BAR_SLICES := {
	# RegularBarA 16×8 → L=1 R=1 T=4 B=1 ;  Fill 12×4 → L=1 R=1
	"hp":    {"bg_l": 1, "bg_r": 1, "bg_t": 4, "bg_b": 1, "f_l": 1, "f_r": 1, "f_h": 0.5,  "f_y": 0.25},
	"mp":    {"bg_l": 1, "bg_r": 1, "bg_t": 4, "bg_b": 1, "f_l": 1, "f_r": 1, "f_h": 0.5,  "f_y": 0.25},
	# BossBarA 32×8 → L=9 R=9 T=2 B=2 ;  Fill 20×4 → L=3 R=3 T=0 B=3
	"boss":  {"bg_l": 9, "bg_r": 9, "bg_t": 2, "bg_b": 2, "f_l": 3, "f_r": 3, "f_h": 0.5,  "f_y": 0.25},
	# MinimalBar 16×6 → L=1 R=1 T=1 B=1
	"enemy": {"bg_l": 1, "bg_r": 1, "bg_t": 1, "bg_b": 1, "f_l": 1, "f_r": 1, "f_h": 0.34, "f_y": 0.33},
}

# UI upscale factor: render the HUD into a SubViewport at (screen / UI_SCALE)
# with nearest-neighbour, then linear-filter that viewport up to screen size
# so pixel art reads smoothly without going chunky.
const UI_SCALE := 6

# Wraps a CanvasLayer's children in a SubViewportContainer→SubViewport tree.
# Returns the root Control to parent UI under. The caller is expected to
# call `sync_scaled_viewport(layer)` from _process (or a resize signal) to
# keep the viewport sized correctly.
static func make_scaled_root(layer: CanvasLayer) -> Control:
	var container := SubViewportContainer.new()
	container.stretch = true                          # vp output stretches to container
	container.stretch_shrink = UI_SCALE               # vp.size = container.size / UI_SCALE
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	layer.add_child(container)
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.handle_input_locally = false
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(vp)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp.add_child(root)
	layer.set_meta("_ui_vp", vp)
	layer.set_meta("_ui_root", root)
	sync_scaled_viewport(layer)
	return root

static func sync_scaled_viewport(layer: CanvasLayer) -> void:
	var vp = layer.get_meta("_ui_vp", null)
	var root = layer.get_meta("_ui_root", null)
	if vp == null or root == null or not is_instance_valid(vp) or not is_instance_valid(root):
		return
	# With stretch + stretch_shrink, the container drives vp.size — we just
	# mirror it onto the root Control so anchors compute against the viewport.
	if root.size != Vector2(vp.size):
		root.size = Vector2(vp.size)
		root.position = Vector2.ZERO

static func tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null

static func panel(size: Vector2, kind: String = "window") -> NinePatchRect:
	var path: String = TEX_PANEL
	var p: int = PANEL_PATCH
	match kind:
		"inner":     path = TEX_PANEL_INNER
		"large":     path = TEX_PANEL_LARGE
		"outlined":  path = TEX_PANEL_OUTLINED
		"slot":
			path = TEX_GRID_SLOT
			p = SLOT_PATCH
		"slot_frame":
			path = TEX_GRID_SLOT_FRM
			p = SLOT_PATCH
		"frame_digital":
			path = TEX_FRAME_DIGITAL
			p = 8
	var t: Texture2D = tex(path)
	if t == null:
		return null
	var n := NinePatchRect.new()
	n.texture = t
	n.size = size
	n.patch_margin_left = p
	n.patch_margin_top = p
	n.patch_margin_right = p
	n.patch_margin_bottom = p
	n.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return n

static func styled_label(text: String, font_size: int = 14, color: Color = COL_TEXT) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.08, 1.0))
	lbl.add_theme_constant_override("outline_size", 3)
	return lbl

# Composite bar built from 9-patch background, foreground, and a clip-
# wrapped 9-patch fill. Stretches cleanly to any width.
static func make_bar(width: int, kind: String = "hp") -> Control:
	var bg_path: String = TEX_HP_BG
	var fill_path: String = TEX_HP_FILL
	var frm_path: String = TEX_HP_FRAME
	var fill_color: Color = COL_HP
	var glow_color: Color = COL_HP_GLOW
	if kind == "mp":
		bg_path = TEX_MP_BG; fill_path = TEX_MP_FILL; frm_path = TEX_MP_FRAME
		fill_color = COL_MP; glow_color = COL_MP_GLOW
	elif kind == "boss":
		bg_path = TEX_BOSS_BG; fill_path = TEX_BOSS_FILL; frm_path = TEX_BOSS_FRM
		fill_color = COL_HP; glow_color = Color(1, 0.5, 0.5)
	elif kind == "enemy":
		bg_path = TEX_ENEMY_BG; fill_path = TEX_ENEMY_FL; frm_path = TEX_ENEMY_FRM
	var bg_tex: Texture2D = tex(bg_path)
	if bg_tex == null:
		var fb := ColorRect.new()
		fb.color = fill_color
		fb.custom_minimum_size = Vector2(width, 12)
		fb.set_meta("_arpg_bar_fallback", true)
		return fb
	var slice = _BAR_SLICES.get(kind, _BAR_SLICES["hp"])
	var native_h: int = bg_tex.get_height()
	var bar_h: int = max(native_h * 4, 24)        # integer 4× display
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(width, bar_h)
	holder.size = holder.custom_minimum_size
	# Background as 9-patch (caps cover the diagonal trapezoid corners).
	var bg := NinePatchRect.new()
	bg.texture = bg_tex
	bg.size = Vector2(width, bar_h)
	bg.patch_margin_left = int(slice["bg_l"])
	bg.patch_margin_right = int(slice["bg_r"])
	bg.patch_margin_top = int(slice.get("bg_t", 0))
	bg.patch_margin_bottom = int(slice.get("bg_b", 0))
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	holder.add_child(bg)
	# Fill clipper — fill is roughly half the height of the frame (the
	# "middle row" the user described), centred vertically.
	var fill_h: int = int(bar_h * float(slice["f_h"]))
	var fill_y: int = int(bar_h * float(slice["f_y"]))
	var fill_clip := Control.new()
	fill_clip.clip_contents = true
	fill_clip.position = Vector2(0, fill_y)
	fill_clip.size = Vector2(width, fill_h)
	holder.add_child(fill_clip)
	var fill_tex: Texture2D = tex(fill_path)
	if fill_tex:
		var fill := NinePatchRect.new()
		fill.texture = fill_tex
		fill.size = Vector2(width, fill_h)
		fill.patch_margin_left = int(slice["f_l"])
		fill.patch_margin_right = int(slice["f_r"])
		fill.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		fill_clip.add_child(fill)
	# Foreground frame on top.
	var frm_tex: Texture2D = tex(frm_path)
	if frm_tex:
		var frm := NinePatchRect.new()
		frm.texture = frm_tex
		frm.size = Vector2(width, bar_h)
		frm.patch_margin_left = int(slice["bg_l"])
		frm.patch_margin_right = int(slice["bg_r"])
		frm.patch_margin_top = int(slice.get("bg_t", 0))
		frm.patch_margin_bottom = int(slice.get("bg_b", 0))
		frm.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		holder.add_child(frm)
	holder.set_meta("_fill_clip", fill_clip)
	holder.set_meta("_fill_color", fill_color)
	holder.set_meta("_glow_color", glow_color)
	holder.set_meta("_full_width", float(width))
	holder.set_script(_BarLogic())
	return holder

# Player composite status bar:
#   • FighterBar (Red) — main HP bar, two-row stepped trapezoid. The bottom
#     row is offset left and ends partway across.
#   • Two FighterBarSecondary (Red) bars — sit on the bottom row to the
#     RIGHT of where the FighterBar's bottom row ends (mana / energy / etc).
# Returns a Control with set_hp(v,m), set_secondary(idx, v, m).
static func make_player_status_bar(width: int, height: int = 80) -> Control:
	# Per the Unity FighterBar prefab: render at NATIVE pixel dimensions
	# inside the viewport (root 55×10, fill inset 3 px). The SubViewport
	# wrapper handles the visible upscale with linear filtering.
	var bar_h: int = 10                                # FighterBar native height
	var holder := Control.new()
	holder.size = Vector2(width, height)
	holder.custom_minimum_size = holder.size

	# --- Main HP bar (FighterBar) -------------------------------------------
	# The FighterBar takes the FULL bar width. Its top row is the wide
	# parallelogram (HP); its bottom row is a fixed-size stepped tag on the
	# left (captured in the L=18 cap of the 9-slice — stays the source's
	# native 18 px wide regardless of total width).
	var fb_w: int = width
	var fb_y: int = int((height - bar_h) * 0.5)
	var bottom_tag_end_x: int = 18                     # source col where bottom-row tag ends
	var fb_bg_tex: Texture2D = tex(UI + "/ValueBars/Red/FighterBarBackground.png")
	var fb_fill_tex: Texture2D = tex(UI + "/ValueBars/Red/FighterBarFill.png")
	# Tiled middle preserves the stepped silhouette better than stretching.
	if fb_bg_tex:
		var fb_bg := NinePatchRect.new()
		fb_bg.texture = fb_bg_tex
		fb_bg.position = Vector2(0, fb_y)
		fb_bg.size = Vector2(fb_w, bar_h)
		# Unity meta: spriteBorder L=18, B=5, R=8, T=1
		fb_bg.patch_margin_left = 18
		fb_bg.patch_margin_right = 8
		fb_bg.patch_margin_top = 1
		fb_bg.patch_margin_bottom = 5
		fb_bg.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
		fb_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		holder.add_child(fb_bg)

	# Clip the fill to ONLY the top band (rows 0-5 of the bar). The fill's
	# 9-slice middle has filled pixels in its bottom band that, when
	# stretched horizontally, would bleed across the bottom row where the
	# mana secondaries live. Limiting clip height to the top band keeps the
	# bottom row clean for the secondaries.
	var top_band_h: int = 6
	var fb_clip := Control.new()
	fb_clip.position = Vector2(0, fb_y)
	fb_clip.size = Vector2(fb_w, top_band_h)
	fb_clip.clip_contents = true
	holder.add_child(fb_clip)
	if fb_fill_tex:
		var fb_fill := NinePatchRect.new()
		fb_fill.texture = fb_fill_tex
		fb_fill.size = Vector2(fb_w, bar_h)
		# Unity meta: spriteBorder L=17, B=5, R=8, T=1
		fb_fill.patch_margin_left = 17
		fb_fill.patch_margin_right = 8
		fb_fill.patch_margin_top = 1
		fb_fill.patch_margin_bottom = 5
		fb_fill.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		fb_clip.add_child(fb_fill)

		# Second clip: just the bottom-band TAG area (left 18 px of bottom
		# row). The fill draws at full bar size, offset upward so its
		# bottom-band content lands inside this small clip — preserving
		# red fill in the FIGHTERBAR tag region. HP-driven via the same
		# clipper.
		var tag_clip := Control.new()
		tag_clip.position = Vector2(0, fb_y + top_band_h)
		tag_clip.size = Vector2(bottom_tag_end_x, bar_h - top_band_h)
		tag_clip.clip_contents = true
		holder.add_child(tag_clip)
		var fb_tag_fill := NinePatchRect.new()
		fb_tag_fill.texture = fb_fill_tex
		fb_tag_fill.size = Vector2(fb_w, bar_h)
		fb_tag_fill.position = Vector2(0, -top_band_h)
		fb_tag_fill.patch_margin_left = 17
		fb_tag_fill.patch_margin_right = 8
		fb_tag_fill.patch_margin_top = 1
		fb_tag_fill.patch_margin_bottom = 5
		fb_tag_fill.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tag_clip.add_child(fb_tag_fill)
		holder.set_meta("_tag_clip", tag_clip)
		holder.set_meta("_tag_full_w", float(bottom_tag_end_x))

	# --- Secondary bars (two): sit on the bottom band immediately AFTER
	#     the FighterBar's bottom-row tag, filling the remaining bottom row.
	var sec_h: int = 5                                  # native FighterBarSecondary height
	var sec_y: int = fb_y + 5                           # row 5 — top of the bottom band
	var sec_gap: int = 2
	var sec_origin_x: int = bottom_tag_end_x + 1
	var remaining_w: int = fb_w - sec_origin_x
	var sec_w: int = int((remaining_w - sec_gap) * 0.5)

	var sec_bg_tex: Texture2D = tex(UI + "/ValueBars/Red/FighterBarSecondaryBackground.png")
	var sec_fill_tex: Texture2D = tex(UI + "/ValueBars/Red/FighterBarSecondaryFill.png")
	var sec_fg_tex: Texture2D = tex(UI + "/ValueBars/Red/FighterBarSecondaryForeground.png")
	var sec_clips: Array = []
	for i in range(2):
		var sx: int = sec_origin_x + i * (sec_w + sec_gap)
		if sec_bg_tex:
			var sb := NinePatchRect.new()
			sb.texture = sec_bg_tex
			sb.position = Vector2(sx, sec_y)
			sb.size = Vector2(sec_w, sec_h)
			# SecondaryBackground 32×5 → L=4 R=4
			sb.patch_margin_left = 4
			sb.patch_margin_right = 4
			sb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			holder.add_child(sb)
		# Inset the fill to fit inside the BG's frame outline, leaving the
		# slope-cut left edge visible. The Foreground (28×3) is 4 px
		# narrower and 2 px shorter than the BG (32×5), centred — same
		# inset pattern: 2 px each side horizontally, 1 px each side vertically.
		var fill_inset_x: int = 2
		var fill_inset_y: int = 1
		var fill_w: int = max(sec_w - fill_inset_x * 2, 0)
		var fill_h: int = max(sec_h - fill_inset_y * 2, 0)
		var sc := Control.new()
		sc.position = Vector2(sx + fill_inset_x, sec_y + fill_inset_y)
		sc.size = Vector2(fill_w, fill_h)
		sc.clip_contents = true
		holder.add_child(sc)
		if sec_fill_tex:
			var sf := NinePatchRect.new()
			sf.texture = sec_fill_tex
			sf.size = Vector2(fill_w, fill_h)
			# SecondaryFill 24×1 → L=0 R=4
			sf.patch_margin_left = 0
			sf.patch_margin_right = 4
			sf.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sc.add_child(sf)
		if sec_fg_tex:
			var sg := NinePatchRect.new()
			sg.texture = sec_fg_tex
			sg.position = Vector2(sx, sec_y)
			sg.size = Vector2(sec_w, sec_h)
			# SecondaryForeground 28×3 → L=3 R=3 T=1 B=1
			sg.patch_margin_left = 3
			sg.patch_margin_right = 3
			sg.patch_margin_top = 1
			sg.patch_margin_bottom = 1
			sg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			holder.add_child(sg)
		sec_clips.append({"clip": sc, "full_w": float(fill_w)})

	holder.set_meta("_hp_clip", fb_clip)
	holder.set_meta("_hp_full_w", float(fb_w))
	holder.set_meta("_sec", sec_clips)
	holder.set_script(_StatusBarLogic())
	return holder

static func _StatusBarLogic() -> Script:
	var s := GDScript.new()
	s.source_code = "extends Control\n" \
		+ "func set_hp(v: float, m: float) -> void:\n" \
		+ "\tvar t: float = clamp(v / max(m, 1.0), 0.0, 1.0)\n" \
		+ "\tvar c = get_meta('_hp_clip', null)\n" \
		+ "\tvar w: float = float(get_meta('_hp_full_w', size.x))\n" \
		+ "\tif c and is_instance_valid(c):\n" \
		+ "\t\tc.size = Vector2(w * t, c.size.y)\n" \
		+ "\tvar tc = get_meta('_tag_clip', null)\n" \
		+ "\tvar tw: float = float(get_meta('_tag_full_w', 0.0))\n" \
		+ "\tif tc and is_instance_valid(tc):\n" \
		+ "\t\ttc.size = Vector2(tw * t, tc.size.y)\n" \
		+ "func set_secondary(idx: int, v: float, m: float) -> void:\n" \
		+ "\tvar arr = get_meta('_sec', [])\n" \
		+ "\tif idx < 0 or idx >= arr.size():\n" \
		+ "\t\treturn\n" \
		+ "\tvar t: float = clamp(v / max(m, 1.0), 0.0, 1.0)\n" \
		+ "\tvar c = arr[idx]['clip']\n" \
		+ "\tvar w: float = float(arr[idx]['full_w'])\n" \
		+ "\tif c and is_instance_valid(c):\n" \
		+ "\t\tc.size = Vector2(w * t, c.size.y)\n"
	s.reload()
	return s

static func _BarLogic() -> Script:
	var s := GDScript.new()
	s.source_code = "extends Control\n" \
		+ "var _value: float = 1.0\n" \
		+ "var _flash_t: float = 0.0\n" \
		+ "func set_value(v: float, m: float) -> void:\n" \
		+ "\tvar t: float = clamp(v / max(m, 1.0), 0.0, 1.0)\n" \
		+ "\tvar fc = get_meta('_fill_clip', null)\n" \
		+ "\tvar fw: float = float(get_meta('_full_width', size.x))\n" \
		+ "\tif fc and is_instance_valid(fc):\n" \
		+ "\t\tfc.size = Vector2(fw * t, size.y)\n" \
		+ "\tif t < _value - 0.01:\n" \
		+ "\t\t_flash_t = 0.18\n" \
		+ "\t_value = t\n" \
		+ "func _process(dt: float) -> void:\n" \
		+ "\tif _flash_t > 0.0:\n" \
		+ "\t\t_flash_t = max(0.0, _flash_t - dt)\n" \
		+ "\t\tmodulate = Color(1.4, 1.0, 1.0) if _flash_t > 0.0 else Color(1,1,1)\n"
	s.reload()
	return s
