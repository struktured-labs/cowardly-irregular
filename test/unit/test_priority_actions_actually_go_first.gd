extends GutTest

## quick_strike is "Lightning-fast attack that always goes first". It went whenever its speed said.
##
## The ability authors priority=true; _compute_action_speed read speed_modifier and nothing else, so
## the key had ZERO readers. A slow Ninja's Quick Strike resolved after everyone — the one property
## the ability is named for. Lower speed_value sorts earlier, so priority subtracts an offset rather
## than clamping to a constant, which keeps two priority actions ordered against each other instead
## of tied.
##
## Also here: the autobattle path's "Cannot use ability: X (MP: N)" line now names silence when that
## is the cause. Blaming MP for a boss debuff sends the next reader to the wrong system — the same
## class as the comment that sent me to a consumer which did not exist.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")

var _bm = null

func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)

func _fighter(speed: int) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Speed %d" % speed
	c.speed = speed
	c.max_hp = 100
	c.current_hp = 100
	c.max_mp = 99
	c.current_mp = 99
	c.job = {"id": "ninja", "abilities": ["quick_strike"]}
	return c

func _ability(aid: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	assert_not_null(parsed, "CONTROL: abilities.json parses")
	return ((parsed as Dictionary).get("abilities", parsed) as Dictionary)[aid]

func test_quick_strike_still_authors_the_promise() -> void:
	var qs := _ability("quick_strike")
	assert_true(bool(qs.get("priority", false)),
		"the data is the source of this behaviour — if priority is retired, retire the code with it")
	assert_string_contains(str(qs.get("description", "")), "first",
		"CONTROL: the description is what makes the missing mechanic a defect and not a preference")

func test_a_priority_ability_outruns_a_much_faster_opponent() -> void:
	## The real shape: a SLOW ninja against a FAST rival. Without the offset the ninja loses.
	var slow := _fighter(1)
	var fast := _fighter(200)
	var ninja_speed: float = _bm._compute_action_speed(slow, "ability", _ability("quick_strike"))
	var rival_speed: float = _bm._compute_action_speed(fast, "attack")
	assert_lt(ninja_speed, rival_speed,
		"lower sorts first — Quick Strike must beat a 200-speed basic attack from a 1-speed caster")

func test_an_ordinary_ability_from_the_same_caster_does_not() -> void:
	## The discriminator. If everything got the offset the ordering would be unchanged in effect.
	var slow := _fighter(1)
	var fast := _fighter(200)
	var ordinary: Dictionary = _ability("quick_strike").duplicate(true)
	ordinary.erase("priority")
	assert_gt(_bm._compute_action_speed(slow, "ability", ordinary),
		_bm._compute_action_speed(fast, "attack"),
		"without priority the slow caster still loses — the offset is keyed on the flag, not the ability")

func test_two_priority_actions_still_order_by_speed() -> void:
	## Why an offset and not a flat constant: a constant ties them and the tiebreak becomes arbitrary.
	## ⚠️ This one does NOT fail when the priority read is removed — the offset applies to both sides
	## equally, so their relative order is unchanged. I predicted it would, and the wrong count is
	## what showed me it guards the offset-vs-constant CHOICE, not the feature. Its arm is replacing
	## `-=` with `=`, which ties them at -1000.0 and turns this red.
	var qs := _ability("quick_strike")
	assert_lt(_bm._compute_action_speed(_fighter(200), "ability", qs),
		_bm._compute_action_speed(_fighter(1), "ability", qs),
		"the faster of two priority casters must still act first")

func test_the_offset_clears_the_whole_ordinary_range() -> void:
	## Guards the magnitude against a future speed inflation quietly re-tying the two bands.
	var fastest: float = _bm._compute_action_speed(_fighter(999), "defer")
	var slowest: float = _bm._compute_action_speed(_fighter(0), "ability")
	assert_gt(_bm.PRIORITY_OFFSET, absf(slowest - fastest),
		"PRIORITY_OFFSET must exceed the ordinary speed spread or priority stops being reliable")

func test_the_autobattle_refusal_names_silence_not_mp() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var i: int = src.find("[AUTOBATTLE] Cannot use ability")
	assert_gt(i, -1, "CONTROL: located the refusal line")
	assert_string_contains(src.substr(maxi(0, i - 400), 500), "silenced",
		"the diagnostic must name silence — it is now a second way this refusal fires")
