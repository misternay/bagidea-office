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

var rig: Node3D                   # CameraRig — driven exactly like the real view
var cam: Camera3D
var _root: Node3D                 # holds placed item rigs
var items: Array = []             # parallel to _root children: {dict, node}
var sel: int = -1
var armed_type := ""              # palette item to place on next empty click
var armed_asset := ""             # for poster/model placement
var play_anim := true
var imported_models: Array = []   # paths of .glb/.fbx imported this session

# Camera = the REAL wallpaper framing, frozen (no drift), DOF off, and the
# only freedom is a gentle left/right yaw so height + focus + beauty stay put.
const BASE_TARGET := Vector3(2.5, 0.2, 0.8)
const BASE_YAW := -12.0
const BASE_PITCH := -45.0
const BASE_DIST := 58.0
const YAW_LIMIT := 9.0            # ± degrees of allowed sway
var yaw := BASE_YAW
var _dragging_cam := false
var _dragging_item := false

var _req: HTTPRequest
var _save_req: HTTPRequest
var _preset_req: HTTPRequest
var ui: Control

const TYPES := [
	["desk", "🪑 Desk"], ["table", "🍽 Table"], ["chair", "💺 Chair"],
	["shelf", "📚 Shelf"], ["plant", "🪴 Plant"], ["lamp", "💡 Lamp"], ["rug", "🟫 Rug"],
]

# 5 starter furniture-arrangement presets across the floor (x -11..17,
# z -11..14). Loading one replaces the current items; tweak then "Save as
# preset" to keep a custom one. These are intentionally simple seeds.
const PRESETS := [
	{ "name": "Classic grid", "items": [
		{ "type": "desk", "x": -7, "z": -7, "rot": 0 }, { "type": "chair", "x": -7, "z": -6, "rot": 180 },
		{ "type": "desk", "x": -4, "z": -7, "rot": 0 }, { "type": "chair", "x": -4, "z": -6, "rot": 180 },
		{ "type": "desk", "x": -7, "z": -3, "rot": 0 }, { "type": "chair", "x": -7, "z": -2, "rot": 180 },
		{ "type": "desk", "x": -4, "z": -3, "rot": 0 }, { "type": "chair", "x": -4, "z": -2, "rot": 180 },
		{ "type": "plant", "x": -9.5, "z": -8.5 }, { "type": "plant", "x": -1.5, "z": -1 },
		{ "type": "lamp", "x": -2, "z": -8, "color": "ffe6b0" } ] },
	{ "name": "Open plan", "items": [
		{ "type": "table", "x": -5, "z": -5, "scale": 1.4 }, { "type": "chair", "x": -6, "z": -5, "rot": 90 },
		{ "type": "chair", "x": -4, "z": -5, "rot": 270 }, { "type": "chair", "x": -5, "z": -6, "rot": 180 },
		{ "type": "chair", "x": -5, "z": -4, "rot": 0 },
		{ "type": "rug", "x": -5, "z": -5, "scale": 1.6, "color": "33405a" },
		{ "type": "plant", "x": -8, "z": -2 }, { "type": "shelf", "x": -9, "z": -7, "rot": 90 } ] },
	{ "name": "Cozy lounge", "items": [
		{ "type": "rug", "x": 2, "z": 4, "scale": 1.8, "color": "7a3b4b" },
		{ "type": "table", "x": 2, "z": 4, "scale": 0.8 },
		{ "type": "chair", "x": 0.8, "z": 4, "rot": 90 }, { "type": "chair", "x": 3.2, "z": 4, "rot": 270 },
		{ "type": "plant", "x": -0.5, "z": 2.5 }, { "type": "plant", "x": 4.5, "z": 5.5 },
		{ "type": "lamp", "x": 0, "z": 6, "color": "ffcf9a" }, { "type": "lamp", "x": 4.5, "z": 2.5, "color": "ffcf9a" },
		{ "type": "shelf", "x": 5.5, "z": 4, "rot": 270 } ] },
	{ "name": "Focus pods", "items": [
		{ "type": "desk", "x": 8, "z": -7 }, { "type": "chair", "x": 8, "z": -6, "rot": 180 }, { "type": "shelf", "x": 9.4, "z": -7, "rot": 90 },
		{ "type": "desk", "x": 8, "z": -3 }, { "type": "chair", "x": 8, "z": -2, "rot": 180 }, { "type": "shelf", "x": 9.4, "z": -3, "rot": 90 },
		{ "type": "desk", "x": 12, "z": -7 }, { "type": "chair", "x": 12, "z": -6, "rot": 180 }, { "type": "plant", "x": 13.5, "z": -8 },
		{ "type": "lamp", "x": 10, "z": -5, "color": "cfe0ff" } ] },
	{ "name": "Minimal green", "items": [
		{ "type": "desk", "x": 0, "z": 0 }, { "type": "chair", "x": 0, "z": 1, "rot": 180 },
		{ "type": "plant", "x": -2, "z": -1 }, { "type": "plant", "x": 2, "z": -1 },
		{ "type": "plant", "x": -2, "z": 2 }, { "type": "plant", "x": 2, "z": 2 },
		{ "type": "rug", "x": 0, "z": 0.5, "scale": 1.3, "color": "2f5a3a" } ] },
]
var custom_presets: Array = []

func setup(camera_rig: Node3D, camera: Camera3D) -> void:
	rig = camera_rig
	cam = camera

func _ready() -> void:
	_root = Node3D.new()
	_root.name = "EditorLayout"
	add_child(_root)
	_req = HTTPRequest.new(); add_child(_req); _req.request_completed.connect(_on_layout)
	_save_req = HTTPRequest.new(); add_child(_save_req)
	_preset_req = HTTPRequest.new(); add_child(_preset_req); _preset_req.request_completed.connect(_on_preset)
	_build_ui()
	_update_cam()
	_req.request(LAYOUT_URL)
	_preset_req.request("http://127.0.0.1:8787/presets")  # pull saved presets

# ---------------------------------------------------------------- camera
func _update_cam() -> void:
	if rig == null or cam == null:
		return
	rig.position = BASE_TARGET
	rig.rotation_degrees = Vector3(BASE_PITCH, yaw, 0.0)
	cam.position = Vector3(0.0, 0.0, BASE_DIST)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_RIGHT or e.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging_cam = e.pressed
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_on_left_press(e.position)
			else:
				_dragging_item = false
	elif e is InputEventMouseMotion:
		if _dragging_cam:
			# yaw only, clamped — locks height, distance and focus so the
			# framing never drifts from the real wallpaper look.
			yaw = clampf(yaw - e.relative.x * 0.06, BASE_YAW - YAW_LIMIT, BASE_YAW + YAW_LIMIT)
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
	# presets
	var pl := Label.new(); pl.text = "— Presets —"; pl.add_theme_font_size_override("font_size", 10); vb.add_child(pl)
	var pbtn := OptionButton.new(); pbtn.name = "PresetPick"
	pbtn.add_item("เลือก preset…")
	for pr in PRESETS:
		pbtn.add_item("⭐ " + pr["name"])
	pbtn.item_selected.connect(_on_preset_picked)
	vb.add_child(pbtn)
	# import + library
	var imp := Button.new(); imp.text = "📦 Import .glb"; imp.pressed.connect(_import_model); vb.add_child(imp)
	var pst := Button.new(); pst.text = "🖼 Import image"; pst.pressed.connect(_import_image); vb.add_child(pst)
	var lib := Label.new(); lib.name = "LibLabel"; lib.text = "คลังโมเดล: (ว่าง)"
	lib.add_theme_font_size_override("font_size", 10); vb.add_child(lib)
	var animchk := CheckButton.new(); animchk.text = "เล่น animation โมเดล"; animchk.button_pressed = true
	animchk.toggled.connect(func(on): play_anim = on); vb.add_child(animchk)
	var save := Button.new(); save.text = "💾 บันทึก (อัปเดตวอลเปเปอร์)"; save.pressed.connect(_save); vb.add_child(save)
	var savep := Button.new(); savep.text = "⭐ บันทึกเป็น preset"; savep.pressed.connect(_save_as_preset); vb.add_child(savep)
	ui.add_child(panel)
	_refresh_lib()

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
		armed_type = "model"; armed_asset = path
		if not imported_models.has(path):
			imported_models.append(path)
		_refresh_lib()
		_flash("คลิกวางโมเดล"))

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

func _current_items() -> Array:
	var out: Array = []
	for e in items:
		out.append(e["dict"])
	return out

func _save() -> void:
	var body := JSON.stringify({ "items": _current_items() })
	_save_req.request(LAYOUT_URL, ["content-type: application/json"], HTTPClient.METHOD_POST, body)
	_flash("💾 บันทึกแล้ว — วอลเปเปอร์อัปเดต")

# ---------------------------------------------------------------- presets
func _on_preset_picked(idx: int) -> void:
	if idx <= 0:
		return
	var list := PRESETS + custom_presets
	if idx - 1 >= list.size():
		return
	_load_preset(list[idx - 1])

func _load_preset(pr: Dictionary) -> void:
	for c in _root.get_children():
		c.queue_free()
	items.clear()
	sel = -1
	for it in pr.get("items", []):
		if it is Dictionary:
			_add_item(it.duplicate(true))
	_refresh_sel()
	_flash("⭐ โหลด preset: " + String(pr.get("name", "")))

func _save_as_preset() -> void:
	# tiny inline name prompt
	var dlg := AcceptDialog.new()
	dlg.title = "บันทึกเป็น preset"
	var le := LineEdit.new(); le.placeholder_text = "ชื่อ preset"; le.custom_minimum_size = Vector2(260, 0)
	dlg.add_child(le)
	dlg.register_text_enter(le)
	add_child(dlg)
	dlg.confirmed.connect(func():
		var nm := le.text.strip_edges()
		if nm != "":
			var body := JSON.stringify({ "name": nm, "items": _current_items() })
			_save_req.request("http://127.0.0.1:8787/presets", ["content-type: application/json"], HTTPClient.METHOD_POST, body)
			_flash("⭐ บันทึก preset: " + nm)
			_preset_req.request("http://127.0.0.1:8787/presets")  # refresh list
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.popup_centered(Vector2i(320, 130))
	le.grab_focus()

func _on_preset(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if data is Dictionary and data.get("presets") is Array:
		custom_presets = data["presets"]
		var pick := ui.find_child("PresetPick", true, false)
		if pick and pick is OptionButton:
			var ob := pick as OptionButton
			# rebuild: default + custom
			while ob.item_count > 1 + PRESETS.size():
				ob.remove_item(ob.item_count - 1)
			for cp in custom_presets:
				ob.add_item("🔸 " + String(cp.get("name", "")))

func _refresh_lib() -> void:
	var lbl := ui.find_child("LibLabel", true, false)
	if lbl == null or not (lbl is Label):
		return
	if imported_models.is_empty():
		(lbl as Label).text = "คลังโมเดล: (ว่าง)"
	else:
		var names: Array = []
		for m in imported_models:
			names.append(String(m).get_file())
		(lbl as Label).text = "คลังโมเดล: " + ", ".join(names)
