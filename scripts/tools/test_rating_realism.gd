extends Node

# «Правдоподобен ли рейтинг?» — симуляция игрока с ЗАРАНЕЕ ИЗВЕСТНОЙ настоящей силой.
# Игрок играет с уровнями ИИ, исходы выпадают по шахматной формуле ожидания, рейтинг
# считается ровно так, как в игре (Profile.rating_after). Проверяем свойства, которые
# делают рейтинг честным:
#   1. Игрок, выбирающий соперников по силе, приходит к своей настоящей силе.
#   2. Нельзя «накрутить» рейтинг, играя без конца только с самым слабым уровнем.
#   3. Нельзя «утопить» рейтинг, играя только с самым сильным.
#   4. Более сильный игрок всегда получает более высокий рейтинг.
#   5. Одна партия новичка не сдвигает рейтинг на десятки и сотни очков.
#   6. Растущий игрок не отстаёт от своего роста надолго.
# Запуск: scenes/tools/TestRatingRealism.tscn. Использует Profile.LEVEL_RATING как «правду»
# о силе уровней (её проверяет TestLevelLadder).

const SEEDS := 30
var fails := 0

func check(name: String, ok: bool, info: String = "") -> void:
	print(("OK   " if ok else "FAIL ") + name + (" " + info if info != "" else ""))
	if not ok:
		fails += 1

# исход одной партии: 1 / 0.5 / 0 для игрока настоящей силы t против соперника opp
func roll(rng: RandomNumberGenerator, t: float, opp: float) -> float:
	var e := 1.0 / (1.0 + pow(10.0, (opp - t) / 400.0))
	var p_draw := 0.12 * (1.0 - absf(2.0 * e - 1.0))
	var p_win := e - p_draw / 2.0
	var x := rng.randf()
	if x < p_win:
		return 1.0
	if x < p_win + p_draw:
		return 0.5
	return 0.0

# уровень, чей рейтинг ближе всего к текущему рейтингу игрока (выбор «по силам»)
func nearest_level(r: float) -> int:
	var best := 1
	var bd := 1.0e9
	for i in range(Profile.LEVEL_RATING.size()):
		var d := absf(float(Profile.LEVEL_RATING[i]) - r)
		if d < bd:
			bd = d
			best = i + 1
	return best

# state = {"r", "rd", "v"}; policy: "near" — соперник по силам, либо номер уровня
func play_games(rng: RandomNumberGenerator, state: Dictionary, t: float, n: int, policy, growth: float = 0.0) -> void:
	for i in range(n):
		var level: int = nearest_level(state.r) if str(policy) == "near" else int(policy)
		var opp := float(Profile.LEVEL_RATING[level - 1])
		var s := roll(rng, t + growth * i, opp)
		var u: Dictionary = Profile.rating_after(state.r, state.rd, state.v, level, s)
		state.r = u.rating
		state.rd = u.rd
		state.v = u.volatility

func fresh() -> Dictionary:
	return {"r": Glicko2.DEFAULT_RATING, "rd": Glicko2.DEFAULT_RD, "v": Glicko2.DEFAULT_VOLATILITY}

func mean_final(t: float, n: int, policy, growth: float = 0.0) -> float:
	var total := 0.0
	for seed in range(SEEDS):
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + seed
		var st := fresh()
		play_games(rng, st, t, n, policy, growth)
		total += st.r
	return total / SEEDS

func _ready() -> void:
	var tab: Array = Profile.LEVEL_RATING
	var lo: float = float(tab[0])
	var hi: float = float(tab[tab.size() - 1])
	print("таблица уровней: %d … %d" % [int(lo), int(hi)])

	# 1. сходимость: игрок выбирает соперников по силам
	for frac in [0.1, 0.3, 0.5]:
		var t: float = lo + (hi - lo) * frac
		var r80 := mean_final(t, 80, "near")
		check("сходимость: настоящая сила %d → рейтинг после 80 партий %d (допуск ±150)" % [int(t), int(r80)], absf(r80 - t) <= 150.0)

	# 2. накрутка на самом слабом уровне: победы над «уровнем 400» не должны разгонять рейтинг
	var farm_t: float = lo + (hi - lo) * 0.6
	var farmed := mean_final(farm_t, 300, 1)
	check("накрутка: 300 побед над уровнем 1 дают рейтинг %d, не выше %d" % [int(farmed), int(Glicko2.DEFAULT_RATING + 100.0)], farmed <= Glicko2.DEFAULT_RATING + 100.0)

	# 3. «стена»: слабый игрок только против сильнейшего
	var wall := mean_final(lo, 100, tab.size())
	check("стена: 100 поражений от сильнейшего оставляют рейтинг %d ≥ 100" % int(wall), wall >= 100.0)

	# 4. монотонность
	var prev := -1.0e9
	var mono := true
	for frac in [0.15, 0.3, 0.45, 0.6, 0.75, 0.9]:
		var r := mean_final(lo + (hi - lo) * frac, 80, "near")
		if r < prev:
			mono = false
		prev = r
	check("более сильный игрок получает более высокий рейтинг", mono)

	# 5. первая партия новичка
	var swing := 0.0
	for lv in [1, 5, 10, 15]:
		var u: Dictionary = Profile.rating_after(Glicko2.DEFAULT_RATING, Glicko2.DEFAULT_RD, Glicko2.DEFAULT_VOLATILITY, lv, 1.0)
		swing = maxf(swing, absf(u.rating - Glicko2.DEFAULT_RATING))
	check("первая партия сдвигает рейтинг не больше чем на 100 (максимум %d)" % int(swing), swing <= 100.0)

	# 6. растущий игрок: +2 очка силы за партию, 150 партий
	var t0: float = lo + (hi - lo) * 0.2
	var growth := 2.0
	var tail := 0.0
	for seed in range(SEEDS):
		var rng := RandomNumberGenerator.new()
		rng.seed = 2000 + seed
		var st := fresh()
		play_games(rng, st, t0, 150, "near", growth)
		tail += (t0 + growth * 149.0) - st.r
	tail /= SEEDS
	check("растущий игрок: отставание рейтинга от настоящей силы %d (допуск ≤ 150)" % int(tail), absf(tail) <= 150.0)

	_check_tournament()

	print("=== ИТОГО ошибок: %d ===" % fails)
	get_tree().quit(1 if fails > 0 else 0)

# Турнирный рейтинг считается той же функцией: проверяем через настоящий Profile
# (current_user пуст — на диск ничего не пишется, состояние возвращается).
func _check_tournament() -> void:
	var saved_user: String = Profile.current_user
	var saved_r: float = Profile.tournament_rating
	var saved_rd: float = Profile.tournament_rd
	var saved_v: float = Profile.tournament_volatility
	Profile.current_user = ""
	Profile.tournament_rating = Glicko2.DEFAULT_RATING
	Profile.tournament_rd = Glicko2.DEFAULT_RD
	Profile.tournament_volatility = Glicko2.DEFAULT_VOLATILITY
	Profile.record_tournament_game(15, 1.0)
	check("турнир: первая победа сдвигает рейтинг не больше чем на 100 (%+d)" % int(Profile.last_tournament_rating_change), absf(Profile.last_tournament_rating_change) <= 100.0)
	Profile.tournament_rating = Glicko2.DEFAULT_RATING
	for i in range(100):
		Profile.record_tournament_game(1, 1.0)
	check("турнир: 100 побед над уровнем 1 не разгоняют рейтинг (%d)" % int(Profile.tournament_rating), Profile.tournament_rating <= Glicko2.DEFAULT_RATING + 100.0)
	var saved_real: int = Profile.real_rating
	var saved_int: float = Profile.rating
	Profile.set_real_rating(1234)
	check("настоящий рейтинг становится точкой отсчёта", int(Profile.tournament_rating) == 1234 and int(Profile.rating) == 1234 and Profile.tournament_rd < Glicko2.DEFAULT_RD)
	Profile.set_real_rating(99999)
	check("настоящий рейтинг ограничен сверху", Profile.real_rating == Profile.REAL_RATING_MAX)
	Profile.set_real_rating(0)
	check("ноль убирает настоящий рейтинг, рейтинг остаётся", Profile.real_rating == 0 and int(Profile.tournament_rating) == Profile.REAL_RATING_MAX)
	Profile.real_rating = saved_real
	Profile.rating = saved_int
	Profile.current_user = saved_user
	Profile.tournament_rating = saved_r
	Profile.tournament_rd = saved_rd
	Profile.tournament_volatility = saved_v
