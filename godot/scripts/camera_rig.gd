extends Node3D
## Orbit-style camera rig: long lens + slight tilt for the HD-2D diorama look.
## Subtle idle drift sells the "living wallpaper" feel.

@export var target := Vector3(0.0, 0.9, -1.5)
@export var yaw := -16.0
@export var pitch := -30.0
@export var distance := 14.5
@export var drift := true

var _t := 0.0

func _ready() -> void:
	position = target
	rotation_degrees = Vector3(pitch, yaw, 0.0)
	$Camera3D.position = Vector3(0.0, 0.0, distance)

func _process(delta: float) -> void:
	if not drift:
		return
	_t += delta * 0.07
	rotation_degrees.y = yaw + sin(_t) * 2.5
	$Camera3D.position.z = distance + sin(_t * 0.6) * 0.6
