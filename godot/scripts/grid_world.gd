extends Node3D
## Uniform room-grid office — the swappable "jigsaw" floor.
##
## The floor is GRID_COLS × GRID_ROWS identical cells. Every room is built into
## its own container Node3D sitting at a fixed SLOT centre; swapping two rooms
## just exchanges which slot each container sits in (and re-homes its agent
## anchors). Because every cell is the same size with door gaps on all four
## sides, ANY room fits in ANY slot — true jigsaw.
##
## Developed standalone (render-to-PNG) so the geometry can be perfected before
## being wired into the live world_builder API.

const CELL_X := 10.5       # cell width  (X) — rooms are rectangular: X longer than Z
const CELL_Z := 8.0        # cell depth  (Z)
const GRID_COLS := 3
const GRID_ROWS := 3
const WALL_H := 4.0
const WALL_T := 0.18
const DOOR_W := 2.2        # door-gap width on each interior side

# default room kind per slot (index = row*COLS + col)
var room_order: Array = [
	"exec",  "ops",   "server",
	"lobby", "cafe",  "meeting",
	"rec",   "dormx", "dorm",
]

# kind → {label, floor tint (LIGHT pastel — polished metal catches SSR), accent light}
const ROOM_DEFS := {
	"exec":    {"label": "EXECUTIVE", "tint": "ffe7c2", "accent": "ffb14a"},
	"ops":     {"label": "OPS FLOOR", "tint": "cfe2ff", "accent": "4ec3ff"},
	"server":  {"label": "SERVER",    "tint": "c8ffe0", "accent": "55ffaa"},
	"lobby":   {"label": "LOBBY",     "tint": "ffd8d0", "accent": "ff7a5a"},
	"cafe":    {"label": "CAFETERIA", "tint": "ffe2c0", "accent": "ffb874"},
	"meeting": {"label": "MEETING",   "tint": "e3d6ff", "accent": "b48cff"},
	"rec":     {"label": "RECREATION","tint": "d4ffd8", "accent": "7effc8"},
	"dormx":   {"label": "DORM XL",   "tint": "d2dcff", "accent": "8ab4ff"},
	"dorm":    {"label": "DORM",      "tint": "d6dcff", "accent": "9ab0ff"},
}

# agent anchors per room kind — LOCAL offset from cell centre (y = 0.86 floor).
# Names are exactly those agent_manager.gd already targets, so the brain is
# untouched: only WHERE each anchor sits is now grid-driven.
# All sub-anchors live in the FOUR QUADRANTS (|x|>=1.6 and |z|>=1.6) so the
# central plus-corridor that links the four door gaps stays clear — agents and
# the swap never drop furniture in a doorway. (cell is 10.5 x 8 → half 5.25 x 4)
const ROOM_ANCHORS := {
	"exec":  {"exec_c": Vector2(0, 0), "ceo_desk": Vector2(-2.6, -3.0), "lead_desk": Vector2(3.0, -1.65),
		"pace_a": Vector2(-3.0, 2.4), "pace_b": Vector2(3.0, 2.4)},
	"ops":   {"ops_c": Vector2(0, 0), "desk1": Vector2(-4.0, -1.65), "desk2": Vector2(-2.0, -1.65),
		"desk3": Vector2(2.0, -1.65), "desk4": Vector2(4.0, -1.65), "desk5": Vector2(-2.5, 3.25),
		"desk6": Vector2(2.5, 3.25), "ap1": Vector2(-4.2, 2.4), "ap2": Vector2(4.2, 2.4)},
	"server": {"server_c": Vector2(0, 0)},
	"lobby": {"lobby_c": Vector2(0, 0), "spawn": Vector2(0, 3.4), "sec_c": Vector2(-3.2, -2.5),
		"sec_window": Vector2(-3.2, -1.7)},
	"cafe":  {"cafe_c": Vector2(0, 0), "cafe_s1": Vector2(-3.0, 2.4), "cafe_s2": Vector2(3.0, -2.4)},
	"meeting": {"meeting_c": Vector2(0, 0), "m_s1": Vector2(-2.6, -2.4), "m_s2": Vector2(2.6, -2.4),
		"m_s3": Vector2(-2.6, 2.4), "m_s4": Vector2(2.6, 2.4)},
	"rec":   {"rec_c": Vector2(0, 0), "rec_s1": Vector2(-3.2, -2.4), "rec_s2": Vector2(3.2, 2.4),
		"rec_s3": Vector2(-3.2, 2.4), "rec_s4": Vector2(3.2, -2.4)},
	"dormx": {"dormx_c": Vector2(0, 0), "b3": Vector2(-4.0, -2.5), "b4": Vector2(-2.0, -2.5),
		"b5": Vector2(2.0, -2.5), "b6": Vector2(4.0, -2.5), "b7": Vector2(-2.5, 2.4), "b8": Vector2(2.5, 2.4)},
	"dorm":  {"dorm_c": Vector2(0, 0), "bed1": Vector2(-3.0, -2.5), "bed2": Vector2(3.0, -2.5)},
}
const FLOOR_Y := 0.86
const SEAT_DZ := 0.85    # desk pod chair offset: in FRONT of the desk (south, the
                         # camera side) so the seated agent isn't hidden behind the
                         # desk; the work anchor sits here and the agent faces the
                         # screen (north). (The CEO console is the exception.)

var _cell_node: Array = []      # slot index → container Node3D
var _cell_center: Array = []    # slot index → Vector3 (fixed)

var WP := {}                    # anchor name → world Vector3 (live)
var _anchor_slot := {}          # anchor name → current slot
var _anchor_local := {}         # anchor name → Vector2 local offset
var astar := AStar3D.new()
var _wp_ids := {}
var _next_id := 0
var _slot_static := {}          # slot → [hub id, door ids touching slot] (static; anchors added live)

func _ready() -> void:
	_build()
	_build_graph()

func slot_center(slot: int) -> Vector3:
	var c := slot % GRID_COLS
	var r := slot / GRID_COLS
	var x := (c - (GRID_COLS - 1) * 0.5) * CELL_X
	var z := (r - (GRID_ROWS - 1) * 0.5) * CELL_Z
	return Vector3(x, 0, z)

func _build() -> void:
	# ground slab + outer perimeter wall around the whole grid
	var halfx := GRID_COLS * CELL_X * 0.5
	var halfz := GRID_ROWS * CELL_Z * 0.5
	add_child(_box(Vector3(0, -0.1, 0), Vector3(GRID_COLS * CELL_X + 0.6, 0.2, GRID_ROWS * CELL_Z + 0.6), _m("232838", 0.5)))
	# perimeter is a U: back (north) + the two sides, with the FRONT (south, the
	# camera-facing side) left open — same silhouette as the original office.
	var lenx := GRID_COLS * CELL_X + WALL_T
	var lenz := GRID_ROWS * CELL_Z
	_perim(Vector3(0, 0, -halfz), Vector3(lenx, 0, WALL_T))      # back wall
	_perim(Vector3(-halfx, 0, 0), Vector3(WALL_T, 0, lenz))      # west wall
	_perim(Vector3( halfx, 0, 0), Vector3(WALL_T, 0, lenz))      # east wall

	# rooms — one container per slot at its fixed cell centre
	for slot in range(GRID_COLS * GRID_ROWS):
		var center := slot_center(slot)
		_cell_center.append(center)
		var room := Node3D.new()
		room.position = center
		add_child(room)
		_cell_node.append(room)
		var kind := String(room_order[slot])
		_build_room(room, kind)
		_register_anchors(slot, kind)

func _perim(pos: Vector3, size: Vector3) -> void:
	var T := 0.34          # thick enough to read as a real wall from a distance
	var base := _m("69748f", 0.6)
	var glass := _m("b6d2f4", 0.05, "7fa0cf", 0.8); glass.albedo_color.a = 0.55
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var cap := _m("dbe4f2", 0.3)
	var bh := 2.8          # SOLID wall (the bulk) — clearly visible
	var gh := WALL_H - bh  # window band above
	var sz := Vector3(max(size.x, T), 0, max(size.z, T))
	add_child(_box(Vector3(pos.x, bh * 0.5, pos.z), Vector3(sz.x, bh, sz.z), base))
	add_child(_box(Vector3(pos.x, bh + gh * 0.5, pos.z), Vector3(sz.x, gh, sz.z), glass))
	add_child(_box(Vector3(pos.x, WALL_H + 0.03, pos.z), Vector3(sz.x + 0.08, 0.1, sz.z + 0.08), cap))

## Record this slot's agent anchors (world + local + slot) from ROOM_ANCHORS.
func _register_anchors(slot: int, kind: String) -> void:
	var center: Vector3 = _cell_center[slot]
	for aname in ROOM_ANCHORS.get(kind, {}):
		var loc: Vector2 = ROOM_ANCHORS[kind][aname]
		_anchor_local[aname] = loc
		_anchor_slot[aname] = slot
		WP[aname] = center + Vector3(loc.x, FLOOR_Y, loc.y)

# ----------------------------------------------------------------- A* graph
## Skeleton: a hub per slot + a door node on each shared wall. Room anchors hang
## off their slot's hub. Swapping a room re-homes its anchors to the new hub.
func _build_graph() -> void:
	# hubs at slot centres
	for slot in range(GRID_COLS * GRID_ROWS):
		_add_point("hub_%d" % slot, _cell_center[slot] + Vector3(0, FLOOR_Y, 0))
		_slot_static[slot] = [_wp_ids["hub_%d" % slot]]
	# door nodes between orthogonally adjacent slots, connecting the two hubs
	for slot in range(GRID_COLS * GRID_ROWS):
		var c := slot % GRID_COLS
		var r := slot / GRID_COLS
		if c + 1 < GRID_COLS:
			_link_slots(slot, slot + 1)
		if r + 1 < GRID_ROWS:
			_link_slots(slot, slot + GRID_COLS)
	# anchors → their slot hub
	for aname in WP:
		_add_point(aname, WP[aname])
		var hk := "hub_%d" % int(_anchor_slot.get(aname, -1))
		if _wp_ids.has(hk):
			astar.connect_points(_wp_ids[aname], _wp_ids[hk])
		else:
			push_warning("grid: anchor %s has no hub (%s)" % [aname, hk])

func _link_slots(a: int, b: int) -> void:
	var mid: Vector3 = (_cell_center[a] + _cell_center[b]) * 0.5 + Vector3(0, FLOOR_Y, 0)
	var dn := "door_%d_%d" % [a, b]
	_add_point(dn, mid)
	astar.connect_points(_wp_ids["hub_%d" % a], _wp_ids[dn])
	astar.connect_points(_wp_ids[dn], _wp_ids["hub_%d" % b])
	# the door belongs to BOTH cells — a valid in-cell entry node on either side
	_slot_static[a].append(_wp_ids[dn])
	_slot_static[b].append(_wp_ids[dn])

func _add_point(name: String, pos: Vector3) -> void:
	_wp_ids[name] = _next_id
	astar.add_point(_next_id, pos)
	_next_id += 1

func _nearest(pos: Vector3) -> int:
	var best := -1; var best_d := INF
	for name in _wp_ids:
		var d: float = pos.distance_to(astar.get_point_position(_wp_ids[name]))
		if d < best_d: best_d = d; best = _wp_ids[name]
	return best

## Which grid slot a world position sits in (clamped to the grid).
func _slot_of(pos: Vector3) -> int:
	var c := int(round(pos.x / CELL_X + (GRID_COLS - 1) * 0.5))
	var r := int(round(pos.z / CELL_Z + (GRID_ROWS - 1) * 0.5))
	c = clampi(c, 0, GRID_COLS - 1)
	r = clampi(r, 0, GRID_ROWS - 1)
	return r * GRID_COLS + c

## Nearest graph node that lives in the SAME cell as `pos` (its hub, a door on
## that cell's wall, or an anchor in that cell). This is the crux of the
## walk-through-walls fix: the plain nearest node may sit across a wall in the
## neighbouring cell, so the first straight leg would clip through it. Restricting
## the entry node to the current cell forces every inter-room trip through a door.
func _nearest_slot(pos: Vector3) -> int:
	var slot := _slot_of(pos)
	var best := -1; var best_d := INF
	for id in _slot_static.get(slot, []):
		var d: float = pos.distance_to(astar.get_point_position(id))
		if d < best_d: best_d = d; best = id
	# this cell's live anchors (membership rides room swaps via _anchor_slot)
	for aname in _anchor_slot:
		if _anchor_slot[aname] == slot and _wp_ids.has(aname):
			var d2: float = pos.distance_to(astar.get_point_position(_wp_ids[aname]))
			if d2 < best_d: best_d = d2; best = _wp_ids[aname]
	return best if best != -1 else _nearest(pos)

func path_to(from_pos: Vector3, target: String) -> Array:
	if not _wp_ids.has(target): return []
	var pts := astar.get_point_path(_nearest_slot(from_pos), _wp_ids[target])
	var out: Array = []
	for p in pts: out.append(p)
	if out.size() > 1 and from_pos.distance_to(out[0]) < 0.4: out.pop_front()
	return out

func path_between(from_pos: Vector3, to_pos: Vector3) -> Array:
	var pts := astar.get_point_path(_nearest_slot(from_pos), _nearest_slot(to_pos))
	var out: Array = []
	for p in pts: out.append(p)
	if out.size() > 1 and from_pos.distance_to(out[0]) < 0.4: out.pop_front()
	out.append(to_pos)
	return out

## Re-home a room's anchors after its container moved to `slot`.
func _rehome_anchors(slot: int) -> void:
	var center: Vector3 = _cell_center[slot]
	for aname in _anchor_slot:
		if _anchor_slot[aname] == slot:
			var loc: Vector2 = _anchor_local[aname]
			WP[aname] = center + Vector3(loc.x, FLOOR_Y, loc.y)
			if _wp_ids.has(aname):
				astar.set_point_position(_wp_ids[aname], WP[aname])

## Swap two rooms between their slots — the whole container (walls, floor,
## furniture) glides to the other slot. Agent anchors ride along because they
## live under the container.
func swap_slots(a: int, b: int) -> void:
	if a == b or a < 0 or b < 0: return
	if a >= _cell_node.size() or b >= _cell_node.size(): return
	var na: Node3D = _cell_node[a]
	var nb: Node3D = _cell_node[b]
	na.position = _cell_center[b]
	nb.position = _cell_center[a]
	_cell_node[a] = nb; _cell_node[b] = na
	var tmp = room_order[a]; room_order[a] = room_order[b]; room_order[b] = tmp
	# move each room's anchors to the other slot (re-home position + re-wire the
	# graph edge from the old hub to the new one)
	var a_an: Array = []; var b_an: Array = []
	for an in _anchor_slot:
		if _anchor_slot[an] == a: a_an.append(an)
		elif _anchor_slot[an] == b: b_an.append(an)
	for an in a_an: _reslot_anchor(an, a, b)
	for an in b_an: _reslot_anchor(an, b, a)

func _reslot_anchor(aname: String, from_slot: int, to_slot: int) -> void:
	_anchor_slot[aname] = to_slot
	var center: Vector3 = _cell_center[to_slot]
	var loc: Vector2 = _anchor_local[aname]
	WP[aname] = center + Vector3(loc.x, FLOOR_Y, loc.y)
	var fh := "hub_%d" % from_slot
	var th := "hub_%d" % to_slot
	if _wp_ids.has(aname) and _wp_ids.has(fh) and _wp_ids.has(th):
		astar.set_point_position(_wp_ids[aname], WP[aname])
		if astar.are_points_connected(_wp_ids[aname], _wp_ids[fh]):
			astar.disconnect_points(_wp_ids[aname], _wp_ids[fh])
		astar.connect_points(_wp_ids[aname], _wp_ids[th])

## Build one room's contents at LOCAL origin (cell centre = 0,0,0).
## Matches the original art: polished tinted metal floor + LOW glass railings
## (not tall opaque walls — those felt cramped) + warm accent lighting.
func _build_room(room: Node3D, kind: String) -> void:
	var d: Dictionary = ROOM_DEFS.get(kind, ROOM_DEFS["ops"])
	var tint := Color(String(d["tint"]))
	var kit := _kit_avail()
	# ── floor: polished metal tiles, tinted per room (catch SSR reflections) ──
	if kit:
		_floor_tiles(room, tint)
	else:
		var fl := _box(Vector3(0, 0.02, 0), Vector3(CELL_X - WALL_T, 0.04, CELL_Z - WALL_T), _m(String(d["tint"]), 0.18))
		room.add_child(fl)
	# ── low dividers: knee-to-waist glass railings, open and airy ────────────
	_dividers(room, tint)
	# ── lighting: ONE soft accent dome (sun + ambient already light the floor;
	#    extra lights wash the polished tiles out to white) ───────────────────
	var lamp := OmniLight3D.new(); lamp.position = Vector3(0, 2.6, 0)
	lamp.light_color = Color(String(d["accent"])); lamp.light_energy = 0.9; lamp.omni_range = CELL_X * 0.85
	room.add_child(lamp)
	_furnish(room, kind, String(d["accent"]))

## Polished tinted metal floor — 3×2 kit tiles stretched to the rectangular cell.
func _floor_tiles(room: Node3D, tint: Color) -> void:
	var spx := CELL_X - WALL_T
	var spz := CELL_Z - WALL_T
	var nx := 3; var nz := 2
	for ix in nx:
		for iz in nz:
			var px := ((ix + 0.5) / float(nx) - 0.5) * spx
			var pz := ((iz + 0.5) / float(nz) - 0.5) * spz
			var tile := _kit_node(room, "Floor_Metal_Square", Vector3(px, 0, pz), 0.0,
				Vector3(spx / nx / 4.0, 1.0, spz / nz / 4.0))
			# mid-tone, not pastel — pastel blows out to white under the sun
			if tile: _tint_meshes(tile, tint * 0.62, 0.42)

## Low glass railings on all four sides, each split around a centre door gap.
func _dividers(room: Node3D, tint: Color) -> void:
	var hx := CELL_X * 0.5         # east/west walls sit here
	var hz := CELL_Z * 0.5         # north/south walls sit here
	var seg_x := (CELL_X - DOOR_W) * 0.5   # length of each north/south segment (runs along X)
	var seg_z := (CELL_Z - DOOR_W) * 0.5   # length of each east/west segment (runs along Z)
	var off_x := (DOOR_W + seg_x) * 0.5
	var off_z := (DOOR_W + seg_z) * 0.5
	var kit := _kit_avail()
	for s in [-1.0, 1.0]:
		var nz: float = s * hz
		var nx: float = s * hx
		if kit:
			_kit_node(room, "Railing_Flat", Vector3(-off_x, 0, nz), 0.0, Vector3(seg_x / 3.92, 1.0, 1.0))
			_kit_node(room, "Railing_Flat", Vector3(off_x, 0, nz), 0.0, Vector3(seg_x / 3.92, 1.0, 1.0))
			_kit_node(room, "Railing_Flat", Vector3(nx, 0, -off_z), 90.0, Vector3(seg_z / 3.92, 1.0, 1.0))
			_kit_node(room, "Railing_Flat", Vector3(nx, 0, off_z), 90.0, Vector3(seg_z / 3.92, 1.0, 1.0))
		else:
			var gm := _m("aac6e8", 0.08); gm.albedo_color.a = 0.5
			gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			room.add_child(_box(Vector3(-off_x, 0.55, nz), Vector3(seg_x, 1.1, 0.06), gm))
			room.add_child(_box(Vector3(off_x, 0.55, nz), Vector3(seg_x, 1.1, 0.06), gm))
			room.add_child(_box(Vector3(nx, 0.55, -off_z), Vector3(0.06, 1.1, seg_z), gm))
			room.add_child(_box(Vector3(nx, 0.55, off_z), Vector3(0.06, 1.1, seg_z), gm))

## Tint + polish a kit model's meshes (mirrors world_builder._tint_meshes).
func _tint_meshes(node: Node, tint: Color, rough := -1.0) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var mi: MeshInstance3D = node
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i)
			if src is BaseMaterial3D:
				var dup: BaseMaterial3D = src.duplicate()
				dup.albedo_color = tint
				if rough >= 0.0:
					dup.roughness = rough; dup.metallic = 0.12
				mi.set_surface_override_material(i, dup)
	for c in node.get_children():
		_tint_meshes(c, tint, rough)

# ----------------------------------------------------------- kit furniture
const SCIFI_DIR := "res://assets/scifi/"
var _kit_cache := {}

func _kit_avail() -> bool:
	return FileAccess.file_exists(ProjectSettings.globalize_path(SCIFI_DIR + "Chair_1.glb"))

func _kit(room: Node3D, model: String, lpos: Vector3, roty := 0.0, s := 1.0) -> void:
	_kit_node(room, model, lpos, roty, Vector3.ONE * s)

func _kit_node(room: Node3D, model: String, lpos: Vector3, roty: float, sv: Vector3) -> Node3D:
	if not _kit_cache.has(model):
		var doc := GLTFDocument.new(); var st := GLTFState.new()
		var path := ProjectSettings.globalize_path(SCIFI_DIR + model + ".glb")
		_kit_cache[model] = doc.generate_scene(st) if doc.append_from_file(path, st) == OK else null
	var proto = _kit_cache[model]
	if proto == null: return null
	var inst: Node3D = proto.duplicate()
	inst.position = lpos; inst.rotation_degrees = Vector3(0, roty, 0); inst.scale = sv
	room.add_child(inst)
	return inst

## Per-room hero furniture (kit when present, else simple blocks). All LOCAL to
## the cell centre so it rides the container when rooms swap.
func _furnish(room: Node3D, kind: String, accent: String) -> void:
	var kit := _kit_avail()
	# the four quadrant anchor spots (clear of the central plus-corridor + doors)
	var nw := Vector3(-3.0, 0, -2.5); var ne := Vector3(3.0, 0, -2.5)
	var sw := Vector3(-3.0, 0, 2.4); var se := Vector3(3.0, 0, 2.4)
	match kind:
		"exec":
			# CEO sits at the BACK of the room facing the office front (+Z): the
			# command console is the desk (its screen faces the floor), and the
			# chair sits behind it so the CEO oversees the room. Director desk (NE);
			# orrery in a front corner.
			var ceo_p := Vector3(-2.6, 0, -1.6)
			if kit:
				# the command console IS the desk — its open side + screens face the
				# room (+Z). The CEO chair sits behind the console's back, facing the
				# room front (+Z), so the CEO oversees the floor.
				_kit(room, "Command_Console", ceo_p, 0.0, 0.5)
				_kit(room, "Chair_1", ceo_p + Vector3(0, 0, -1.4), 0.0, 0.62)
			else:
				room.add_child(_box(ceo_p + Vector3(0, 0.4, 0), Vector3(1.7, 0.8, 0.7), _m("23303f", 0.5)))
			_desk_pod(room, ne, 180.0, kit)
			if kit:
				_kit(room, "Orrery", sw, 0.0, 0.35)
		"ops":
			# six desk pods on the six ops anchors (back row of 4, front pair)
			for sp in [Vector3(-4.0, 0, -2.5), Vector3(-2.0, 0, -2.5), Vector3(2.0, 0, -2.5),
					Vector3(4.0, 0, -2.5), Vector3(-2.5, 0, 2.4), Vector3(2.5, 0, 2.4)]:
				_desk_pod(room, sp, 180.0, kit)   # all face the front (+Z), like the CEO
		"server":
			# racks down both side walls (clear of the side doors at z=0), a glowing
			# data core the server-agent tends, generators in a front corner
			var rc := ["55ff9e", "4ec3ff", "ffd24a", "ff6a8a"]
			for i in 2:
				_server_rack(room, Vector3(-4.4, 0, -2.6 + i * 5.0), 90.0, rc[i])
				_server_rack(room, Vector3(4.4, 0, -2.6 + i * 5.0), -90.0, rc[i + 2])
			_holo_core(room, Vector3(0, 0, 0), accent)
			if kit:
				_kit(room, "Generator", sw, 0.0, 0.5)
				_kit(room, "Battery_Blue", se, 0.0, 0.7)
		"meeting":
			# central table is the gather point (not a doorway) — seats in quadrants
			if kit:
				_kit(room, "Octo_Table", Vector3(0, 0, 0), 0.0, 0.5)
				# Chair_1 faces +Z at 0°; angle each corner seat to look at the centre
				# table: roty = atan2(dx, dz) toward (0,0).
				_kit(room, "Chair_1", nw, 50.0, 0.6); _kit(room, "Chair_1", ne, -50.0, 0.6)
				_kit(room, "Chair_1", sw, 129.0, 0.6); _kit(room, "Chair_1", se, -129.0, 0.6)
			else:
				room.add_child(_box(Vector3(0, 0.4, 0), Vector3(2.0, 0.8, 2.0), _m("241d30", 0.5)))
		"cafe":
			room.add_child(_box(Vector3(-4.4, 0.5, -2.5), Vector3(1.6, 1.0, 0.9), _m("2a1d10", 0.5)))   # counter (NW corner)
			for tp in [sw, ne]:
				if kit:
					_kit(room, "Cafeteria_Table", tp, 0.0, 0.8)
					_kit(room, "Chair_1", tp + Vector3(0.85, 0, 0), -90.0, 0.55)
					_kit(room, "Chair_1", tp + Vector3(-0.85, 0, 0), 90.0, 0.55)
				else:
					room.add_child(_box(tp + Vector3(0, 0.4, 0), Vector3(1.0, 0.8, 1.0), _m("3a2a18", 0.5)))
		"dorm":
			_bunk(room, nw, "Blue", kit); _bunk(room, ne, "Red", kit)
			# (no plant — kept out of the office per design)
		"dormx":
			# six bunks on the six dormx anchors
			var cols := ["Blue", "Green", "Orange", "Purple", "Red", "Grey"]
			var spots := [Vector3(-4.0, 0, -2.5), Vector3(-2.0, 0, -2.5), Vector3(2.0, 0, -2.5),
				Vector3(4.0, 0, -2.5), Vector3(-2.5, 0, 2.4), Vector3(2.5, 0, 2.4)]
			for i in spots.size(): _bunk(room, spots[i], cols[i], kit)
		"rec":
			if kit:
				_kit(room, "Large_Monitor_White", nw, 90.0, 0.5)
				_kit(room, "Cafeteria_Table", se, 0.0, 0.8)
				_kit(room, "3D_Chess_Board", se + Vector3(0, 0.62, 0), 15.0, 0.35)
				_kit(room, "Hydroponics_Full", ne, 0.0, 0.8)
			else:
				room.add_child(_box(nw + Vector3(0, 0.6, 0), Vector3(0.2, 1.2, 1.6), _m("101418", 0.3)))
		"lobby":
			room.add_child(_box(se + Vector3(0, 1.2, 0), Vector3(0.5, 2.4, 0.5), _m("1a2025", 0.3, "ff2a20", 1.6)))  # totem (corner)
			room.add_child(_box(nw + Vector3(0, 0.5, 0), Vector3(1.8, 1.0, 0.7), _m("2a1d18", 0.5)))                 # reception
			room.add_child(_box(sw + Vector3(0, 0.35, 0), Vector3(0.9, 0.7, 0.9), _m("203038", 0.5)))               # armchair
			if kit:
				_kit(room, "End_Table", ne, 0.0, 0.8)
				_kit(room, "3D_Chess_Board", ne + Vector3(0, 0.75, 0), 25.0, 0.35)

## A desk pod: desk box + monitor + chair, facing roty (180 = faces +z/front).
func _desk_pod(room: Node3D, pos: Vector3, roty: float, kit: bool) -> void:
	# Workstation: desk + monitor whose SCREEN faces the room (+Z), and the chair
	# in FRONT of the desk (south, SEAT_DZ) facing the screen (-Z). The agent's
	# home anchor sits on that chair, so it perches in front of the desk (not
	# hidden behind it) with its back to the camera, working at the glowing screen.
	room.add_child(_box(pos + Vector3(0, 0.4, 0), Vector3(1.4, 0.8, 0.7), _m("23303f", 0.5)))
	if kit:
		_kit(room, "Large_Monitor_Blue", pos + Vector3(0, 0.8, 0.05), 0.0, 0.24)   # screen faces +Z (toward the seat)
		_kit(room, "Chair_1", pos + Vector3(0, 0, SEAT_DZ), 180.0, 0.55)            # chair in front, faces the screen (-Z)

## A single bunk (kit when present, else a block).
func _bunk(room: Node3D, pos: Vector3, color: String, kit: bool) -> void:
	if kit:
		_kit(room, "Bunk_Single_" + color, pos, 0.0, 0.7)
	else:
		room.add_child(_box(pos + Vector3(0, 0.3, 0), Vector3(1.0, 0.5, 1.8), _m("2a2d3a", 0.6)))

## A blinking server rack: dark cabinet + a stack of glowing LED strips.
func _server_rack(room: Node3D, pos: Vector3, roty: float, color: String) -> void:
	var rack := Node3D.new(); rack.position = pos; rack.rotation_degrees = Vector3(0, roty, 0)
	room.add_child(rack)
	rack.add_child(_box(Vector3(0, 0.9, 0), Vector3(0.8, 1.8, 0.55), _m("10141c", 0.5)))
	var led := _m(color, 0.3, color, 2.2)
	for i in 7:
		rack.add_child(_box(Vector3(0, 0.34 + i * 0.22, 0.29), Vector3(0.62, 0.07, 0.03), led))

## A holographic data core: glowing translucent cone + a pad + a light.
func _holo_core(room: Node3D, pos: Vector3, accent: String) -> void:
	room.add_child(_box(pos + Vector3(0, 0.05, 0), Vector3(1.1, 0.1, 1.1), _m("0a0e16", 0.4)))
	var holo := MeshInstance3D.new()
	var cyl := CylinderMesh.new(); cyl.top_radius = 0.06; cyl.bottom_radius = 0.5; cyl.height = 1.7
	holo.mesh = cyl
	var hm := _m(accent, 0.1, accent, 1.8); hm.albedo_color.a = 0.38
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	holo.material_override = hm; holo.position = pos + Vector3(0, 1.05, 0)
	room.add_child(holo)
	var l := OmniLight3D.new(); l.light_color = Color(accent); l.light_energy = 1.3; l.omni_range = 4.0
	l.position = pos + Vector3(0, 1.3, 0); room.add_child(l)

func _m(hex: String, rough := 0.8, emit := "", emit_e := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex); m.roughness = rough
	if emit != "":
		m.emission_enabled = true; m.emission = Color(emit); m.emission_energy_multiplier = emit_e
	return m

func _box(pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size
	mi.mesh = bm; mi.material_override = mat; mi.position = pos
	return mi
