extends SceneTree
## Dev probe: prints the real AABB of kit models so placement math is
## measured, not guessed. Run:
##   godot --headless --path godot --script res://scripts/probe.gd

const MODELS := [
	"Wall_Grey", "Wall_Glass_Clear", "Chair_1", "Command_Console",
	"Cafeteria_Table", "Meeting_Table", "Briefing_Screen_Blue",
	"Large_Monitor_Blue", "Plant_1", "Floor_Lamp", "Orrery",
	"Floor_Tile_Carpet_Blue", "End_Table", "Lava_Lamp", "Ceiling_Light",
]

func _init() -> void:
	for name in MODELS:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var path := ProjectSettings.globalize_path("res://assets/scifi/%s.glb" % name)
		if doc.append_from_file(path, state) != OK:
			print(name, "  LOAD FAILED")
			continue
		var scene := doc.generate_scene(state)
		var aabb := _merge_aabb(scene, Transform3D.IDENTITY)
		print("%s  size=%v  origin=%v" % [name, aabb.size, aabb.position])
		scene.free()
	quit()

func _merge_aabb(node: Node, xf: Transform3D) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array = [[node, xf]]
	while stack.size() > 0:
		var item: Array = stack.pop_back()
		var n: Node = item[0]
		var t: Transform3D = item[1]
		if n is Node3D:
			t = t * (n as Node3D).transform
		if n is MeshInstance3D:
			var ab: AABB = t * (n as MeshInstance3D).get_aabb()
			if first:
				result = ab
				first = false
			else:
				result = result.merge(ab)
		for c in n.get_children():
			stack.append([c, t])
	return result
