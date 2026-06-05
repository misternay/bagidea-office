extends CSGSphere3D
## The recreation football ⚽ — gets "kicked" around its corner of the rec
## room in lazy arcs forever. Ambient life, zero events.

const AREA := Rect2(-3.4, 9.0, 3.4, 3.2)  # x, z, w, d
const KICK_SPEED := 4.5

var _rolling := 0.0

func _ready() -> void:
	layers = 2  # moving prop — keep it off the static map render
	_kick_loop()

func _process(delta: float) -> void:
	# The texture sells the kick: spin while airborne, settle when resting.
	if _rolling > 0.0:
		_rolling -= delta
		rotate_x(-delta * 7.0)
		rotate_z(delta * 2.4)

## One immediate kick — idle agents playing football call this.
func kick_now() -> void:
	_do_kick()

func _kick_loop() -> void:
	while is_inside_tree():
		await get_tree().create_timer(randf_range(2.5, 7.0)).timeout
		if not is_inside_tree():
			return
		await _do_kick()

func _do_kick() -> void:
	var target := Vector3(
		randf_range(AREA.position.x, AREA.position.x + AREA.size.x),
		position.y,
		randf_range(AREA.position.y, AREA.position.y + AREA.size.y))
	var dur: float = maxf(position.distance_to(target) / KICK_SPEED, 0.25)
	_rolling = dur
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "position:x", target.x, dur)
	tw.tween_property(self, "position:z", target.z, dur)
	# arc: up then down
	tw.set_parallel(false)
	var base_y := position.y
	tw.tween_property(self, "position:y", base_y, 0.0)
	var arc := create_tween()
	arc.tween_property(self, "position:y", base_y + 0.7, dur * 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	arc.tween_property(self, "position:y", base_y, dur * 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
