extends Node3D
## Root controller for the Executive Office visual target.
## Sets up light/screen angles and handles automated screenshots (--shot).

const BEAM_SHADER := preload("res://shaders/light_beam.gdshader")

func _ready() -> void:
	# Sun comes from the north windows, slanting down into the room.
	$Sun.rotation_degrees = Vector3(-46.0, 150.0, 0.0)
	# Angle the side holo-screens toward the desk.
	$Geometry/ScreenL.rotation_degrees.y = 28.0
	$Geometry/ScreenR.rotation_degrees.y = -28.0
	# Fake god-ray cards anchored to the two windows.
	_add_beam(-2.5)
	_add_beam(2.5)

	if "--shot" in OS.get_cmdline_user_args():
		_take_shot()

	if "--wallpaper" in OS.get_cmdline_user_args():
		# Borderless, covering the primary screen — the attach script then
		# re-parents this window into the desktop's WorkerW layer.
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		DisplayServer.window_set_position(Vector2i.ZERO)
		DisplayServer.window_set_size(DisplayServer.screen_get_size())
		# Wallpaper rung: 30 fps + upscaled 0.75x render — wallpaper must be
		# nearly free while the user works.
		Engine.max_fps = 30
		get_viewport().scaling_3d_scale = 0.75

func _add_beam(x: float) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.3, 5.0)
	var mat := ShaderMaterial.new()
	mat.shader = BEAM_SHADER
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	$Geometry.add_child(mi)
	# Slab leaning from the window head down to the floor light pool.
	mi.position = Vector3(x - 0.5, 1.5, -2.3)
	mi.rotation_degrees = Vector3(-48.0, -14.0, 0.0)
	(mi.material_override as ShaderMaterial).set_shader_parameter("strength", 0.35)
	return mi

func _take_shot() -> void:
	# Let fog/particles/exposure settle, then capture one frame and quit.
	await get_tree().create_timer(2.5).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := ProjectSettings.globalize_path("res://").path_join("../shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("executive_office.png")
	img.save_png(path)
	print("screenshot saved: ", path)
	get_tree().quit()
