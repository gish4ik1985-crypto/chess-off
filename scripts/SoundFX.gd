extends AudioStreamPlayer
class_name SoundFX

# Fully procedural short sound effects (no audio files). Piece moves are
# synthesized as wooden "knocks": a fast-decaying low resonant thump with a
# tiny noise transient — like a wooden piece landing on a wooden board —
# with slight random pitch variation so no two moves sound identical.
# Check/result stay as soft tonal chimes. Volume follows Global.sfx_volume.

# В вебе (планшет, телефон) 44.1 кГц синтезом по отсчётам не вытянуть — звук хрипит; см. MusicPlayer.
var MIX_RATE := 22050.0 if OS.has_feature("web") else 44100.0
const MAX_FRAMES_PER_CALL := 4096
const IDLE_SECONDS := 0.3 # сколько тишины дописать после последнего звука, затем перестать кормить буфер

# Selectable flavours of the piece-move knock (Global.move_sound_style).
# freq: base pitch range; decay: how fast the thump dies (higher = drier);
# click: strength of the contact transient; partial: upper "woody" overtone;
# dur: total length. Capture reuses the style with a sharper first hit.
const MOVE_STYLES := [
	{"name": "Дерево — глубокий стук", "freq_lo": 110.0, "freq_hi": 140.0, "decay": 26.0, "click": 0.25, "partial": 0.30, "dur": 0.16},
	{"name": "Дерево — звонкий стук", "freq_lo": 200.0, "freq_hi": 255.0, "decay": 40.0, "click": 0.55, "partial": 0.50, "dur": 0.12},
	{"name": "Лёгкий щелчок", "freq_lo": 300.0, "freq_hi": 380.0, "decay": 70.0, "click": 0.90, "partial": 0.20, "dur": 0.07},
	{"name": "Мягкий войлок", "freq_lo": 80.0, "freq_hi": 105.0, "decay": 20.0, "click": 0.06, "partial": 0.12, "dur": 0.18},
]

var playback: AudioStreamGeneratorPlayback
var _tones: Array = [] # queue of {kind, freq, dur, wave_mix}
var _phase := 0.0
var _time_in_tone := 0.0
var _rng := RandomNumberGenerator.new()
var _idle_time := 0.0

func _ready() -> void:
	bus = "Master"
	volume_db = -8.0
	stream = AudioStreamGenerator.new()
	stream.mix_rate = MIX_RATE
	stream.buffer_length = 0.2
	_rng.randomize()

func _style() -> Dictionary:
	return MOVE_STYLES[clampi(Global.move_sound_style, 0, MOVE_STYLES.size() - 1)]

func _knock(st: Dictionary, pitch_scale: float, dur_scale: float) -> Dictionary:
	return {
		"kind": "knock",
		"freq": _rng.randf_range(st.freq_lo, st.freq_hi) * pitch_scale,
		"dur": st.dur * dur_scale,
		"decay": st.decay,
		"click": st.click,
		"partial": st.partial,
	}

func play_move() -> void:
	# single tap in the chosen style, pitch varies a little every time
	_queue([_knock(_style(), 1.0, 1.0)])

func play_capture() -> void:
	# piece clacks against piece (higher, shorter), then settles on the board
	var st = _style()
	_queue([_knock(st, 1.6, 0.6), _knock(st, 0.9, 1.1)])

func play_check() -> void:
	_queue([{"kind": "tone", "freq": 660.0, "dur": 0.06, "wave_mix": 0.2}, {"kind": "tone", "freq": 880.0, "dur": 0.09, "wave_mix": 0.2}])

func play_result(win: bool) -> void:
	if win:
		_queue([{"kind": "tone", "freq": 523.25, "dur": 0.1, "wave_mix": 0.3}, {"kind": "tone", "freq": 659.25, "dur": 0.1, "wave_mix": 0.3}, {"kind": "tone", "freq": 783.99, "dur": 0.18, "wave_mix": 0.3}])
	else:
		_queue([{"kind": "tone", "freq": 392.0, "dur": 0.12, "wave_mix": 0.5}, {"kind": "tone", "freq": 261.63, "dur": 0.2, "wave_mix": 0.5}])

func _queue(tones: Array) -> void:
	if not Global.sound_on or Global.sfx_volume <= 0.0:
		return
	volume_db = linear_to_db(clampf(Global.sfx_volume, 0.01, 1.0)) - 4.0
	_tones = tones
	_time_in_tone = 0.0
	_idle_time = 0.0
	if not is_playing():
		play()
	playback = get_stream_playback()
	_fill_buffer()

func _process(_delta: float) -> void:
	if playback == null:
		return
	_fill_buffer()

func _fill_buffer() -> void:
	if playback == null:
		return
	var to_fill = mini(playback.get_frames_available(), MAX_FRAMES_PER_CALL)
	var dt = 1.0 / MIX_RATE
	if _tones.is_empty():
		# раньше тишина гналась в буфер без конца, отсчёт за отсчётом, — это и грузило процессор
		_idle_time += to_fill * dt
		if _idle_time >= IDLE_SECONDS:
			stop()
			playback = null
			return
	var chunk := PackedVector2Array()
	chunk.resize(to_fill)
	for i in range(to_fill):
		if _tones.is_empty():
			continue
		var tone = _tones[0]
		_time_in_tone += dt
		if _time_in_tone >= tone.dur:
			_time_in_tone = 0.0
			_tones.pop_front()
			continue
		var t: float = _time_in_tone
		var s := 0.0
		if tone.get("kind", "tone") == "knock":
			# percussive thump: sharp exponential decay, slight downward
			# pitch bend (wood "gives" a little), plus a short noise click
			var env = exp(-t * tone.get("decay", 34.0))
			var freq = tone.freq * (1.0 - 0.25 * (t / tone.dur))
			_phase += freq * dt
			if _phase > 1.0:
				_phase -= 1.0
			var body = sin(TAU * _phase)
			# second partial an octave-and-a-bit up gives it woodiness
			var partial = sin(TAU * _phase * 2.4) * tone.get("partial", 0.35)
			var click = (_rng.randf() * 2.0 - 1.0) * exp(-t * 400.0) * tone.get("click", 0.5)
			s = (body + partial) * env * 0.55 + click
		else:
			var env = sin(PI * clampf(t / tone.dur, 0.0, 1.0))
			env = env * env
			_phase += tone.freq * dt
			if _phase > 1.0:
				_phase -= 1.0
			var sine_v = sin(TAU * _phase)
			var tri_v = 1.0 - 4.0 * abs(fmod(_phase + 0.75, 1.0) - 0.5)
			s = lerp(sine_v, tri_v, tone.get("wave_mix", 0.0)) * env * 0.5
		s = clampf(s, -1.0, 1.0)
		chunk[i] = Vector2(s, s)
	if to_fill > 0:
		playback.push_buffer(chunk)
