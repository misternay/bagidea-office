extends CanvasLayer
## 2D GUI layer: crisp screen-space text replacing unreadable in-world labels.
## - MMO-style nameplates that track characters: portrait + name + role +
##   live status, with a state accent border.
## - Meeting-minutes panel pinned over the meeting room.
## - Replay Theater marquee banner.

var _plates := {}  # agent Node3D -> {root, sub, role, accent}
var _wb_panel: PanelContainer
var _wb_box: VBoxContainer
var _wb_lines: Array[String] = []
var _theater_banner: Label

func _ready() -> void:
	layer = 2
	_build_whiteboard()
	_build_theater_banner()

# ---------------------------------------------------------------- nameplates

func register(agent: Node3D, display_name: String, role: String,
		portrait: Texture2D, accent: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.06, 0.11, 0.82)
	style.set_corner_radius_all(8)
	style.set_border_width_all(1)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.85)
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

	var nm := Label.new()
	nm.text = display_name
	nm.add_theme_font_size_override("font_size", 13)
	nm.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(nm)

	var sub := Label.new()
	sub.text = role
	sub.add_theme_font_size_override("font_size", 10)
	sub.add_theme_color_override("font_color", Color(0.62, 0.68, 0.78))
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(sub)

	add_child(root)
	_plates[agent] = {"root": root, "sub": sub, "role": role}

func set_status(agent: Node3D, text: String) -> void:
	if not _plates.has(agent):
		return
	var p: Dictionary = _plates[agent]
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

func unregister(agent: Node3D) -> void:
	if _plates.has(agent):
		_plates[agent].root.queue_free()
		_plates.erase(agent)

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
	_wb_lines.append(line.left(52))
	while _wb_lines.size() > 7:
		# keep the header, trim the oldest body line
		_wb_lines.remove_at(1 if _wb_lines.size() > 1 else 0)
	_wb_refresh()

func _wb_refresh() -> void:
	for c in _wb_box.get_children():
		c.queue_free()
	_wb_panel.visible = _wb_lines.size() > 0
	for i in _wb_lines.size():
		var l := Label.new()
		l.text = _wb_lines[i]
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_size_override("font_size", 13 if i == 0 else 12)
		l.add_theme_color_override("font_color",
			Color(0.85, 0.7, 1.0) if i == 0 else Color(0.88, 0.9, 0.97))
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
		p.root.position = sp - Vector2(p.root.size.x * 0.5, p.root.size.y)
	for agent in dead:
		_plates[agent].root.queue_free()
		_plates.erase(agent)

	if _wb_panel.visible:
		var sp2 := cam.unproject_position(Vector3(13, 2.4, -0.5))
		_wb_panel.position = sp2 - Vector2(_wb_panel.size.x * 0.5, _wb_panel.size.y)
	if _theater_banner.visible:
		_theater_banner.position.x = get_viewport().get_visible_rect().size.x * 0.5 \
			- _theater_banner.size.x * 0.5
