extends RefCounted
## One-shot pixel-FX flipbooks ("Super Pixel Effects Gigapack" by untiedgames,
## license: bundling OK / no redistribution — assets gitignored, see README).
## Sheets are horizontal strips of square frames played at the pack's
## canonical 15 fps; the sprite frees itself when the animation ends.

const DIR := "res://assets/pixelfx/"
const FPS := 15.0

static var _cache := {}

static func has_assets() -> bool:
	return FileAccess.file_exists(DIR + "success.png")

static func _tex(name: String) -> ImageTexture:
	if _cache.has(name):
		return _cache[name]
	var path := ProjectSettings.globalize_path(DIR + name + ".png")
	var img := Image.load_from_file(path)
	if img == null:
		_cache[name] = null
		return null
	var tex := ImageTexture.create_from_image(img)
	_cache[name] = tex
	return tex

## Spawn an effect as a child of `parent` at a local offset. Frame size is
## square, so frames = width / height. pixel size 0.02 → a 40px symbol
## reads ~0.8 m in world.
static func spawn(parent: Node3D, name: String, offset: Vector3,
		ppm := 0.02, loops := 1) -> void:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var tex := _tex(name)
	if tex == null:
		return
	var frames := int(float(tex.get_width()) / float(tex.get_height()))
	var s := Sprite3D.new()
	s.texture = tex
	s.hframes = frames
	s.vframes = 1
	s.frame = 0
	s.pixel_size = ppm
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.layers = 2  # never on the static map render
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.render_priority = 10
	parent.add_child(s)
	s.position = offset
	var tw := s.create_tween()
	tw.set_loops(loops)
	tw.tween_property(s, "frame", frames - 1, frames / FPS).from(0)
	tw.finished.connect(s.queue_free)
