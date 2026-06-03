extends Node3D
## Orbit camera rig v2: long lens, wide diorama framing, and a living
## multi-axis drift (slow Lissajous on yaw/pitch/distance plus a gentle
## target sway) so the wallpaper never feels frozen.

@export var target := Vector3(-0.5, 0.4, -2.8)
@export var yaw := -12.0
@export var pitch := -32.0
@export var distance := 33.0
@export var drift := true
## 0 = static, 1 = default cinematic drift, 2 = dramatic.
@export var drift_amount := 1.0

var _t := 0.0

@onready var _cam: Camera3D = $Camera3D

func _ready() -> void:
	position = target
	rotation_degrees = Vector3(pitch, yaw, 0.0)
	_cam.position = Vector3(0.0, 0.0, distance)

func _process(delta: float) -> void:
	if not drift or drift_amount <= 0.0:
		return
	_t += delta
	var a := drift_amount
	# Different prime-ish periods per axis → the path never visibly repeats.
	rotation_degrees.y = yaw + sin(_t * 0.060) * 5.0 * a
	rotation_degrees.x = pitch + sin(_t * 0.037 + 1.7) * 2.0 * a
	_cam.position.z = distance + sin(_t * 0.047 + 0.6) * 2.6 * a
	position = target + Vector3(
		sin(_t * 0.027) * 1.1 * a,
		sin(_t * 0.051 + 0.9) * 0.15 * a,
		cos(_t * 0.033) * 0.8 * a)
