extends Sprite3D
## Pixel-art agent v2, generated at runtime: 16x24 with outline + shading and
## a 2-frame walk cycle. Billboarded + shaded so the sprite is lit by the 3D
## scene (HD-2D core trick). Real art assets will replace ART later — the
## node API (walk_to / set_status) is what the rest of the game depends on.

@export var suit_color := Color8(38, 46, 76)
@export var hair_color := Color8(52, 38, 30)
@export var skin_color := Color8(236, 188, 152)
@export var tie_color := Color8(168, 52, 58)

const WALK_SPEED := 1.6   # m/s
const FRAME_TIME := 0.16  # walk-cycle frame swap

# Keys: o=outline h=hair H=hair shine f=skin F=skin shade e=eye
#       s=suit S=suit shade w=shirt t=tie p=pants b=shoes .=transparent
const ART_IDLE: Array[String] = [
	"................",
	".....oooo.......",
	"....ohhhho......",
	"...ohHhhhho.....",
	"...ohhhhhho.....",
	"...offffffo.....",
	"...ofeffefo.....",
	"...offffffo.....",
	"....oFFFFo......",
	"...oswwwwso.....",
	"..osswttwsso....",
	"..osswttwsso....",
	"..ossswwssso....",
	"..osssssssso....",
	"..ofssssssfo....",
	"...oSSSSSSo.....",
	"...oppppppo.....",
	"...oppppppo.....",
	"...oppo.oppo....",
	"...oppo.oppo....",
	"...oppo.oppo....",
	"..obbbo.obbbo...",
	"................",
	"................",
]

# Stride frame: legs apart.
const ART_WALK: Array[String] = [
	"................",
	".....oooo.......",
	"....ohhhho......",
	"...ohHhhhho.....",
	"...ohhhhhho.....",
	"...offffffo.....",
	"...ofeffefo.....",
	"...offffffo.....",
	"....oFFFFo......",
	"...oswwwwso.....",
	"..osswttwsso....",
	"..osswttwsso....",
	"..ossswwssso....",
	"..osssssssso....",
	"..ofssssssfo....",
	"...oSSSSSSo.....",
	"...oppppppo.....",
	"..oppo..oppo....",
	"..oppo...oppo...",
	".oppo.....oppo..",
	".oppo.....oppo..",
	"obbbo......obbbo",
	"................",
	"................",
]

var idle_pos := Vector3.ZERO
var _label: Label3D
var _walk_tween: Tween
var _t := 0.0
var _bob_speed := 2.2
var _walking := false
var _frame_t := 0.0
var _frame := 0
var _tex_idle: ImageTexture
var _tex_walk: ImageTexture

func _ready() -> void:
	var colors := {
		"o": Color8(18, 16, 22),
		"h": hair_color,
		"H": hair_color.lightened(0.25),
		"f": skin_color,
		"F": skin_color.darkened(0.16),
		"e": Color8(40, 40, 48),
		"s": suit_color,
		"S": suit_color.darkened(0.3),
		"w": Color8(225, 228, 235),
		"t": tie_color,
		"p": suit_color.darkened(0.4),
		"b": Color8(24, 22, 28),
	}
	_tex_idle = _bake(ART_IDLE, colors)
	_tex_walk = _bake(ART_WALK, colors)
	texture = _tex_idle
	idle_pos = position
	_t = randf() * TAU

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 64
	_label.outline_size = 16
	_label.pixel_size = 0.004
	_label.position = Vector3(0, 1.05, 0)
	_label.modulate = Color(0.75, 0.95, 1.0)
	add_child(_label)

func _bake(art: Array[String], colors: Dictionary) -> ImageTexture:
	var w: int = art[0].length()
	var h: int = art.size()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var row := art[y]
		for x in w:
			var key := row[x]
			if colors.has(key):
				img.set_pixel(x, y, colors[key])
	return ImageTexture.create_from_image(img)

func _process(delta: float) -> void:
	# Idle bob via pixel offset so it never fights the walk tween on position.
	_t += delta * _bob_speed
	offset.y = sin(_t) * 0.15
	# Two-frame walk cycle while moving.
	if _walking:
		_frame_t += delta
		if _frame_t >= FRAME_TIME:
			_frame_t = 0.0
			_frame = 1 - _frame
			texture = _tex_walk if _frame == 1 else _tex_idle
	elif texture != _tex_idle:
		texture = _tex_idle

func set_status(text: String) -> void:
	_label.text = text

## Walk through waypoints (straight tween legs along the A* graph).
## Returns the total walk duration in seconds.
func walk_to(points: Array) -> float:
	if points.is_empty():
		return 0.0
	if _walk_tween:
		_walk_tween.kill()
	_walk_tween = create_tween()
	var from := position
	var total := 0.0
	for p in points:
		var leg_time: float = max(from.distance_to(p) / WALK_SPEED, 0.05)
		_walk_tween.tween_property(self, "position", p, leg_time)
		total += leg_time
		from = p
	_walking = true
	_bob_speed = 7.0
	_walk_tween.finished.connect(func():
		_bob_speed = 2.2
		_walking = false)
	return total
