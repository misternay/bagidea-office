extends Node3D
## 🎨 3D Office Editor — a real in-world editor launched in its OWN window
## (office_floor with --editor3d). The procedural rooms/walls + Ghost Deck are
## LOCKED context; you place / move / rotate / scale DECOR and import .glb
## models (with animation) or images, then save. Saving writes the shared
## layout.json so the live wallpaper renders the same arrangement; "Save as
## preset" keeps it as a reusable custom preset.
##
## Picking is real 3D (a box collider per item + camera raycast) — click the
## object itself to select, drag the floor handle to move. Panels: SCENE
## (everything placed) and LIBRARY (imported models/images, reusable).

const LAYOUT_URL := "http://127.0.0.1:8787/layout"
const PRESETS_URL := "http://127.0.0.1:8787/presets"
const ASSETS_URL := "http://127.0.0.1:8787/assets"

var rig: Node3D
var cam: Camera3D
var _root: Node3D
var items: Array = []             # [{dict, node, body}]
var sel: int = -1
var play_anim := true
var _hi: MeshInstance3D            # selection highlight ring

# camera: real framing + game-style controls (LMB pan, RMB orbit, wheel zoom)
const BASE_TARGET := Vector3(2.5, 0.2, 0.8)
const BASE_YAW := -12.0
const BASE_PITCH := -45.0
var target := BASE_TARGET
var yaw := BASE_YAW
const YAW_LIMIT := 32.0
var dist := 58.0
const DIST_MIN := 30.0
const DIST_MAX := 64.0
var _orbit := false               # RMB/MMB held → rotate
var _lmb := false                 # LMB held
var _drag_item := false           # LMB drag is moving the selected item
var _panning := false             # LMB drag is panning the camera
var _press_pos := Vector2.ZERO
var _moved := false
var _pan_anchor := Vector3.ZERO   # world point grabbed under the cursor

var _req: HTTPRequest
var _save_req: HTTPRequest
var _preset_req: HTTPRequest
var _assets_req: HTTPRequest
var ui: Control
var custom_presets: Array = []
var library: Array = []           # [{path, kind, name}]

const TYPES := [
	["desk", "🪑 Desk"], ["table", "🍽 Table"], ["chair", "💺 Chair"],
	["shelf", "📚 Shelf"], ["plant", "🪴 Plant"], ["lamp", "💡 Lamp"],
	["rug", "🟫 Rug"], ["sofa", "🛋 Sofa"], ["tv", "📺 TV"],
	["whiteboard", "📋 Board"], ["cabinet", "🗄 Cabinet"], ["cooler", "🚰 Cooler"],
]

const PRESETS := [
	{ "name": "Classic grid", "items": [
		{ "type": "desk", "x": -7, "z": -7 }, { "type": "chair", "x": -7, "z": -6, "rot": 180 },
		{ "type": "desk", "x": -4, "z": -7 }, { "type": "chair", "x": -4, "z": -6, "rot": 180 },
		{ "type": "desk", "x": -7, "z": -3 }, { "type": "chair", "x": -7, "z": -2, "rot": 180 },
		{ "type": "desk", "x": -4, "z": -3 }, { "type": "chair", "x": -4, "z": -2, "rot": 180 },
		{ "type": "plant", "x": -9.5, "z": -8.5 }, { "type": "cooler", "x": -1.5, "z": -8 } ] },
	{ "name": "Open plan", "items": [
		{ "type": "table", "x": -5, "z": -5, "scale": 1.4 }, { "type": "chair", "x": -6, "z": -5, "rot": 90 },
		{ "type": "chair", "x": -4, "z": -5, "rot": 270 }, { "type": "rug", "x": -5, "z": -5, "scale": 1.6, "color": "33405a" },
		{ "type": "whiteboard", "x": -8.5, "z": -7 }, { "type": "plant", "x": -8, "z": -2 } ] },
	{ "name": "Cozy lounge", "items": [
		{ "type": "rug", "x": 2, "z": 4, "scale": 1.8, "color": "7a3b4b" }, { "type": "sofa", "x": 2, "z": 5 },
		{ "type": "table", "x": 2, "z": 4, "scale": 0.8 }, { "type": "tv", "x": 2, "z": 2, "rot": 180 },
		{ "type": "plant", "x": -0.5, "z": 2.5 }, { "type": "lamp", "x": 4.5, "z": 5, "color": "ffcf9a" } ] },
	{ "name": "Focus pods", "items": [
		{ "type": "desk", "x": 8, "z": -7 }, { "type": "chair", "x": 8, "z": -6, "rot": 180 }, { "type": "shelf", "x": 9.4, "z": -7, "rot": 90 },
		{ "type": "desk", "x": 8, "z": -3 }, { "type": "chair", "x": 8, "z": -2, "rot": 180 }, { "type": "cabinet", "x": 9.4, "z": -3, "rot": 90 },
		{ "type": "lamp", "x": 10, "z": -5, "color": "cfe0ff" } ] },
	{ "name": "Minimal green", "items": [
		{ "type": "desk", "x": 0, "z": 0 }, { "type": "chair", "x": 0, "z": 1, "rot": 180 },
		{ "type": "plant", "x": -2, "z": -1 }, { "type": "plant", "x": 2, "z": -1 },
		{ "type": "plant", "x": -2, "z": 2 }, { "type": "rug", "x": 0, "z": 0.5, "scale": 1.3, "color": "2f5a3a" } ] },
]

func setup(camera_rig: Node3D, camera: Camera3D) -> void:
	rig = camera_rig
	cam = camera

func _ready() -> void:
	_root = Node3D.new(); _root.name = "EditorLayout"; add_child(_root)
	_req = HTTPRequest.new(); add_child(_req); _req.request_completed.connect(_on_layout)
	_save_req = HTTPRequest.new(); add_child(_save_req)
	_preset_req = HTTPRequest.new(); add_child(_preset_req); _preset_req.request_completed.connect(_on_preset)
	_assets_req = HTTPRequest.new(); add_child(_assets_req); _assets_req.request_completed.connect(_on_assets)
	_make_highlight()
	_build_ui()
	_update_cam()
	_req.request(LAYOUT_URL)
	_preset_req.request(PRESETS_URL)
	_assets_req.request(ASSETS_URL)

# ---------------------------------------------------------------- camera
func _update_cam() -> void:
	if rig == null or cam == null:
		return
	rig.position = target
	rig.rotation_degrees = Vector3(BASE_PITCH, yaw, 0.0)
	cam.position = Vector3(0.0, 0.0, dist)

# True while the cursor is over an editor panel — gate camera input so
# scrolling a menu doesn't also zoom the world (and pans don't start on UI).
func _over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _over_ui(): return
			dist = clampf(dist - 2.5, DIST_MIN, DIST_MAX); _update_cam()
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _over_ui(): return
			dist = clampf(dist + 2.5, DIST_MIN, DIST_MAX); _update_cam()
		elif e.button_index == MOUSE_BUTTON_RIGHT or e.button_index == MOUSE_BUTTON_MIDDLE:
			_orbit = e.pressed and not _over_ui()
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				if _over_ui(): return
				_lmb = true; _moved = false; _press_pos = e.position
				_begin_left(e.position)
			else:
				# a click with no drag on empty space → unselect
				if _lmb and not _moved and not _drag_item:
					sel = -1; _place_highlight(); _refresh_sel()
				_lmb = false; _drag_item = false; _panning = false
	elif e is InputEventMouseMotion:
		if _orbit:
			yaw = clampf(yaw - e.relative.x * 0.08, BASE_YAW - YAW_LIMIT, BASE_YAW + YAW_LIMIT)
			_update_cam()
		elif _lmb:
			if e.relative.length() > 0.5: _moved = true
			if _drag_item and sel >= 0:
				var hit := _floor_hit(e.position)
				if hit != Vector3.INF:
					items[sel]["dict"]["x"] = snappedf(hit.x, 0.1)
					items[sel]["dict"]["z"] = snappedf(hit.z, 0.1)
					items[sel]["node"].position.x = items[sel]["dict"]["x"]
					items[sel]["node"].position.z = items[sel]["dict"]["z"]
					_place_highlight()
			elif _panning:
				# grab-pan: keep the world point you grabbed under the cursor —
				# rock solid at any yaw/zoom (no swing).
				var cur := _floor_hit(e.position)
				if cur != Vector3.INF and _pan_anchor != Vector3.INF:
					target += _pan_anchor - cur
					target.x = clampf(target.x, -14.0, 20.0)
					target.z = clampf(target.z, -14.0, 18.0)
					_update_cam()

# LMB pressed on the world: grab the clicked item (→ drag-move) or, on empty,
# start a camera pan. Selection of a different item happens here too.
func _begin_left(screen: Vector2) -> void:
	var space := get_world_3d().direct_space_state
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	var q := PhysicsRayQueryParameters3D.create(o, o + d * 500.0)
	q.collide_with_areas = true
	q.collide_with_bodies = true
	var r := space.intersect_ray(q)
	if r and r.has("collider"):
		var node: Node = r["collider"]
		while node and not node.has_meta("item_rig"):
			node = node.get_parent()
		if node:
			for i in items.size():
				if items[i]["node"] == node:
					sel = i; _drag_item = true; _place_highlight(); _refresh_sel(); _refresh_scene(); return
	# empty space → pan the camera (and unselect on a clean click)
	_panning = true
	_pan_anchor = _floor_hit(screen)

func _floor_hit(screen: Vector2) -> Vector3:
	if cam == null: return Vector3.INF
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	if absf(d.y) < 0.0001: return Vector3.INF
	var tt := -o.y / d.y
	if tt < 0: return Vector3.INF
	return o + d * tt

# Add an item from the palette / library: it appears at the camera focus,
# gets selected, ready to drag into place. (Placement is via buttons now —
# clicking empty space only unselects.)
func _add_at_focus(type: String, asset := "") -> void:
	var it := { "type": type, "x": snappedf(target.x, 0.1), "z": snappedf(target.z, 0.1), "rot": 0.0, "scale": 1.0 }
	if asset != "": it["asset"] = asset
	_add_item(it); sel = items.size() - 1
	_place_highlight(); _refresh_sel(); _refresh_scene()
	_flash("เพิ่มแล้ว — ลากเพื่อจัดวาง")

# ---------------------------------------------------------------- highlight
func _make_highlight() -> void:
	# a bright disc + ring on the floor + a soft pillar of light so the
	# selected object is unmistakable from any angle.
	_hi = MeshInstance3D.new()
	var tm := TorusMesh.new(); tm.inner_radius = 0.95; tm.outer_radius = 1.25
	_hi.mesh = tm
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.45, 0.9, 1.0)
	m.emission_enabled = true; m.emission = Color(0.45, 0.9, 1.0); m.emission_energy_multiplier = 4.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.albedo_color.a = 0.9
	_hi.material_override = m
	_hi.visible = false
	add_child(_hi)
	# pillar
	var pil := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = 0.9; cm.bottom_radius = 0.9; cm.height = 3.0
	pil.mesh = cm; pil.position.y = 1.5; pil.name = "Pillar"
	var pm := StandardMaterial3D.new(); pm.albedo_color = Color(0.45, 0.9, 1.0, 0.12)
	pm.emission_enabled = true; pm.emission = Color(0.45, 0.9, 1.0); pm.emission_energy_multiplier = 1.0
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	pil.material_override = pm
	_hi.add_child(pil)

func _process(_dt: float) -> void:
	if _hi and _hi.visible:
		_hi.rotation_degrees.y += _dt * 40.0   # gentle spin so it reads as "selected"

func _place_highlight() -> void:
	if sel < 0 or sel >= items.size():
		_hi.visible = false; return
	var it: Dictionary = items[sel]["dict"]
	_hi.visible = true
	_hi.position = Vector3(float(it.get("x", 0)), 0.06, float(it.get("z", 0)))
	var s := float(it.get("scale", 1.0))
	_hi.scale = Vector3(s, s, s)

# ---------------------------------------------------------------- items
func _on_layout(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200: return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if data is Dictionary and data.get("items") is Array:
		for it in data["items"]:
			if it is Dictionary: _add_item(it.duplicate(true))
	_refresh_scene()

func _add_item(it: Dictionary) -> void:
	var node := _spawn(it)
	_root.add_child(node)
	items.append({ "dict": it, "node": node })

func _mat(hex: String, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex) if hex != "" else Color(0.7, 0.72, 0.78)
	m.roughness = rough
	return m

func _box(w: float, h: float, d: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(w, h, d)
	mi.mesh = bm; mi.material_override = mat
	return mi

func _spawn(it: Dictionary) -> Node3D:
	var rig2 := Node3D.new()
	rig2.set_meta("item_rig", true)
	rig2.position = Vector3(float(it.get("x", 0)), float(it.get("y", 0)), float(it.get("z", 0)))
	rig2.rotation_degrees = Vector3(0, float(it.get("rot", 0)), 0)
	var s := float(it.get("scale", 1.0)); rig2.scale = Vector3(s, s, s)
	var col := String(it.get("color", ""))
	var foot := Vector3(1.0, 1.0, 1.0)   # collider footprint
	match String(it.get("type", "desk")):
		"desk":
			var top := _box(1.4, 0.08, 0.8, _mat(col if col != "" else "3a2e25", 0.5)); top.position.y = 0.74; rig2.add_child(top)
			for sx in [-0.6, 0.6]:
				for sz in [-0.32, 0.32]:
					var leg := _box(0.08, 0.74, 0.08, _mat("222831")); leg.position = Vector3(sx, 0.37, sz); rig2.add_child(leg)
			foot = Vector3(1.4, 0.9, 0.8)
		"table":
			var t := _box(1.1, 0.08, 1.1, _mat(col if col != "" else "4a3b2c", 0.5)); t.position.y = 0.7; rig2.add_child(t)
			var post := _box(0.12, 0.7, 0.12, _mat("2a2a2a")); post.position.y = 0.35; rig2.add_child(post); foot = Vector3(1.1, 0.8, 1.1)
		"chair":
			var seat := _box(0.45, 0.07, 0.45, _mat(col if col != "" else "5a6b8c", 0.6)); seat.position.y = 0.45; rig2.add_child(seat)
			var back := _box(0.45, 0.5, 0.07, _mat(col if col != "" else "5a6b8c", 0.6)); back.position = Vector3(0, 0.7, -0.19); rig2.add_child(back); foot = Vector3(0.5, 1.0, 0.5)
		"shelf":
			var bd := _box(0.9, 1.6, 0.32, _mat(col if col != "" else "4a3a2a", 0.7)); bd.position.y = 0.8; rig2.add_child(bd); foot = Vector3(0.9, 1.6, 0.4)
		"plant":
			var pot := _box(0.3, 0.3, 0.3, _mat("8a5a3a")); pot.position.y = 0.15; rig2.add_child(pot)
			var lv := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 0.32; sm.height = 0.7
			lv.mesh = sm; lv.material_override = _mat(col if col != "" else "3c7a3c", 0.9); lv.position.y = 0.6; rig2.add_child(lv); foot = Vector3(0.5, 1.0, 0.5)
		"lamp":
			var st := _box(0.06, 1.3, 0.06, _mat("333")); st.position.y = 0.65; rig2.add_child(st)
			var light := OmniLight3D.new(); light.position.y = 1.35; light.light_energy = 2.0; light.omni_range = 5.0
			light.light_color = Color(col) if col != "" else Color(1, 0.9, 0.7); rig2.add_child(light); foot = Vector3(0.4, 1.4, 0.4)
		"rug":
			var rg := _box(2.0, 0.02, 1.5, _mat(col if col != "" else "7a3b4b", 0.95)); rg.position.y = 0.02; rig2.add_child(rg); foot = Vector3(2.0, 0.2, 1.5)
		"sofa":
			var base := _box(1.6, 0.4, 0.7, _mat(col if col != "" else "44506b", 0.7)); base.position.y = 0.25; rig2.add_child(base)
			var bk := _box(1.6, 0.5, 0.18, _mat(col if col != "" else "44506b", 0.7)); bk.position = Vector3(0, 0.6, -0.26); rig2.add_child(bk); foot = Vector3(1.6, 0.9, 0.8)
		"tv":
			var screen := _box(1.5, 0.85, 0.08, _mat("0a0a0c", 0.3)); screen.position.y = 1.1; rig2.add_child(screen)
			var stnd := _box(0.1, 1.0, 0.1, _mat("222")); stnd.position.y = 0.5; rig2.add_child(stnd); foot = Vector3(1.5, 1.6, 0.4)
		"whiteboard":
			var wb := _box(1.6, 1.0, 0.06, _mat("f0f2f5", 0.4)); wb.position.y = 1.2; rig2.add_child(wb)
			var fr := _box(0.06, 1.2, 0.06, _mat("888")); fr.position = Vector3(-0.8, 0.6, 0); rig2.add_child(fr)
			var fr2 := _box(0.06, 1.2, 0.06, _mat("888")); fr2.position = Vector3(0.8, 0.6, 0); rig2.add_child(fr2); foot = Vector3(1.6, 1.8, 0.3)
		"cabinet":
			var cb := _box(0.9, 1.1, 0.5, _mat(col if col != "" else "6b7280", 0.6)); cb.position.y = 0.55; rig2.add_child(cb); foot = Vector3(0.9, 1.1, 0.5)
		"cooler":
			var bdy := _box(0.4, 1.1, 0.4, _mat("dfe7ef", 0.4)); bdy.position.y = 0.55; rig2.add_child(bdy)
			var jug := _box(0.32, 0.4, 0.32, _mat("7ec8ff", 0.2)); jug.position.y = 1.25; rig2.add_child(jug); foot = Vector3(0.45, 1.5, 0.45)
		"poster":
			_spawn_poster(rig2, String(it.get("asset", ""))); foot = Vector3(1.3, 0.9, 0.2)
		"model":
			_spawn_model(rig2, String(it.get("asset", ""))); foot = Vector3(1.4, 1.4, 1.4)
		_:
			var dd := _box(0.6, 0.6, 0.6, _mat(col)); dd.position.y = 0.3; rig2.add_child(dd)
	# pick collider (invisible) sized to the item
	var sb := StaticBody3D.new(); sb.collision_layer = 1; sb.collision_mask = 0
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = foot
	cs.shape = bs; cs.position.y = foot.y * 0.5
	sb.add_child(cs); rig2.add_child(sb)
	return rig2

func _spawn_poster(rig2: Node3D, asset: String) -> void:
	if asset == "": return
	var img := Image.new()
	if img.load(asset) != OK: return
	var mi := MeshInstance3D.new(); var qm := QuadMesh.new(); qm.size = Vector2(1.2, 0.8); mi.mesh = qm
	var m := StandardMaterial3D.new(); m.albedo_texture = ImageTexture.create_from_image(img)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m; mi.position.y = 1.4; rig2.add_child(mi)

func _spawn_model(rig2: Node3D, asset: String) -> void:
	if asset == "": return
	var ext := asset.get_extension().to_lower()
	var scene: Node = null
	if ext == "glb" or ext == "gltf":
		var doc := GLTFDocument.new(); var stt := GLTFState.new()
		if doc.append_from_file(asset, stt) == OK: scene = doc.generate_scene(stt)
	elif ext == "fbx":
		var doc := FBXDocument.new(); var stt := GLTFState.new()
		if doc.append_from_file(asset, stt) == OK: scene = doc.generate_scene(stt)
	if scene:
		rig2.add_child(scene)
		if play_anim:
			var ap := scene.find_child("AnimationPlayer", true, false)
			if ap and ap is AnimationPlayer and (ap as AnimationPlayer).get_animation_list().size() > 0:
				(ap as AnimationPlayer).play((ap as AnimationPlayer).get_animation_list()[0])

# ---------------------------------------------------------------- UI
# A brand-dark theme so the editor doesn't look like raw Godot greybox.
func _build_theme() -> Theme:
	var th := Theme.new()
	var accent := Color(0.37, 0.78, 1.0)
	var ink := Color(0.88, 0.93, 1.0)
	# panels: dark glass, rounded
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.04, 0.07, 0.12, 0.94)
	panel.set_corner_radius_all(14)
	panel.set_border_width_all(1); panel.border_color = Color(1, 1, 1, 0.10)
	panel.set_content_margin_all(12)
	panel.shadow_color = Color(0, 0, 0, 0.5); panel.shadow_size = 16
	th.set_stylebox("panel", "PanelContainer", panel)
	# buttons
	var mk := func(bg: Color, bord: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new(); s.bg_color = bg; s.set_corner_radius_all(9)
		s.set_border_width_all(1); s.border_color = bord
		s.content_margin_top = 7; s.content_margin_bottom = 7
		s.content_margin_left = 11; s.content_margin_right = 11
		return s
	th.set_stylebox("normal", "Button", mk.call(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.10)))
	th.set_stylebox("hover", "Button", mk.call(Color(0.37, 0.78, 1.0, 0.16), accent))
	th.set_stylebox("pressed", "Button", mk.call(Color(0.37, 0.78, 1.0, 0.28), accent))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", ink)
	th.set_color("font_hover_color", "Button", Color(1, 1, 1))
	th.set_font_size("font_size", "Button", 13)
	th.set_color("font_color", "Label", ink)
	# option button mirrors Button
	th.set_stylebox("normal", "OptionButton", mk.call(Color(1, 1, 1, 0.05), accent))
	th.set_stylebox("hover", "OptionButton", mk.call(Color(0.37, 0.78, 1.0, 0.16), accent))
	th.set_stylebox("pressed", "OptionButton", mk.call(Color(0.37, 0.78, 1.0, 0.2), accent))
	th.set_color("font_color", "OptionButton", ink)
	# sliders
	var track := StyleBoxFlat.new(); track.bg_color = Color(1, 1, 1, 0.08); track.set_corner_radius_all(4); track.content_margin_top = 3; track.content_margin_bottom = 3
	var fill := StyleBoxFlat.new(); fill.bg_color = accent; fill.set_corner_radius_all(4); fill.content_margin_top = 3; fill.content_margin_bottom = 3
	th.set_stylebox("slider", "HSlider", track)
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill)
	# scroll + line edit
	var le := StyleBoxFlat.new(); le.bg_color = Color(0, 0, 0, 0.3); le.set_corner_radius_all(8); le.set_content_margin_all(8); le.set_border_width_all(1); le.border_color = Color(1, 1, 1, 0.12)
	th.set_stylebox("normal", "LineEdit", le)
	th.set_color("font_color", "LineEdit", ink)
	return th

func _build_ui() -> void:
	ui = Control.new(); ui.set_anchors_preset(Control.PRESET_FULL_RECT); ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = _build_theme()
	var layer := CanvasLayer.new(); layer.add_child(ui); add_child(layer)

	# ── TOP TOOLBAR — layout / file actions, separate from the object palette
	var bar := PanelContainer.new(); bar.position = Vector2(12, 10)
	var bh := HBoxContainer.new(); bh.add_theme_constant_override("separation", 8); bar.add_child(bh)
	var bt := Label.new(); bt.text = "🎨 EDITOR"; bh.add_child(bt)
	var sep := VSeparator.new(); bh.add_child(sep)
	var plab := Label.new(); plab.text = "Layout:"; plab.add_theme_font_size_override("font_size", 11); bh.add_child(plab)
	var pbtn := OptionButton.new(); pbtn.name = "PresetPick"; pbtn.add_item("เลือก layout…")
	for pr in PRESETS: pbtn.add_item("⭐ " + pr["name"])
	pbtn.item_selected.connect(_on_preset_picked); bh.add_child(pbtn)
	var imp := Button.new(); imp.text = "📦 .glb"; imp.pressed.connect(_import_model); bh.add_child(imp)
	var pst := Button.new(); pst.text = "🖼 image"; pst.pressed.connect(_import_image); bh.add_child(pst)
	var save := Button.new(); save.text = "💾 บันทึก"; save.pressed.connect(_save); bh.add_child(save)
	var savep := Button.new(); savep.text = "⭐ เป็น preset"; savep.pressed.connect(_save_as_preset); bh.add_child(savep)
	ui.add_child(bar)

	# ── LEFT — object palette only (categorised: system vs decor)
	var panel := PanelContainer.new(); panel.position = Vector2(12, 64); panel.custom_minimum_size = Vector2(196, 0)
	var sc := ScrollContainer.new(); sc.custom_minimum_size = Vector2(190, 470); panel.add_child(sc)
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 4); vb.custom_minimum_size = Vector2(178, 0); sc.add_child(vb)
	var title := Label.new(); title.text = "＋ เพิ่มวัตถุ"; vb.add_child(title)
	var hint := Label.new(); hint.text = "ซ้ายลาก=เลื่อนกล้อง · คลิกวัตถุ=เลือก · ลาก=ย้าย · ขวา=หมุน"
	hint.add_theme_font_size_override("font_size", 9); hint.autowrap_mode = TextServer.AUTOWRAP_WORD; vb.add_child(hint)
	var catlab := Label.new(); catlab.text = "🟢 ของตกแต่ง"; catlab.add_theme_font_size_override("font_size", 10); vb.add_child(catlab)
	for t in TYPES:
		var b := Button.new(); b.text = "＋ " + t[1]; b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var ty: String = t[0]
		b.pressed.connect(func(): _add_at_focus(ty))
		vb.add_child(b)
	var ac := CheckButton.new(); ac.text = "เล่น animation โมเดล"; ac.button_pressed = true
	ac.add_theme_font_size_override("font_size", 10)
	ac.toggled.connect(func(on): play_anim = on); vb.add_child(ac)
	ui.add_child(panel)

	# right top: selected item
	var sp := PanelContainer.new(); sp.name = "SelPanel"; sp.anchor_left = 1.0; sp.anchor_right = 1.0
	sp.position = Vector2(-232, 12); sp.custom_minimum_size = Vector2(218, 0)
	var sv := VBoxContainer.new(); sv.name = "SelBox"; sv.add_theme_constant_override("separation", 5); sp.add_child(sv)
	ui.add_child(sp); sp.visible = false

	# right bottom: SCENE list
	var scp := PanelContainer.new(); scp.anchor_left = 1.0; scp.anchor_right = 1.0; scp.anchor_top = 1.0; scp.anchor_bottom = 1.0
	scp.position = Vector2(-232, -250); scp.custom_minimum_size = Vector2(218, 230)
	var scvb := VBoxContainer.new(); scp.add_child(scvb)
	var scl := Label.new(); scl.text = "🗂 SCENE — วัตถุที่วาง"; scvb.add_child(scl)
	var ssc := ScrollContainer.new(); ssc.custom_minimum_size = Vector2(210, 190); scvb.add_child(ssc)
	var slist := VBoxContainer.new(); slist.name = "SceneList"; slist.custom_minimum_size = Vector2(200, 0); ssc.add_child(slist)
	ui.add_child(scp)

	# left bottom: LIBRARY (imported assets)
	var lp := PanelContainer.new(); lp.anchor_top = 1.0; lp.anchor_bottom = 1.0
	lp.position = Vector2(12, -210); lp.custom_minimum_size = Vector2(210, 190)
	var lvb := VBoxContainer.new(); lp.add_child(lvb)
	var ll := Label.new(); ll.text = "🗃 LIBRARY — โมเดล/รูปที่ import"; ll.add_theme_font_size_override("font_size", 11); lvb.add_child(ll)
	var lsc := ScrollContainer.new(); lsc.custom_minimum_size = Vector2(202, 150); lvb.add_child(lsc)
	var llist := VBoxContainer.new(); llist.name = "LibList"; llist.custom_minimum_size = Vector2(192, 0); lsc.add_child(llist)
	ui.add_child(lp)

	var toast := Label.new(); toast.name = "Toast"; toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	toast.position = Vector2(-120, -40); ui.add_child(toast)

func _flash(msg: String) -> void:
	var toast := ui.find_child("Toast", true, false)
	if toast and toast is Label: (toast as Label).text = msg

func _refresh_sel() -> void:
	var sp := ui.find_child("SelPanel", true, false)
	var sv := ui.find_child("SelBox", true, false)
	if sp == null or sv == null: return
	for c in sv.get_children(): c.queue_free()
	if sel < 0 or sel >= items.size():
		sp.visible = false; return
	sp.visible = true
	var it: Dictionary = items[sel]["dict"]
	var lbl := Label.new(); lbl.text = "⚙ " + String(it.get("type", "")); sv.add_child(lbl)
	# stepper rows (sliders were invisible on the dark theme) — clear value + buttons
	var apply_rot := func(v): it["rot"] = wrapf(v, 0.0, 360.0); items[sel]["node"].rotation_degrees.y = it["rot"]; _refresh_sel()
	sv.add_child(_stepper("หมุน", "%d°" % int(it.get("rot", 0)),
		func(): apply_rot.call(float(it.get("rot", 0)) - 15.0),
		func(): apply_rot.call(float(it.get("rot", 0)) + 15.0)))
	var apply_scl := func(v): it["scale"] = clampf(v, 0.3, 4.0); items[sel]["node"].scale = Vector3(it["scale"], it["scale"], it["scale"]); _place_highlight(); _refresh_sel()
	sv.add_child(_stepper("ขนาด", "%.1f" % float(it.get("scale", 1.0)),
		func(): apply_scl.call(float(it.get("scale", 1.0)) - 0.1),
		func(): apply_scl.call(float(it.get("scale", 1.0)) + 0.1)))
	var del := Button.new(); del.text = "🗑 ลบวัตถุนี้"
	del.pressed.connect(func():
		items[sel]["node"].queue_free(); items.remove_at(sel); sel = -1
		_place_highlight(); _refresh_sel(); _refresh_scene()); sv.add_child(del)

func _stepper(label: String, value: String, on_minus: Callable, on_plus: Callable) -> HBoxContainer:
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 4)
	var l := Label.new(); l.text = label; l.custom_minimum_size = Vector2(48, 0); row.add_child(l)
	var minus := Button.new(); minus.text = "−"; minus.custom_minimum_size = Vector2(34, 0)
	minus.pressed.connect(on_minus); row.add_child(minus)
	var v := Label.new(); v.text = value; v.custom_minimum_size = Vector2(50, 0); v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; row.add_child(v)
	var plus := Button.new(); plus.text = "＋"; plus.custom_minimum_size = Vector2(34, 0)
	plus.pressed.connect(on_plus); row.add_child(plus)
	return row

func _refresh_scene() -> void:
	var box := ui.find_child("SceneList", true, false)
	if box == null: return
	for c in box.get_children(): c.queue_free()
	for i in items.size():
		var b := Button.new(); b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%d. %s" % [i + 1, String(items[i]["dict"].get("type", ""))]
		b.add_theme_font_size_override("font_size", 11)
		var idx := i
		b.pressed.connect(func(): sel = idx; _place_highlight(); _refresh_sel())
		box.add_child(b)

func _refresh_lib() -> void:
	var box := ui.find_child("LibList", true, false)
	if box == null: return
	for c in box.get_children(): c.queue_free()
	if library.is_empty():
		var e := Label.new(); e.text = "(ว่าง — กด Import)"; e.add_theme_font_size_override("font_size", 10); box.add_child(e); return
	for a in library:
		var row := HBoxContainer.new()
		var b := Button.new(); b.alignment = HORIZONTAL_ALIGNMENT_LEFT; b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var icon := "📦 " if a.get("kind") == "model" else "🖼 "
		b.text = icon + String(a.get("name", "")); b.add_theme_font_size_override("font_size", 10)
		var ap := String(a.get("path", "")); var ak := String(a.get("kind", "model"))
		b.pressed.connect(func(): _add_at_focus("model" if ak == "model" else "poster", ap))
		row.add_child(b)
		var x := Button.new(); x.text = "✕"; x.add_theme_font_size_override("font_size", 10)
		x.pressed.connect(func():
			_assets_req.request(ASSETS_URL, ["content-type: application/json"], HTTPClient.METHOD_POST, JSON.stringify({ "remove": ap }))
			library = library.filter(func(z): return z.get("path") != ap); _refresh_lib())
		row.add_child(x)
		box.add_child(row)

# ---------------------------------------------------------------- presets / assets
func _on_preset_picked(idx: int) -> void:
	if idx <= 0: return
	var list := PRESETS + custom_presets
	if idx - 1 < list.size(): _load_preset(list[idx - 1])

func _load_preset(pr: Dictionary) -> void:
	for c in _root.get_children(): c.queue_free()
	items.clear(); sel = -1; _place_highlight()
	for it in pr.get("items", []):
		if it is Dictionary: _add_item(it.duplicate(true))
	_refresh_sel(); _refresh_scene()
	_flash("⭐ โหลด: " + String(pr.get("name", "")))

func _current_items() -> Array:
	var out: Array = []
	for e in items: out.append(e["dict"])
	return out

func _save() -> void:
	_save_req.request(LAYOUT_URL, ["content-type: application/json"], HTTPClient.METHOD_POST, JSON.stringify({ "items": _current_items() }))
	_flash("💾 บันทึกแล้ว — วอลเปเปอร์อัปเดต")

func _save_as_preset() -> void:
	var dlg := AcceptDialog.new(); dlg.title = "บันทึกเป็น preset"
	var le := LineEdit.new(); le.placeholder_text = "ชื่อ preset"; le.custom_minimum_size = Vector2(260, 0)
	dlg.add_child(le); dlg.register_text_enter(le); add_child(dlg)
	dlg.confirmed.connect(func():
		var nm := le.text.strip_edges()
		if nm != "":
			_save_req.request(PRESETS_URL, ["content-type: application/json"], HTTPClient.METHOD_POST, JSON.stringify({ "name": nm, "items": _current_items() }))
			_flash("⭐ บันทึก preset: " + nm)
			_preset_req.request(PRESETS_URL)
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.popup_centered(Vector2i(320, 130)); le.grab_focus()

func _on_preset(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200: return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if data is Dictionary and data.get("presets") is Array:
		custom_presets = data["presets"]
		var pick := ui.find_child("PresetPick", true, false)
		if pick and pick is OptionButton:
			var ob := pick as OptionButton
			while ob.item_count > 1 + PRESETS.size(): ob.remove_item(ob.item_count - 1)
			for cp in custom_presets: ob.add_item("🔸 " + String(cp.get("name", "")))

func _on_assets(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200: return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if data is Dictionary and data.get("assets") is Array:
		library = data["assets"]; _refresh_lib()

func _register_asset(path: String, kind: String) -> void:
	_assets_req.request(ASSETS_URL, ["content-type: application/json"], HTTPClient.METHOD_POST, JSON.stringify({ "path": path, "kind": kind }))
	if not library.any(func(a): return a.get("path") == path):
		library.append({ "path": path, "kind": kind, "name": path.get_file() }); _refresh_lib()

func _import_model() -> void:
	_pick_file(["*.glb", "*.gltf", "*.fbx"], func(p):
		_register_asset(p, "model"); _add_at_focus("model", p))

func _import_image() -> void:
	_pick_file(["*.png", "*.jpg", "*.jpeg", "*.webp"], func(p):
		_register_asset(p, "image"); _add_at_focus("poster", p))

func _pick_file(filters: PackedStringArray, cb: Callable) -> void:
	var fd := FileDialog.new(); fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM; fd.filters = filters; fd.use_native_dialog = true
	add_child(fd)
	fd.file_selected.connect(func(p): cb.call(p); fd.queue_free())
	fd.canceled.connect(func(): fd.queue_free())
	fd.popup_centered(Vector2i(800, 560))
