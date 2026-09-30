extends RefCounted
class_name Glicko2

# Standard Glicko-2 rating algorithm (Mark Glickman), the same system
# lichess.org uses for its ratings (lichess itself starts new players at
# 1500; this game starts new players at 1000 instead, since our AI ladder
# and rating_title() bands are calibrated around a lower "brand new player"
# floor). RD/volatility defaults still match lichess.
# Reference: https://www.glicko.net/glicko/glicko2.pdf

const SCALE := 173.7178
const TAU := 0.5
const EPSILON := 0.000001

const DEFAULT_RATING := 1000.0
const DEFAULT_RD := 350.0
const DEFAULT_VOLATILITY := 0.06

static func _g(phi: float) -> float:
	return 1.0 / sqrt(1.0 + 3.0 * phi * phi / (PI * PI))

static func _e(mu: float, mu_j: float, phi_j: float) -> float:
	return 1.0 / (1.0 + exp(-_g(phi_j) * (mu - mu_j)))

# Updates a player's rating after a SINGLE game against one opponent.
# score: 1.0 = win, 0.5 = draw, 0.0 = loss (from the player's perspective).
# Returns {rating, rd, volatility} — the new values.
static func update(rating: float, rd: float, volatility: float, opp_rating: float, opp_rd: float, score: float) -> Dictionary:
	var mu = (rating - 1500.0) / SCALE
	var phi = rd / SCALE
	var mu_j = (opp_rating - 1500.0) / SCALE
	var phi_j = opp_rd / SCALE

	var g_j = _g(phi_j)
	var e_j = _e(mu, mu_j, phi_j)
	var v = 1.0 / (g_j * g_j * e_j * (1.0 - e_j)) if (e_j > 0.0 and e_j < 1.0) else 1e7
	var delta = v * g_j * (score - e_j)

	# Step 5: iterative solve for new volatility (Illinois algorithm)
	var a = log(volatility * volatility)
	var f = func(x: float) -> float:
		var ex = exp(x)
		var num = ex * (delta * delta - phi * phi - v - ex)
		var den = 2.0 * pow(phi * phi + v + ex, 2)
		return (num / den) - ((x - a) / (TAU * TAU))

	var A = a
	var B: float
	if delta * delta > phi * phi + v:
		B = log(delta * delta - phi * phi - v)
	else:
		var k = 1.0
		while f.call(a - k * TAU) < 0.0:
			k += 1.0
		B = a - k * TAU

	var fa = f.call(A)
	var fb = f.call(B)
	var iterations = 0
	while abs(B - A) > EPSILON and iterations < 100:
		var C = A + (A - B) * fa / (fb - fa)
		var fc = f.call(C)
		if fc * fb < 0.0:
			A = B
			fa = fb
		else:
			fa = fa / 2.0
		B = C
		fb = fc
		iterations += 1

	var new_volatility = exp(A / 2.0)
	var phi_star = sqrt(phi * phi + new_volatility * new_volatility)
	var new_phi = 1.0 / sqrt(1.0 / (phi_star * phi_star) + 1.0 / v)
	var new_mu = mu + new_phi * new_phi * g_j * (score - e_j)

	var new_rating = new_mu * SCALE + 1500.0
	var new_rd = new_phi * SCALE

	return {"rating": new_rating, "rd": new_rd, "volatility": new_volatility}

# RD naturally grows over time (uncertainty increases when not playing).
# Call once per elapsed "period" (we treat each calendar day as one period).
static func decay_rd(rd: float, periods_elapsed: float) -> float:
	if periods_elapsed <= 0.0:
		return rd
	var phi = rd / SCALE
	var c = 34.6 # tuned so RD returns to ~350 over roughly a year of inactivity
	var new_phi = sqrt(phi * phi + periods_elapsed * (c / SCALE) * (c / SCALE))
	return min(new_phi * SCALE, DEFAULT_RD)
