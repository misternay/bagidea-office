extends Node
## Procedural sound effects (autoload "Sfx") — tiny synthesized WAVs, no
## audio assets needed. Cute blips and chimes for office life; the master
## toggle lives in the overlay settings (ui.sound / registry).

var enabled := true

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _last_play := {}  # name -> ticks ms (rate limiting)

func _ready() -> void:
	_streams = {
		"blip": _tone(660.0, 0.07, 22.0),            # soft message tick
		"blip2": _tone(880.0, 0.09, 18.0),           # cute interaction
		"chime": _chord([1046.5, 1318.5], 0.34, 9.0),  # task done — major third
		"ding": _chord([1568.0], 0.3, 8.0),          # approval bell
		"buzz": _tone(165.0, 0.22, 10.0, "square"),  # failure / denied
		"whoosh": _tone(0.0, 0.3, 9.0, "noise"),     # ghost in/out
		"pop": _tone(240.0, 0.07, 30.0),             # ball kick
		"tada": _chord([784.0, 988.0, 1175.0], 0.5, 6.0),  # skill learned
	}
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.volume_db = -10.0
		p.bus = "Master"
		add_child(p)
		_pool.append(p)

## Fire-and-forget with a touch of pitch variance; per-sound rate limit so
## a chatty office never machine-guns the speakers.
func play(p_name: String, min_gap_ms := 120) -> void:
	if not enabled or not _streams.has(p_name):
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
