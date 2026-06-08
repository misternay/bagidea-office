extends Node3D
## 🎨 3D Office Editor — a real in-world editor launched in its OWN window
## (office_floor with --editor3d). The procedural rooms/walls and the Ghost
## Deck are LOCKED context; you freely place / move / rotate / scale furniture
## and decor in true 3D, import .glb models (with animation playback), and
## save to the daemon's layout.json — the live wallpaper then renders the
## exact same arrangement. Furniture is decor (agents path on the existing
## graph); a saved layout never breaks navigation.
##
## Controls: LMB place/select · LMB-drag move · RMB/MMB-drag orbit ·
##           Shift+drag pan · wheel zoom · scene panel for rotate/scale/delete.

const LAYOUT_URL := "http://127.0.0.1:8787/layout"
const ASSETS_URL := "http://127.0.0.1:8787/assets"

var cam: Camera3D
var _root: Node3D                 # holds placed item rigs
var items: Array = []             # parallel to _root children: {dict, node}
var sel: int = -1
var armed_type := ""              # palette item to place on next empty click
var armed_asset := ""             # for poster/model placement
var play_anim := true

# orbit camera state
var orbit_yaw := 0.6
var orbit_pitch := 0.9
var orbit_dist := 26.0
var orbit_target := Vector3(3, 0, 1.5)
var _dragging_cam := false
var _panning := false
var _dragging_item := false

var _req: HTTPRequest
var _save_req: HTTPRequest
var ui: Control

const TYPES := [
	["desk", "🪑 Desk"], ["table", "🍽 Table"], ["chair", "💺 Chair"],
	["shelf", "📚 Shelf"], ["plant", "🪴 Plant"], ["lamp", "💡 Lamp"], ["rug", "🟫 Rug"],
]

func setup(camera: Camera3D) -> void:
	cam = camera

func _ready() -> void:
	_root = Node3D.new()
	_root.name = "EditorLayout"
	add_child(_root)
	_req = HTTPRequest.new(); add_child(_req); _req.request_completed.connect(_on_layout)
	_save_req = HTTPRequest.new(); add_child(_save_req)
	_build_ui()
	_update_cam()
	_req.request(LAYOUT_URL)

# ---------------------------------------------------------------- camera
func _update_cam() -> void:
	if cam == null:
		return
	var dir := Vector3(
		cos(orbit_pitch) * sin(orbit_yaw),
		sin(orbit_pitch),
		cos(orbit_pitch) * cos(orbit_yaw))
	cam.position = orbit_target + dir * orbit_dist
	cam.look_at(orbit_target, Vector3.UP)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_dist = max(6.0, orbit_dist - 2.0); _update_cam()
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_dist = min(70.0, orbit_dist + 2.0); _update_cam()
		elif e.button_index == MOUSE_BUTTON_RIGHT or e.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging_cam = e.pressed
			_panning = e.pressed and Input.is_key_pressed(KEY_SHIFT)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_on_left_press(e.position)
			else:
				_dragging_item = false
	elif e is InputEventMouseMotion:
		if _dragging_cam:
			if _panning:
				var right := cam.global_transform.basis.x
				var up := cam.global_transform.basis.y
				orbit_target -= (right * e.relative.x - up * e.relative.y) * orbit_dist * 0.0016
			else:
				orbit_yaw -= e.relative.x * 0.008
				orbit_pitch = clamp(orbit_pitch + e.relative.y * 0.008, 0.2, 1.45)
			_update_cam()
		elif _dragging_item and sel >= 0:
			var hit := _floor_hit(e.position)
			if hit != Vector3.INF:
				items[sel]["dict"]["x"] = snappedf(hit.x, 0.1)
				items[sel]["dict"]["z"] = snappedf(hit.z, 0.1)
				items[sel]["node"].position.x = items[sel]["dict"]["x"]
				items[sel]["node"].position.z = items[sel]["dict"]["z"]

func _floor_hit(screen: Vector2) -> Vector3:
	if cam == null:
		return Vector3.INF
	var origin := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return Vector3.INF
	var tt := -origin.y / dir.y
	if tt < 0:
		return Vector3.INF
	return origin + dir * tt

func _on_left_press(screen: Vector2) -> void:
	var hit := _floor_hit(screen)
	if hit == Vector3.INF:
		return
	# nearest existing item within reach → select+drag; else place armed type
	var best := -1
	var best_d := 1.2
	for i in items.size():
		var d := Vector2(items[i]["dict"]["x"] - hit.x, items[i]["dict"]["z"] - hit.z).length()
		if d < best_d:
			best_d = d; best = i
	if best >= 0:
		sel = best
		_dragging_item = true
		_refresh_sel()
	elif armed_type != "":
		var it := { "type": armed_type, "x": snappedf(hit.x, 0.1), "z": snappedf(hit.z, 0.1), "rot": 0.0, "scale": 1.0 }
		if armed_asset != "":
			it["asset"] = armed_asset
		_add_item(it)
		sel = items.size() - 1
		_refresh_sel()

# ---------------------------------------------------------------- items
func _on_layout(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if data is Dictionary and data.get("items") is Array:
		for it in data["items"]:
			if it is Dictionary:
				_add_item(it.duplicate())

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
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(w, h, d)
	mi.mesh = bm; mi.material_override = mat
	return mi

func _spawn(it: Dictionary) -> Node3D:
	var rig := Node3D.new()
	rig.position = Vector3(float(it.get("x", 0)), float(it.get("y", 0)), float(it.get("z", 0)))
	rig.rotation_degrees = Vector3(0, float(it.get("rot", 0)), 0)
	var s := float(it.get("scale", 1.0))
	rig.scale = Vector3(s, s, s)
	var col := String(it.get("color", ""))
	match String(it.get("type", "desk")):
		"desk":
			var top := _box(1.4, 0.08, 0.8, _mat(col if col != "" else "3a2e25", 0.5)); top.position.y = 0.74; rig.add_child(top)
			for sx in [-0.6, 0.6]:
				for sz in [-0.32, 0.32]:
					var leg := _box(0.08, 0.74, 0.08, _mat("222831")); leg.position = Vector3(sx, 0.37, sz); rig.add_child(leg)
		"table":
			var t := _box(1.1, 0.08, 1.1, _mat(col if col != "" else "4a3b2c", 0.5)); t.position.y = 0.7; rig.add_child(t)
			var post := _box(0.12, 0.7, 0.12, _mat("2a2a2a")); post.position.y = 0.35; rig.add_child(post)
		"chair":
			var seat := _box(0.45, 0.07, 0.45, _mat(col if col != "" else "5a6b8c", 0.6)); seat.position.y = 0.45; rig.add_child(seat)
			var back := _box(0.45, 0.5, 0.07, _mat(col if col != "" else "5a6b8c", 0.6)); back.position = Vector3(0, 0.7, -0.19); rig.add_child(back)
		"shelf":
			var body := _box(0.9, 1.6, 0.32, _mat(col if col != "" else "4a3a2a", 0.7)); body.position.y = 0.8; rig.add_child(body)
		"plant":
			var pot := _box(0.3, 0.3, 0.3, _mat("8a5a3a")); pot.position.y = 0.15; rig.add_child(pot)
			var lv := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 0.32; sm.height = 0.7
			lv.mesh = sm; lv.material_override = _mat(col if col != "" else "3c7a3c", 0.9); lv.position.y = 0.6; rig.add_child(lv)
		"lamp":
			var stand := _box(0.06, 1.3, 0.06, _mat("333")); stand.position.y = 0.65; rig.add_child(stand)
			var light := OmniLight3D.new(); light.position.y = 1.35; light.light_energy = 2.0; light.omni_range = 5.0
			light.light_color = Color(col) if col != "" else Color(1, 0.9, 0.7); rig.add_child(light)
		"rug":
			var r := _box(2.0, 0.02, 1.5, _mat(col if col != "" else "7a3b4b", 0.95)); r.position.y = 0.02; rig.add_child(r)
		"poster":
			_spawn_poster(rig, String(it.get("asset", "")))
		"model":
			_spawn_model(rig, String(it.get("asset", "")))
		_:
			var d := _box(0.6, 0.6, 0.6, _mat(col)); d.position.y = 0.3; rig.add_child(d)
	return rig

func _spawn_poster(rig: Node3D, asset: String) -> void:
	if asset == "":
		return
	var img := Image.new()
	if img.load(asset) != OK:
		return
	var mi := MeshInstance3D.new(); var qm := QuadMesh.new(); qm.size = Vector2(1.2, 0.8); mi.mesh = qm
	var m := StandardMaterial3D.new(); m.albedo_texture = ImageTexture.create_from_image(img)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m; mi.position.y = 1.4; rig.add_child(mi)

func _spawn_model(rig: Node3D, asset: String) -> void:
	if asset == "":
		return
	var ext := asset.get_extension().to_lower()
	var scene: Node = null
	if ext == "glb" or ext == "gltf":
		var doc := GLTFDocument.new(); var st := GLTFState.new()
		if doc.append_from_file(asset, st) == OK:
			scene = doc.generate_scene(st)
	elif ext == "fbx":
		var doc := FBXDocument.new(); var st := GLTFState.new()
		if doc.append_from_file(asset, st) == OK:
			scene = doc.generate_scene(st)
	if scene:
		rig.add_child(scene)
		if play_anim:
			var ap := scene.find_child("AnimationPlayer", true, false)
			if ap and ap is AnimationPlayer:
				var names := (ap as AnimationPlayer).get_animation_list()
				if names.size() > 0:
					(ap as AnimationPlayer).play(names[0])

func _respawn(i: int) -> void:
	if i < 0 or i >= items.size():
		return
	var old: Node3D = items[i]["node"]
	old.queue_free()
	var node := _spawn(items[i]["dict"])
	_root.add_child(node)
	items[i]["node"] = node

# ---------------------------------------------------------------- UI
func _build_ui() -> void:
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layer := CanvasLayer.new(); layer.add_child(ui); add_child(layer)

	# left palette panel
	var panel := PanelContainer.new()
	panel.position = Vector2(14, 14)
	panel.custom_minimum_size = Vector2(212, 0)
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	var title := Label.new(); title.text = "🎨 OFFICE EDITOR"; vb.add_child(title)
	var hint := Label.new(); hint.text = "คลิกวาง · ลากย้าย · ขวา/กลางหมุนกล้อง"
	hint.add_theme_font_size_override("font_size", 10); vb.add_child(hint)
	for t in TYPES:
		var b := Button.new(); b.text = t[1]
		b.pressed.connect(func(): armed_type = t[0]; armed_asset = ""; _flash("วาง: " + t[1]))
		vb.add_child(b)
	var imp := Button.new(); imp.text = "📦 Import .glb"; imp.pressed.connect(_import_model); vb.add_child(imp)
	var pst := Button.new(); pst.text = "🖼 Import image"; pst.pressed.connect(_import_image); vb.add_child(pst)
	var animchk := CheckButton.new(); animchk.text = "เล่น animation โมเดล"; animchk.button_pressed = true
	animchk.toggled.connect(func(on): play_anim = on); vb.add_child(animchk)
	var save := Button.new(); save.text = "💾 บันทึก (อัปเดตวอลเปเปอร์)"; save.pressed.connect(_save); vb.add_child(save)
	ui.add_child(panel)

	# right selected-item panel
	var sp := PanelContainer.new(); sp.name = "SelPanel"
	sp.anchor_left = 1.0; sp.anchor_right = 1.0
	sp.position = Vector2(-230, 14); sp.custom_minimum_size = Vector2(216, 0)
	var sv := VBoxContainer.new(); sv.name = "SelBox"; sv.add_theme_constant_override("separation", 6); sp.add_child(sv)
	ui.add_child(sp)
	sp.visible = false

	# status toast
	var toast := Label.new(); toast.name = "Toast"
	toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	toast.position = Vector2(-100, -50); ui.add_child(toast)

func _flash(msg: String) -> void:
	var toast := ui.find_child("Toast", true, false)
	if toast and toast is Label:
		(toast as Label).text = msg

func _refresh_sel() -> void:
	var sp := ui.find_child("SelPanel", true, false)
	var sv := ui.find_child("SelBox", true, false)
	if sp == null or sv == null:
		return
	for c in sv.get_children():
		c.queue_free()
	if sel < 0 or sel >= items.size():
		sp.visible = false
		return
	sp.visible = true
	var it: Dictionary = items[sel]["dict"]
	var lbl := Label.new(); lbl.text = "⚙ " + String(it.get("type", "")); sv.add_child(lbl)
	# rotate
	var rl := Label.new(); rl.text = "หมุน"; sv.add_child(rl)
	var rot := HSlider.new(); rot.min_value = 0; rot.max_value = 360; rot.value = float(it.get("rot", 0))
	rot.value_changed.connect(func(v):
		it["rot"] = v
		items[sel]["node"].rotation_degrees.y = v)
	sv.add_child(rot)
	# scale
	var sl := Label.new(); sl.text = "ขนาด"; sv.add_child(sl)
	var scl := HSlider.new(); scl.min_value = 0.4; scl.max_value = 3.0; scl.step = 0.1; scl.value = float(it.get("scale", 1))
	scl.value_changed.connect(func(v):
		it["scale"] = v
		items[sel]["node"].scale = Vector3(v, v, v))
	sv.add_child(scl)
	# delete
	var del := Button.new(); del.text = "🗑 ลบ"
	del.pressed.connect(func():
		items[sel]["node"].queue_free()
		items.remove_at(sel)
		sel = -1
		_refresh_sel())
	sv.add_child(del)

func _import_model() -> void:
	_pick_file(["*.glb", "*.gltf", "*.fbx"], func(path):
		armed_type = "model"; armed_asset = path; _flash("คลิกวางโมเดล"))

func _import_image() -> void:
	_pick_file(["*.png", "*.jpg", "*.jpeg", "*.webp"], func(path):
		armed_type = "poster"; armed_asset = path; _flash("คลิกวางรูป"))

func _pick_file(filters: PackedStringArray, cb: Callable) -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = filters
	fd.use_native_dialog = true
	add_child(fd)
	fd.file_selected.connect(func(p): cb.call(p); fd.queue_free())
	fd.canceled.connect(func(): fd.queue_free())
	fd.popup_centered(Vector2i(800, 560))

func _save() -> void:
	var out: Array = []
	for e in items:
		out.append(e["dict"])
	var body := JSON.stringify({ "items": out })
	_save_req.request(LAYOUT_URL, ["content-type: application/json"], HTTPClient.METHOD_POST, body)
	_flash("💾 บันทึกแล้ว — วอลเปเปอร์อัปเดต")
