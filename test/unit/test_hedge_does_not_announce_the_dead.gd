extends GutTest

## One tab. hedge_position's log line sat OUTSIDE the validity guard its two siblings put it inside.
##
##     if target and is_instance_valid(target) and target.is_alive:
##         target.add_buff("Hedged", ...)
##     battle_log_message.emit("... %s is hedged!" % target.combatant_name)   ← one level out
##
## So a dead or null entry in the target list still printed "X is hedged!" for a buff it never got,
## and reached `target.combatant_name` on something that just failed is_instance_valid. That second
## half is the dangerous one: a property access on a freed instance ABORTS the enclosing function,
## so the rest of the target loop never runs and the survivors silently go unhedged. The abort
## returns nothing and looks like a completed call.
##
## Its siblings volatility_up_self and volatility_up_enemy both have the emit inside the guard,
## which is what makes this a slip rather than a choice — the same tell as the AP-grant cue whose
## sibling played nothing.
##
## Asserts the RELATIONSHIP across all three arms, not this one line, so the next slip in the family
## is caught too.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")

var _bm = null
var _log: Array = []

func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)
	_log = []
	_bm.battle_log_message.connect(func(m): _log.append(str(m)))
	## The arm is wrapped in `if volatility:` — a bare BattleManager has none, and without this the
	## whole family silently no-ops and every assertion below passes for the wrong reason. The
	## controls caught it; a test without them would have shipped green over an arm that never ran.
	_bm.volatility = VolatilitySystem.new()

func _ally(display_name: String, alive: bool) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = display_name
	c.max_hp = 100
	c.current_hp = 100 if alive else 0
	c.is_alive = alive
	return c

func _hedge() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	assert_not_null(parsed, "CONTROL: abilities.json parses")
	return ((parsed as Dictionary).get("abilities", parsed) as Dictionary)["hedge_position"]

func test_a_living_ally_is_hedged_and_announced() -> void:
	var caster := _ally("Speculator", true)
	var ally := _ally("Bram", true)
	_bm._execute_support_ability(caster, _hedge(), [ally])
	assert_string_contains("".join(_log), "Bram is hedged",
		"CONTROL: the working case still works — this fix removes a false line, not the true one")
	assert_gt(ally.active_buffs.size(), 0, "CONTROL: and the buff really lands")

func test_a_dead_ally_is_not_announced() -> void:
	var caster := _ally("Speculator", true)
	var corpse := _ally("Fallen", false)
	_bm._execute_support_ability(caster, _hedge(), [corpse])
	assert_false("".join(_log).contains("Fallen is hedged"),
		"a corpse gets no buff, so it must get no line — the log was announcing what did not happen")
	assert_eq(corpse.active_buffs.size(), 0, "CONTROL: and it genuinely received nothing")

func test_a_dead_entry_does_not_stop_the_living_one_behind_it() -> void:
	## The consequence that costs more than the false line: an error on the dead entry aborts the
	## whole function mid-loop, and every target after it is silently skipped.
	var caster := _ally("Speculator", true)
	var corpse := _ally("Fallen", false)
	var ally := _ally("Mira", true)
	_bm._execute_support_ability(caster, _hedge(), [corpse, ally])
	assert_gt(ally.active_buffs.size(), 0,
		"the ally listed AFTER a corpse must still be hedged")

func test_all_three_volatility_arms_guard_their_own_log_line() -> void:
	## The relationship, so the next slip in this family reds too. Each arm's emit must be indented
	## at least as deep as the add_buff/add_debuff it reports.
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var checked: int = 0
	for arm in ["volatility_up_self", "volatility_up_enemy", "volatility_down"]:
		var i: int = src.find("\t\t\"%s\":" % arm)
		assert_gt(i, -1, "CONTROL: located the %s arm" % arm)
		var j: int = src.find("\n\t\t\"", i + 10)
		var body: String = src.substr(i, j - i) if j > i else src.substr(i, 900)
		var apply_depth: int = -1
		var emit_depth: int = -1
		for line in body.split("\n"):
			var depth: int = line.length() - line.lstrip("\t").length()
			if apply_depth < 0 and (line.contains("add_buff(") or line.contains("add_debuff(")):
				apply_depth = depth
			if emit_depth < 0 and line.contains("battle_log_message.emit("):
				emit_depth = depth
		assert_gt(apply_depth, -1, "CONTROL: %s applies something" % arm)
		assert_gt(emit_depth, -1, "CONTROL: %s announces something" % arm)
		assert_gte(emit_depth, apply_depth,
			"%s's log line must sit no shallower than the buff it reports, or it announces the unbuffed" % arm)
		checked += 1
	assert_eq(checked, 3, "CONTROL: three volatility arms — if the family grows, extend the list")
