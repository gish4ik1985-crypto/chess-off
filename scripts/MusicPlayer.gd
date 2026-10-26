extends AudioStreamPlayer
class_name MusicPlayer

# Fully procedural ambient background music — no audio files.
# Three gentle layers, all sine-based and deliberately calm:
#   1. a slow chord pad (I – vi – IV – V style progression over the region's
#      scale, three soft voices an octave down, swelling in and out),
#   2. a sparse melody over the same scale with rests and light vibrato,
#   3. a quiet sub-octave drone that "breathes".
# A soft feedback echo and slight stereo spread (pad left, melody right)
# make it feel spacious instead of beepy. Per-character params (root, scale,
# note_dur, drone_vol) keep every region's mood distinct.

# В браузере (планшет, телефон) синтез по отсчётам в одном потоке не успевает на 44.1 кГц — звук хрипит.
# Музыка мягкая (синусы), на 22 кГц звучит так же, а нагрузка вдвое меньше.
var MIX_RATE := 22050.0 if OS.has_feature("web") else 44100.0
# За один кадр дописываем не больше этого числа отсчётов: после «подвисания» не пытаемся
# разом нагнать всё и не создаём ещё большее подвисание.
const MAX_FRAMES_PER_CALL := 4096
const BUFFER_LEN := 0.5
const ECHO_SECONDS := 0.45
const ECHO_FEEDBACK := 0.35
const ECHO_MIX := 0.30

var playback: AudioStreamGeneratorPlayback

var root_freq := 261.63
var scale_semitones: Array = [0, 2, 4, 7, 9]
var note_dur := 1.6
var drone_vol := 0.05
var note_vol := 0.085
var pad_vol := 0.045

# melody: scale degrees, -1 = rest — phrases with breathing room
var pattern: Array = [0, 2, 4, -1, 3, 2, 1, -1, 0, 2, 5, 4, -1, 3, 1, -1]
# chord roots as scale degrees; voices stack every other scale step
var chord_roots: Array = [0, 4, 3, 1]

var _pattern_idx := 0
var _time_in_note := 0.0
var _melody_t := 0.0
# legato: each note is its own voice with a slow attack and a long release
# tail that overlaps the next note — a flowing line instead of separate tones
var _voices: Array = [] # {freq, phase, age}

var _chord_idx := 0
var _time_in_chord := 0.0
var _chord_dur := 6.4
var _pad_phases := [0.0, 0.0, 0.0]
var _pad_freqs := [130.0, 165.0, 196.0]

var _phase_drone := 0.0
var _phase_lfo := 0.0

var _echo_buf: PackedFloat32Array
var _echo_pos := 0

func _ready() -> void:
	bus = "Master"
	volume_db = -6.0
	stream = AudioStreamGenerator.new()
	stream.mix_rate = MIX_RATE
	stream.buffer_length = BUFFER_LEN
	_echo_buf = PackedFloat32Array()
	_echo_buf.resize(int(ECHO_SECONDS * MIX_RATE))

func start_theme(params: Dictionary) -> void:
	root_freq = params.get("root", 261.63)
	scale_semitones = params.get("scale", [0, 2, 4, 7, 9])
	note_dur = params.get("note_dur", 1.6)
	drone_vol = params.get("drone_vol", 0.06) * 0.8
	_time_in_note = 0.0
	_pattern_idx = 0
	_melody_t = 0.0
	_voices = [{"freq": _freq_for_degree(max(pattern[0], 0)), "phase": 0.0, "age": 0.0}]
	_chord_idx = 0
	_time_in_chord = 0.0
	_chord_dur = note_dur * 4.0
	_set_chord(0)
	_echo_buf.fill(0.0)
	_echo_pos = 0
	if not is_playing():
		play()
	playback = get_stream_playback()
	_fill_buffer()

func stop_theme() -> void:
	stop()
	playback = null

func _freq_for_degree(i: int) -> float:
	var n = scale_semitones.size()
	var deg = scale_semitones[((i % n) + n) % n]
	var octave = i / n
	return root_freq * pow(2.0, (deg + 12 * octave) / 12.0)

func _set_chord(idx: int) -> void:
	var root_deg: int = chord_roots[idx % chord_roots.size()]
	for v in range(3):
		# stacked "thirds" within the scale, one octave below the melody
		_pad_freqs[v] = _freq_for_degree(root_deg + v * 2) * 0.5

func _process(_delta: float) -> void:
	if playback == null:
		return
	volume_db = linear_to_db(clampf(Global.music_volume, 0.001, 1.0)) - 4.0
	_fill_buffer()

func _fill_buffer() -> void:
	if playback == null:
		return
	var to_fill = mini(playback.get_frames_available(), MAX_FRAMES_PER_CALL)
	var dt = 1.0 / MIX_RATE
	var echo_len = _echo_buf.size()
	var chunk := PackedVector2Array()
	chunk.resize(to_fill)
	for i in range(to_fill):
		# --- melody note clock: rests just let the previous tail ring ---
		_time_in_note += dt
		_melody_t += dt
		if _time_in_note >= note_dur:
			_time_in_note = 0.0
			_pattern_idx = (_pattern_idx + 1) % pattern.size()
			var deg: int = pattern[_pattern_idx]
			if deg >= 0:
				_voices.append({"freq": _freq_for_degree(deg), "phase": 0.0, "age": 0.0})
				if _voices.size() > 3:
					_voices.pop_front()

		# --- chord clock ---
		_time_in_chord += dt
		if _time_in_chord >= _chord_dur:
			_time_in_chord = 0.0
			_chord_idx = (_chord_idx + 1) % chord_roots.size()
			_set_chord(_chord_idx)

		# --- melody: overlapping voices, slow attack + long release (legato) ---
		var mel_sample := 0.0
		var vibrato = 1.0 + 0.0025 * sin(TAU * 4.2 * _melody_t)
		var attack = note_dur * 0.35
		for v in _voices:
			v.age += dt
			var env: float
			if v.age < attack:
				var x = v.age / attack
				env = x * x * (3.0 - 2.0 * x) # smoothstep swell in
			else:
				env = exp(-(v.age - attack) / (note_dur * 1.1)) # long soft tail
			v.phase += v.freq * vibrato * dt
			if v.phase > 1.0:
				v.phase -= 1.0
			mel_sample += sin(TAU * v.phase) * env
		mel_sample *= note_vol

		# --- chord pad: three voices, long swell across the chord ---
		var pad_env = sin(PI * clampf(_time_in_chord / _chord_dur, 0.0, 1.0))
		pad_env = 0.25 + 0.75 * pad_env # never fully silent, no hard gaps
		var pad_sample := 0.0
		for v in range(3):
			_pad_phases[v] += _pad_freqs[v] * dt
			if _pad_phases[v] > 1.0:
				_pad_phases[v] -= 1.0
			pad_sample += sin(TAU * _pad_phases[v])
		pad_sample *= pad_vol * pad_env / 3.0

		# --- breathing sub drone ---
		_phase_drone += root_freq * 0.25 * dt
		if _phase_drone > 1.0:
			_phase_drone -= 1.0
		_phase_lfo += 0.05 * dt
		if _phase_lfo > 1.0:
			_phase_lfo -= 1.0
		var drone_sample = sin(TAU * _phase_drone) * drone_vol * (0.7 + 0.3 * sin(TAU * _phase_lfo))

		# --- soft mono echo shared by both channels ---
		var dry = mel_sample + pad_sample + drone_sample
		var echoed: float = _echo_buf[_echo_pos]
		_echo_buf[_echo_pos] = dry + echoed * ECHO_FEEDBACK
		_echo_pos = (_echo_pos + 1) % echo_len
		var wet = dry + echoed * ECHO_MIX

		# gentle stereo spread: pad leans left, melody leans right
		var l = clampf(wet - mel_sample * 0.25 + pad_sample * 0.20, -1.0, 1.0)
		var r = clampf(wet + mel_sample * 0.25 - pad_sample * 0.20, -1.0, 1.0)
		chunk[i] = Vector2(l, r)
	if to_fill > 0:
		playback.push_buffer(chunk)
