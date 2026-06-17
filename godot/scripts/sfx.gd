extends Node
## Sound effects (autoload "Sfx"). Prefers the real "(Not A Placeholder)
## Free Sounds Pack" WAVs (gitignored — see README); falls back to tiny
## synthesized tones when the pack is missing. Master toggle lives in the
## overlay settings (ui.sound / registry).

const PACK := "res://assets/sounds/"
## name -> pack file (crisp, short picks — interesting, never annoying).
const PACK_MAP := {
	"blip": "Interface 1-1.wav",            # message tick
	"blip2": "Interface 3-3.wav",           # cute interaction
	"chime": "Magical Interface 5-1.wav",   # task done
	"ding": "Sci-Fi Interface 8-1.wav",     # approval bell
	"buzz": "Hit Generic 5-1.wav",          # failure / denied
	"whoosh": "Whoosh 4-1.wav",             # ghost in/out
	"pop": "Hit Generic 2-1.wav",           # ball kick
	"tada": "Special Collectible 9-1.wav",  # skill learned / fanfare
	"door_in": "Door Open 4-1.wav",         # someone walks in / wakes
	"door_out": "Door Close 4-1.wav",       # off to the bunks
	"page": "Book Page 1-2.wav",            # notes & paperwork
	"split": "Fire Whoosh 2-15.wav",        # 💥 the clone burst
	"boom": "Explosion Large 1-1.wav",      # 💥 server-room blast (the big one)
	"boom2": "Explosion Medium 2-1.wav",    # 💥 the second, smaller pop
	"fire": "Fire Burning Loop 2.wav",      # 🔥 crackle as the room catches
}

var enabled := true
var hidden := false  # office hidden → everything stays silent (setting untouched)

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _last_play := {}  # name -> ticks ms (rate limiting)
var _loops := {}      # name -> dedicated AudioStreamPlayer for SUSTAINED sounds

func _ready() -> void:
	# Synth fallbacks first, then the real pack overrides what it can.
	_streams = {
		"blip": _tone(660.0, 0.07, 22.0),
		"blip2": _tone(880.0, 0.09, 18.0),
		"chime": _chord([1046.5, 1318.5], 0.34, 9.0),
		"ding": _chord([1568.0], 0.3, 8.0),
		"buzz": _tone(165.0, 0.22, 10.0, "square"),
		"whoosh": _tone(0.0, 0.3, 9.0, "noise"),
		"pop": _tone(240.0, 0.07, 30.0),
		"tada": _chord([784.0, 988.0, 1175.0], 0.5, 6.0),
		"door_in": _tone(330.0, 0.12, 14.0),
		"door_out": _tone(262.0, 0.12, 14.0),
		"page": _tone(0.0, 0.08, 26.0, "noise"),
		"split": _tone(0.0, 0.4, 7.0, "noise"),
	}
	for key in PACK_MAP:
		var path := ProjectSettings.globalize_path(PACK + PACK_MAP[key])
		if FileAccess.file_exists(path):
			var wav := AudioStreamWAV.load_from_file(path)
			if wav:
				_streams[key] = wav
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.volume_db = -11.0
		p.bus = "Master"
		add_child(p)
		_pool.append(p)

## Fire-and-forget with a touch of pitch variance; per-sound rate limit so
## a chatty office never machine-guns the speakers.
func play(p_name: String, min_gap_ms := 120) -> void:
	if not enabled or hidden or not _streams.has(p_name):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(p_name, -99999)) < min_gap_ms:
		return
	_last_play[p_name] = now
	for p in _pool:
		if not p.playing:
			p.stream = _streams[p_name]
			p.pitch_scale = randf_range(0.96, 1.05)
			p.play()
			return

## Start a SUSTAINED/looping sound on its own dedicated player (e.g. the server-room
## fire crackle). Must be paired with stop_loop() — a looping stream on the fire-and-
## forget pool would play forever AND wedge a pool slot (it never reads `not playing`).
func loop(p_name: String) -> void:
	if not enabled or hidden or not _streams.has(p_name):
		return
	if _loops.has(p_name) and is_instance_valid(_loops[p_name]):
		return  # already running
	var st = _streams[p_name]
	# Force a clean forward loop if the asset didn't carry loop metadata.
	if st is AudioStreamWAV and st.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		st = st.duplicate()
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = st.data.size() / (4 if st.stereo else 2)  # 16-bit frames
	var p := AudioStreamPlayer.new()
	p.volume_db = -11.0
	p.bus = "Master"
	p.stream = st
	add_child(p)
	p.play()
	_loops[p_name] = p

## Stop a sustained sound started with loop(). Safe to call when nothing's playing.
func stop_loop(p_name: String) -> void:
	var p = _loops.get(p_name)
	if is_instance_valid(p):
		p.stop()
		p.queue_free()
	_loops.erase(p_name)

## One decaying tone (sine / square / noise) as a 16-bit 22 kHz WAV.
func _tone(freq: float, dur: float, decay: float, kind := "sine") -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * decay) * minf(t * 240.0, 1.0)  # tiny attack, no click
		var v: float
		match kind:
			"noise":
				v = randf_range(-1.0, 1.0) * 0.6
			"square":
				v = signf(sin(TAU * freq * t)) * 0.45
			_:
				v = sin(TAU * freq * t)
		data.encode_s16(i * 2, int(clampf(v * env, -1.0, 1.0) * 30000.0))
	return _wav(data, rate)

## A few stacked sines — chimes and the little fanfare.
func _chord(freqs: Array, dur: float, decay: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * decay) * minf(t * 240.0, 1.0)
		var v := 0.0
		for k in freqs.size():
			# Later notes enter slightly later — an arpeggiated sparkle.
			var on_at := 0.05 * k
			if t >= on_at:
				v += sin(TAU * float(freqs[k]) * (t - on_at)) * exp(-(t - on_at) * decay)
		v /= float(freqs.size())
		data.encode_s16(i * 2, int(clampf(v * env * 1.6, -1.0, 1.0) * 30000.0))
	return _wav(data, rate)

func _wav(data: PackedByteArray, rate: int) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav
