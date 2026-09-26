extends GutTest

## The basic Attack row applied the Arbiter execute bonus AFTER defense. The swing does the
## opposite: _execute_attack multiplies Final Word, then take_damage runs amount²/(amount+DEF).
## That formula is not linear, so at attack 80, defense 50, 1.5x the row quoted 73 while the
## hit dealt 84, and [KILL] followed the quote. Variance stays out of the preview (it is a
## roll); this file pins that roll to 1x. Miss and crit are not in the quote either, so a
## swing that misses or crits is discarded and retried — those rolls are not the defect.

const ATK := 80
const DEFENSE := 50

var _saved_weather: String = ""
var _saved_weather_timer: float = 0.0
var _saved_damage_multiplier: float = 1.0
var _saved_assignments: Dictionary = {}
var _bm: Node = null
var _notes: PackedStringArray = PackedStringArray()


class _PinnedVariance extends VolatilitySystem:
	func get_variance_range(_combatant) -> Vector2:
		return Vector2(1.0, 1.0)

	func check_tail_event() -> bool:
		return false


func before_each() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and "weather_condition" in gs:
		_saved_weather = str(gs.weather_condition)
		_saved_weather_timer = float(gs.weather_timer)
		## Rain cuts fire. Forest boosts it. Armed so a preview that folds them in
		## out of the swing's order cannot still match the hit.
		gs.weather_condition = "rain"
		gs.weather_timer = 100000.0
	if gs != null and "game_constants" in gs:
		_saved_damage_multiplier = float(gs.game_constants.get("damage_multiplier", 1.0))
		gs.game_constants["damage_multiplier"] = 1.0
	if gs != null and "lens_assignments" in gs:
		_saved_assignments = gs.lens_assignments.duplicate(true)
	_bm = load("res://src/battle/BattleManager.gd").new()
	add_child_autofree(_bm)
	_bm.volatility = _PinnedVariance.new()
	_bm.set_terrain("forest")


func after_each() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and _saved_weather != "" and "weather_condition" in gs:
		gs.weather_condition = _saved_weather
		gs.weather_timer = _saved_weather_timer
	if gs != null and "game_constants" in gs:
		gs.game_constants["damage_multiplier"] = _saved_damage_multiplier
	if gs != null and "lens_assignments" in gs:
		gs.lens_assignments.clear()
		for k in _saved_assignments:
			gs.lens_assignments[k] = _saved_assignments[k]


func _on_log(msg: String) -> void:
	_notes.append(msg)


func _on_miss(_target: Combatant) -> void:
	_notes.append("MISS")


func _on_dealt(_target: Combatant, _amount: int, is_crit: bool, _element: String, _mod: float) -> void:
	if is_crit:
		_notes.append("CRITICAL")


func _fighter(named: String) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = named
	c.is_alive = true
	c.max_hp = 500
	c.current_hp = 500
	c.attack = ATK
	c.defense = 20
	c.speed = 0
	c.current_ap = 4
	## Flame Sword's fire bonus is on the weapon. The swing does not read it for a basic
	## attack; the row must not either, or the quote and the hit diverge.
	c.equipped_weapon = "flame_sword"
	return c


func _foe(max_hp: int, current_hp: int) -> Combatant:
	var t := Combatant.new()
	autofree(t)
	t.combatant_name = "Wounded"
	t.is_alive = true
	t.max_hp = max_hp
	t.current_hp = current_hp
	t.defense = DEFENSE
	t.speed = 0
	t.elemental_weaknesses.append("fire")
	return t


## The pre-fix quote: defend, then scale. Kept so this fixture can prove the two orders
## are not the same integer.
func _bonus_after_defense(atk: int, defense: int, mult: float) -> int:
	var mitigated := maxi(1, int((float(atk) * float(atk)) / float(maxi(1, atk + defense))))
	return maxi(1, int(float(mitigated) * mult))


func _execute_axis() -> String:
	if LensSystem == null or not ("lenses" in LensSystem):
		return ""
	for axis in LensSystem.lenses:
		var me: Dictionary = (LensSystem.lenses[axis] as Dictionary).get("meta_effects", {})
		if float(me.get("lens_execute_threshold", 0.0)) > 0.0 and float(me.get("lens_execute_bonus", 0.0)) > 0.0:
			return str(axis)
	return ""


func _threshold(axis: String) -> float:
	return float((LensSystem.lenses[axis] as Dictionary).get("meta_effects", {}).get("lens_execute_threshold", 0.0))


func _bonus(axis: String) -> float:
	return float((LensSystem.lenses[axis] as Dictionary).get("meta_effects", {}).get("lens_execute_bonus", 0.0))


func _equip(c: Combatant, axis: String) -> void:
	GameState.lens_assignments[c.combatant_name.to_lower().replace(" ", "_")] = axis


## A landed, non-crit swing. Miss (2% floor) and crit (5% floor) are not in the preview.
func _clean_hit(attacker: Combatant, target: Combatant, wounded_hp: int) -> int:
	for _attempt in range(40):
		target.current_hp = wounded_hp
		target.is_alive = true
		_notes = PackedStringArray()
		_bm.battle_log_message.connect(_on_log)
		_bm.attack_missed.connect(_on_miss)
		_bm.damage_dealt.connect(_on_dealt)
		_bm._execute_attack(attacker, target)
		_bm.battle_log_message.disconnect(_on_log)
		_bm.attack_missed.disconnect(_on_miss)
		_bm.damage_dealt.disconnect(_on_dealt)
		var blob := " ".join(_notes)
		if blob.contains("MISS") or blob.contains("CRITICAL") or blob.contains("TAIL"):
			continue
		var dealt := wounded_hp - target.current_hp
		if dealt <= 0:
			continue
		return dealt
	return -1


func test_the_basic_attack_preview_matches_the_swing_with_and_without_execute() -> void:
	var roll: Vector2 = _bm.volatility.get_variance_range(_fighter("Roll"))
	assert_eq(roll, Vector2(1.0, 1.0),
		"CONTROL: the damage roll must be pinned to 1x, or variance can fake a mismatch")
	assert_false(_bm.volatility.check_tail_event(),
		"CONTROL: a tail surge doubles or halves the swing and is not in the preview")
	assert_not_null(LensSystem, "CONTROL: LensSystem must resolve or the bonus arm is vacuous")
	assert_not_null(GameState, "CONTROL: GameState holds lens_assignments")
	var axis := _execute_axis()
	assert_ne(axis, "",
		"CONTROL: some lens must author an execute threshold and bonus, or both arms compare a number to itself")
	var mult := 1.0 + _bonus(axis)
	var quoted_late := _bonus_after_defense(ATK, DEFENSE, mult)
	var swung_early := maxi(1, int((float(int(ATK * mult)) * float(int(ATK * mult))) / float(int(ATK * mult) + DEFENSE)))
	assert_ne(quoted_late, swung_early,
		"CONTROL: the two orders must not be the same integer on attack %d defense %d ×%.2f (after %d, before %d)" % [ATK, DEFENSE, mult, quoted_late, swung_early])
	var threshold := _threshold(axis)
	var max_hp := 20000
	var wounded_hp := maxi(1, int(float(max_hp) * threshold) - 1)
	assert_lte(float(wounded_hp) / float(max_hp), threshold,
		"CONTROL: the target must sit at or under the execute threshold")
	assert_gt(wounded_hp, 1000,
		"CONTROL: the target must survive the hit or the HP delta is a remainder, not the damage")

	var bare := _fighter("BareSwing")
	var bare_foe := _foe(max_hp, wounded_hp)
	assert_eq(_bm.lens_execute_multiplier(bare, bare_foe), 1.0,
		"CONTROL: no lens equipped, so the swing must not apply Final Word")
	var preview_bare: int = _bm.estimate_attack_damage(bare, bare_foe)
	var hit_bare := _clean_hit(bare, bare_foe, wounded_hp)
	assert_gt(hit_bare, 0, "CONTROL: a clean swing must land with no execute bonus")
	assert_eq(preview_bare, hit_bare,
		"with no execute bonus the Attack row must quote the hit (preview %d, hit %d)" % [preview_bare, hit_bare])

	var caster := _fighter("PreviewFighter")
	_equip(caster, axis)
	var foe := _foe(max_hp, wounded_hp)
	var applied: float = float(_bm.lens_execute_multiplier(caster, foe))
	assert_almost_eq(applied, mult, 0.001,
		"CONTROL: the wounded target must be inside Final Word (got ×%.2f, authored ×%.2f)" % [applied, mult])
	var preview_lens: int = _bm.estimate_attack_damage(caster, foe)
	var hit_lens := _clean_hit(caster, foe, wounded_hp)
	assert_gt(hit_lens, 0, "CONTROL: a clean swing must land with the execute bonus")
	assert_gt(hit_lens, hit_bare,
		"CONTROL: the swing itself must hit harder once Final Word applies (bare %d, lensed %d)" % [hit_bare, hit_lens])
	assert_eq(preview_lens, hit_lens,
		"the Attack row must quote the hit — scaling Final Word after defense quotes %d (preview %d, hit %d)" % [quoted_late, preview_lens, hit_lens])
	var formula := str(_bm.estimate_attack_breakdown(caster, foe)["formula"])
	assert_lt(formula.find("×execute"), formula.find("DEF"),
		"Formula Sight must show the bonus before defense, matching the swing (%s)" % formula)
	assert_true(formula.contains(str(preview_lens)),
		"the working must end at the number on the row (%s)" % formula)
