class_name VolatilitySystem extends RefCounted

## VolatilitySystem - 3-layer volatility architecture for combat
## Local (per-combatant) x Global (band) x Macro (persistent)
## Modifies damage variance, crit ranges, and CTB jitter

## Volatility bands - higher = more chaos
enum Band { STABLE, SHIFTING, UNSTABLE, FRACTURED }

## Band parameters: [variance_width, tail_event_pct, ctb_jitter]
const BAND_PARAMS: Array = [
	{"variance": 0.15, "tail_pct": 0.01, "ctb_jitter": 1.0},   # Stable
	{"variance": 0.25, "tail_pct": 0.045, "ctb_jitter": 2.0},  # Shifting
	{"variance": 0.40, "tail_pct": 0.08, "ctb_jitter": 4.0},   # Unstable
	{"variance": 0.60, "tail_pct": 0.135, "ctb_jitter": 8.0},  # Fractured
]

const BAND_NAMES: Array = ["Stable", "Shifting", "Unstable", "Fractured"]

## Local volatility per combatant (default 1.0)
var local_volatility: Dictionary = {}

## Global band (0-3)
var global_band: int = 0


func get_variance_range(combatant) -> Vector2:
	"""Get (min_mult, max_mult) for damage variance, factoring local x global x macro."""
	var band_variance = BAND_PARAMS[global_band]["variance"]
	var local_mult = get_local(combatant)

	# Read macro volatility from GameState if available
	var macro = _get_macro_volatility()

	# Final variance width = base * (1 + macro * 0.5) * local
	var final_width = band_variance * (1.0 + macro * 0.5) * local_mult
	final_width = clampf(final_width, 0.05, 0.80)

	return Vector2(1.0 - final_width, 1.0 + final_width)


func get_ctb_jitter() -> float:
	"""Get CTB jitter range based on global band."""
	return BAND_PARAMS[global_band]["ctb_jitter"]


func check_tail_event() -> bool:
	"""Roll against tail event chance for current band."""
	var tail_pct = BAND_PARAMS[global_band]["tail_pct"]
	var macro = _get_macro_volatility()
	# Macro volatility increases tail event chance
	var final_pct = tail_pct * (1.0 + macro)
	return randf() < final_pct


func set_local(combatant, value: float) -> void:
	"""Set local volatility for a combatant."""
	local_volatility[combatant] = value


func get_local(combatant) -> float:
	"""Get local volatility for a combatant.
	Checks buffs/debuffs with stat='volatility' first, then falls back to stored value."""
	if combatant and "active_buffs" in combatant and "active_debuffs" in combatant:
		# Check active buffs for volatility modifier
		var vol_mult = 1.0
		var found_buff = false
		for buff in combatant.active_buffs:
			if buff.get("stat", "") == "volatility":
				vol_mult *= buff.get("modifier", 1.0)
				found_buff = true
		for debuff in combatant.active_debuffs:
			if debuff.get("stat", "") == "volatility":
				vol_mult *= debuff.get("modifier", 1.0)
				found_buff = true
		if found_buff:
			return vol_mult

	return local_volatility.get(combatant, 1.0)


func shift_band(delta: int) -> void:
	"""Move global band up/down, clamped 0-3."""
	var old_band = global_band
	global_band = clampi(global_band + delta, 0, 3)
	if old_band != global_band:
		print("[VOLATILITY] Band shifted: %s -> %s" % [BAND_NAMES[old_band], BAND_NAMES[global_band]])


func reset_battle() -> void:
	"""Clear local volatility, set starting band from macro."""
	local_volatility.clear()
	# Macro volatility determines starting band
	var macro = _get_macro_volatility()
	if macro >= 0.75:
		global_band = Band.SHIFTING
	else:
		global_band = Band.STABLE
	print("[VOLATILITY] Battle started at band: %s (macro: %.2f)" % [BAND_NAMES[global_band], macro])


func get_band_name() -> String:
	"""Get human-readable band name."""
	return BAND_NAMES[global_band]


func get_tail_event_pct() -> float:
	"""Get current tail event percentage for display."""
	return BAND_PARAMS[global_band]["tail_pct"] * 100.0


func _get_macro_volatility() -> float:
	"""Read macro volatility from GameState."""
	var game_state = Engine.get_singleton("GameState") if Engine.has_singleton("GameState") else null
	if game_state == null:
		# Try node path
		var tree = Engine.get_main_loop()
		if tree and tree.has_method("get_root"):
			var root = tree.get_root()
			if root:
				game_state = root.get_node_or_null("GameState")
	if game_state and "macro_volatility" in game_state:
		return game_state.macro_volatility
	return 0.0
