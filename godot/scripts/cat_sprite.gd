extends Sprite3D
## The office cat 🐱 — xzany "Cat 2D Pixel Art" (free pack; gitignored, no
## redistribution as an asset). Wanders the recreation room, and idle agents
## can call it over to play. world_builder falls back to the procedural dog
## when the pack is missing, so clones still run.

const DIR := "res://assets/characters/cat/Sprites/"
## Wander area (the recreation room — same range the dog used).
const ROAM := Rect2(-9.2, 6.8, 11.4, 5.6)
const SPEED := 1.1
const RUN_SPEED := 2.7

static func has_assets() -> bool:
	return FileAccess.file_exists(ProjectSettings.globalize_path(DIR + "IDLE.png"))

var _anims := {}  # name -> {tex, frames}
var _anim := ""
var _frame_t := 0.0
var _tween: Tween
var _moving := false
var _busy_until := 0.0  # play sessions pause the roam loop

func _ready() -> void:
	layers = 2  # moving prop — keep it off the static map render
	# 80x64 cells in single-row strips (runtime-loaded: assets are gitignored).
	for spec in [["idle", "IDLE", 8], ["walk", "WALK", 12], ["run", "RUN", 8]]:
		var img := Image.load_from_file(ProjectSettings.globalize_path(DIR + str(spec[1]) + ".png"))
		if img:
			_anims[spec[0]] = {"tex": ImageTexture.create_from_image(img), "frames": int(spec[2])}
	pixel_size = 0.02
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	shaded = true
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	offset.y = 26.0  # feet on the node's floor line
	_play("idle")
	_roam_loop()

func _play(p_name: String) -> void:
	if _anim == p_name or not _anims.has(p_name):
		return
	_anim = p_name
	var a: Dictionary = _anims[p_name]
	texture = a.tex
	hframes = a.frames
	frame = 0

func _roam_loop() -> void:
	while is_inside_tree():
		await get_tree().create_timer(randf_range(2.0, 6.5)).timeout
		if not is_inside_tree():
			return
		if Time.get_ticks_msec() / 1000.0 < _busy_until:
			continue
		var target := Vector3(
			randf_range(ROAM.position.x, ROAM.position.x + ROAM.size.x),
			position.y,
			randf_range(ROAM.position.y, ROAM.position.y + ROAM.size.y))
		_move_to(target, SPEED, "walk")

func _move_to(target: Vector3, speed: float, anim: String) -> void:
	flip_h = target.x > position.x  # art faces left
	_play(anim)
	_moving = true
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "position", target, position.distance_to(target) / speed)
	_tween.finished.connect(func() -> void:
		_moving = false
		_play("idle"))

## An idle agent calls the cat over: it RUNS to them and hangs out a while.
func attend(pos: Vector3, seconds := 6.0) -> void:
	_busy_until = Time.get_ticks_msec() / 1000.0 + seconds + 2.0
	_move_to(Vector3(pos.x + 0.45, position.y, pos.z + 0.3), RUN_SPEED, "run")

func _process(delta: float) -> void:
	if not _anims.has(_anim):
		return
	_frame_t += delta
	var fps := 12.0 if _moving else 7.0
	if _frame_t >= 1.0 / fps:
		_frame_t = 0.0
		frame = (frame + 1) % hframes
