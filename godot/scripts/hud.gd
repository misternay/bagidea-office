extends CanvasLayer
## 2D GUI layer: crisp screen-space text replacing unreadable in-world labels.
## - MMO-style nameplates that track characters: portrait + name + role +
##   live status, with a state accent border.
## - Meeting-minutes panel pinned over the meeting room.
## - Replay Theater marquee banner.

var _plates := {}  # agent Node3D -> {root, sub, role, pill, pill_label, pill_style}

const STATE_COLORS := {
	"idle": Color(0.35, 0.9, 0.5),
	"working": Color(0.4, 0.8, 1.0),
	"meeting": Color(0.8, 0.55, 1.0),
	"blocked": Color(1.0, 0.72, 0.32),
	"offline": Color(0.6, 0.63, 0.72),
}
var _fx_list: Array = []  # {s: Sprite2D, agent, frames, loops, t}
var _wb_panel: PanelContainer
var _wb_box: VBoxContainer
var _wb_lines: Array[String] = []
var _theater_banner: Label

func _ready() -> void:
	layer = 2
	_build_whiteboard()
	_build_theater_banner()

# ---------------------------------------------------------------- nameplates

# Tiny baked rank icons (pixel art — the 3D HUD font has no color emoji).
const CROWN_ART: Array[String] = [
	"y...y...y",
	"y..yyy..y",
	"yy.yyy.yy",
	"yyyyyyyyy",
	".yyyyyyy.",
]
const STAR_ART: Array[String] = [
	"....c....",
	"...ccc...",
	"ccccccccc",
	".ccccccc.",
	"..ccccc..",
	".ccc.ccc.",
	".c.....c.",
]
static var _crown_tex: ImageTexture
static var _star_tex: ImageTexture

static func _bake_icon(art: Array[String], col: Color) -> ImageTexture:
	var w: int = art[0].length()
	var h: int = art.size()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			if art[y][x] != ".":
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

## Rank dressing: the CEO (the owner) wears gold + a crown; the Director
## (main) wears bright blue + a lead star — both readable at a glance,
## mirroring the chat rail.
func register(agent: Node3D, display_name: String, role: String,
		portrait: Texture2D, accent: Color) -> void:
	var rank := str(agent.get("rank")) if agent.get("rank") != null else "staff"
	var bg := Color(0.04, 0.06, 0.11, 0.82)
	var border := Color(accent.r, accent.g, accent.b, 0.85)
	var name_col := Color(0.96, 0.98, 1.0)
	var icon_tex: ImageTexture = null
	if rank == "ceo":
		bg = Color(0.2, 0.13, 0.02, 0.88)
		border = Color(1.0, 0.8, 0.35, 0.95)
		name_col = Color(1.0, 0.92, 0.66)
		if _crown_tex == null:
			_crown_tex = _bake_icon(CROWN_ART, Color(1.0, 0.8, 0.3))
		icon_tex = _crown_tex
	elif rank == "lead":
		bg = Color(0.02, 0.1, 0.17, 0.88)
		border = Color(0.4, 0.82, 1.0, 0.95)
		name_col = Color(0.78, 0.95, 1.0)
		if _star_tex == null:
			_star_tex = _bake_icon(STAR_ART, Color(0.45, 0.85, 1.0))
		icon_tex = _star_tex

	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(8)
	style.set_border_width_all(2 if icon_tex else 1)
	style.border_color = border
	style.content_margin_left = 7
	style.content_margin_right = 9
	style.content_margin_top = 3
	style.content_margin_bottom = 4

	var root := PanelContainer.new()
	root.add_theme_stylebox_override("panel", style)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.z_index = 5

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 7)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hb)

	if portrait:
		var frame := PanelContainer.new()
		var fstyle := StyleBoxFlat.new()
		fstyle.bg_color = Color(accent.r, accent.g, accent.b, 0.25)
		fstyle.set_corner_radius_all(6)
		fstyle.set_content_margin_all(1)
		frame.add_theme_stylebox_override("panel", fstyle)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pic := TextureRect.new()
		pic.texture = portrait
		pic.custom_minimum_size = Vector2(28, 28)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(pic)
		hb.add_child(frame)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 4)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(name_row)
	if icon_tex:
		var badge := TextureRect.new()
		badge.texture = icon_tex
		badge.custom_minimum_size = Vector2(icon_tex.get_width() * 2, icon_tex.get_height() * 2)
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_row.add_child(badge)
	var nm := Label.new()
	nm.text = display_name
	nm.add_theme_font_size_override("font_size", 13)
	nm.add_theme_color_override("font_color", name_col)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(nm)

	var sub := Label.new()
	sub.text = role
	sub.add_theme_font_size_override("font_size", 10)
	sub.add_theme_color_override("font_color", Color(0.62, 0.68, 0.78))
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(sub)

	# State pill: every agent in the office shows its live state at a glance.
	var pill := PanelContainer.new()
	var pill_style := StyleBoxFlat.new()
	pill_style.bg_color = Color(0.35, 0.9, 0.5, 0.16)
	pill_style.set_corner_radius_all(6)
	pill_style.set_border_width_all(1)
	pill_style.border_color = Color(0.35, 0.9, 0.5, 0.7)
	pill_style.content_margin_left = 6
	pill_style.content_margin_right = 6
	pill_style.content_margin_top = 0
	pill_style.content_margin_bottom = 1
	pill.add_theme_stylebox_override("panel", pill_style)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var pill_label := Label.new()
	pill_label.text = "IDLE"
	pill_label.add_theme_font_size_override("font_size", 9)
	pill_label.add_theme_color_override("font_color", Color(0.35, 0.9, 0.5))
	pill_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(pill_label)
	vb.add_child(pill)

	add_child(root)
	_plates[agent] = {"root": root, "sub": sub, "role": role,
		"pill": pill, "pill_label": pill_label, "pill_style": pill_style}

func set_status(agent: Node3D, text: String) -> void:
	if not _plates.has(agent):
		return
	var p: Dictionary = _plates[agent]
	# Containers grow with long text but never shrink back on their own —
	# snap the plate back to its minimum size after every change.
	p.root.reset_size.call_deferred()
	if text == "":
		p.sub.text = p.role
		p.sub.add_theme_color_override("font_color", Color(0.62, 0.68, 0.78))
	else:
		p.sub.text = text
		var c := Color(0.55, 0.85, 1.0)
		if "⚠" in text or "approval" in text:
			c = Color(1.0, 0.72, 0.35)
		elif "✗" in text or "failed" in text or "denied" in text:
			c = Color(1.0, 0.45, 0.4)
		elif "✓" in text or "done" in text:
			c = Color(0.45, 0.95, 0.6)
		elif "💤" in text or "offline" in text:
			c = Color(0.55, 0.58, 0.7)
		p.sub.add_theme_color_override("font_color", c)

func set_state(agent: Node3D, state: String) -> void:
	if not _plates.has(agent):
		return
	var p: Dictionary = _plates[agent]
	var c: Color = STATE_COLORS.get(state, Color(0.6, 0.65, 0.75))
	p.pill_label.text = state.to_upper()
	p.pill_label.add_theme_color_override("font_color", c)
	p.pill_style.bg_color = Color(c.r, c.g, c.b, 0.16)
	p.pill_style.border_color = Color(c.r, c.g, c.b, 0.7)
	p.root.reset_size.call_deferred()

func unregister(agent: Node3D) -> void:
	if _plates.has(agent):
		_plates[agent].root.queue_free()
		_plates.erase(agent)

# ---------------------------------------------------------------- pixel fx

## Event FX on the HUD itself — drawn ABOVE the nameplates (z 20 vs 5),
## floating over the plate while tracking the character. 15 fps strips.
func fx(agent: Node3D, tex: Texture2D, frames: int, loops := 1) -> void:
	var s := Sprite2D.new()
	s.texture = tex
	s.hframes = frames
	s.frame = 0
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.z_index = 20
	add_child(s)
	_fx_list.append({"s": s, "agent": agent, "frames": frames, "loops": loops, "t": 0.0})

func _track_fx(delta: float, cam: Camera3D) -> void:
	for i in range(_fx_list.size() - 1, -1, -1):
		var f: Dictionary = _fx_list[i]
		f.t += delta
		var idx := int(f.t * 15.0)
		if idx >= f.frames * f.loops or not is_instance_valid(f.agent):
			f.s.queue_free()
			_fx_list.remove_at(i)
			continue
		f.s.frame = idx % f.frames
		var wp: Vector3 = f.agent.global_position + Vector3(0, 1.0, 0)
		if cam.is_position_behind(wp):
			f.s.visible = false
			continue
		f.s.visible = true
		var dist := cam.global_position.distance_to(wp)
		var sc: float = clampf(44.0 / dist, 0.62, 1.2) * 1.9
		f.s.scale = Vector2(sc, sc)
		# Hover just above the nameplate.
		f.s.position = cam.unproject_position(wp) - Vector2(0, 74.0 * sc * 0.55)

# ---------------------------------------------------------------- whiteboard

func _build_whiteboard() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.05, 0.13, 0.85)
	style.set_corner_radius_all(10)
	style.set_border_width_all(1)
	style.border_color = Color(0.7, 0.55, 1.0, 0.8)
	style.set_content_margin_all(10)
	_wb_panel = PanelContainer.new()
	_wb_panel.add_theme_stylebox_override("panel", style)
	_wb_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wb_panel.visible = false
	_wb_box = VBoxContainer.new()
	_wb_box.add_theme_constant_override("separation", 1)
	_wb_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wb_panel.add_child(_wb_box)
	add_child(_wb_panel)

func wb_reset(header: String) -> void:
	_wb_lines.clear()
	if header != "":
		_wb_lines.append(header)
	_wb_refresh()

func wb_add(line: String) -> void:
	_wb_lines.append(line.left(150))
	while _wb_lines.size() > 6:
		# keep the header, trim the oldest body line
		_wb_lines.remove_at(1 if _wb_lines.size() > 1 else 0)
	_wb_refresh()
	# A visible pulse on every new line — the meeting is clearly alive.
	_wb_panel.modulate = Color(1.5, 1.4, 1.7)
	var tw := create_tween()
	tw.tween_property(_wb_panel, "modulate", Color.WHITE, 0.5)

func _wb_refresh() -> void:
	for c in _wb_box.get_children():
		c.queue_free()
	_wb_panel.visible = _wb_lines.size() > 0
	for i in _wb_lines.size():
		var last := i == _wb_lines.size() - 1 and i > 0
		var l := Label.new()
		# Older lines stay compact; the LATEST speaks in full, word-wrapped.
		l.text = _wb_lines[i] if (last or i == 0) else _wb_lines[i].left(52)
		if last:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(260, 0)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_size_override("font_size", 13 if (i == 0 or last) else 11)
		l.add_theme_color_override("font_color",
			Color(0.85, 0.7, 1.0) if i == 0
			else (Color(1.0, 1.0, 1.0) if last else Color(0.7, 0.73, 0.82)))
		_wb_box.add_child(l)

# ---------------------------------------------------------------- theater

func _build_theater_banner() -> void:
	_theater_banner = Label.new()
	_theater_banner.text = "⏪  R E P L A Y   T H E A T E R"
	_theater_banner.add_theme_font_size_override("font_size", 26)
	_theater_banner.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
	_theater_banner.add_theme_constant_override("outline_size", 8)
	_theater_banner.add_theme_color_override("font_outline_color", Color(0.1, 0.02, 0.02, 0.9))
	_theater_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_theater_banner.position.y = 18
	_theater_banner.visible = false
	_theater_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_theater_banner)

func set_theater(on: bool) -> void:
	_theater_banner.visible = on

# ---------------------------------------------------------------- tracking

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var dead: Array = []
	for agent in _plates:
		if not is_instance_valid(agent):
			dead.append(agent)
			continue
		var p: Dictionary = _plates[agent]
		var wp: Vector3 = agent.global_position + Vector3(0, 1.0, 0)
		if cam.is_position_behind(wp):
			p.root.visible = false
			continue
		p.root.visible = true
		var sp := cam.unproject_position(wp)
		# Perspective-consistent size: scale by camera distance so a plate is
		# never bigger than its far-away character or tiny on a near one.
		var dist := cam.global_position.distance_to(wp)
		var s: float = clampf(44.0 / dist, 0.62, 1.2)
		p.root.scale = Vector2(s, s)
		# Anchor the BOTTOM-CENTER of the (scaled) plate to the head point.
		p.root.position = sp - Vector2(p.root.size.x * 0.5 * s, p.root.size.y * s)
	for agent in dead:
		_plates[agent].root.queue_free()
		_plates.erase(agent)

	_track_fx(_delta, cam)

	if _wb_panel.visible:
		var sp2 := cam.unproject_position(Vector3(13, 2.4, -0.5))
		_wb_panel.position = sp2 - Vector2(_wb_panel.size.x * 0.5, _wb_panel.size.y)
	if _theater_banner.visible:
		_theater_banner.position.x = get_viewport().get_visible_rect().size.x * 0.5 \
			- _theater_banner.size.x * 0.5
