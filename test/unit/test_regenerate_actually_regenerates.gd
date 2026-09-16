extends GutTest

## ⛔ THE CLERIC'S RECREATIO COST 10 MP AND DID NOTHING AT ALL. `regenerate` is typed `healing`, so it
## reaches `_execute_healing_ability` — which reads `heal_amount` and nothing else. It authors no
## `heal_amount`: it authors `effect: regen` with `regen_per_turn: 40`, and the arm that reads those
## lives in `_execute_support_ability`, which a healing-typed ability never reaches.
##
## Measured before the fix, live executor, Cleric at 200/500:
##     cast -> heal(0), no status, no meta; three turn ticks -> 200 HP, unchanged
##
## Found by cowir-autogrind (11638) running the executor-path axis from cowir-battle's 2d14d92d over
## their own backlog — and their first filing of it was wrong in both directions, which is why the
## measurement is in this file rather than the claim.
##
## ⚠️ NOT a balance change, and the distinction matters because two abilities of the same shape ARE
## held for struktured (frost_armor's retaliation, subset_drain's secondary): those need an invented
## number or add a promise the data does not carry. This one authors its own 40 and its own 3 turns,
## and the current behaviour is "a player pays MP and receives nothing" — the same class as esuna
## writing a junk status, or pray damaging the ally it restores, both fixed here as bugs.

const REGEN_PER_TURN := 40
const DURATION := 3


func _cleric(hp: int = 200) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Mira"
	c.job = {"id": "cleric"}
	c.max_hp = 500
	c.current_hp = hp
	c.max_mp = 99
	c.current_mp = 99
	c.magic = 20
	c.is_alive = true
	return c


func test_the_ability_still_authors_what_this_guard_is_about() -> void:
	## CONTROL: every arm below reads the SHIPPED ability, so a data change must red here first.
	var ability: Dictionary = JobSystem.get_ability("regenerate")
	assert_eq(str(ability.get("type", "")), "healing", "regenerate is typed healing — that is what routes it")
	assert_eq(str(ability.get("effect", "")), "regen", "and authors its effect")
	assert_eq(int(ability.get("regen_per_turn", 0)), REGEN_PER_TURN, "with its own per-turn amount")
	assert_eq(int(ability.get("duration", 0)), DURATION, "and its own duration")
	assert_false(ability.has("heal_amount"), "and NO heal_amount — which is why the healing executor had nothing to read")
	assert_gt(int(ability.get("mp_cost", 0)), 0, "it costs MP, which is what made doing nothing a defect rather than a gap")


func test_casting_it_applies_the_regen_it_authors() -> void:
	var cleric := _cleric()
	BattleManager._execute_healing_ability(cleric, JobSystem.get_ability("regenerate"), [cleric])
	assert_true(cleric.has_status("regen"), "the cast applies regen")
	assert_eq(int(cleric.get_meta("_regen_per_turn", 0)), REGEN_PER_TURN,
		"carrying the authored 40, not the 5%%-of-max default (%d here)" % int(cleric.max_hp * 0.05))


func test_it_heals_the_authored_amount_each_turn_and_then_stops() -> void:
	var cleric := _cleric()
	BattleManager._execute_healing_ability(cleric, JobSystem.get_ability("regenerate"), [cleric])
	var seen: Array[int] = []
	for turn in DURATION + 1:
		cleric.update_buff_durations()
		seen.append(cleric.current_hp)
	assert_eq(seen[0], 240, "turn 1 restores the authored 40")
	assert_eq(seen[DURATION - 1], 200 + REGEN_PER_TURN * DURATION, "and it runs for the authored %d turns" % DURATION)
	assert_eq(seen[DURATION], seen[DURATION - 1], "then stops — the fourth tick restores nothing")
	assert_false(cleric.has_status("regen"), "and the status is gone")


func test_an_ordinary_heal_is_untouched() -> void:
	## CONTROL: the routing is narrow. `cure` authors a heal_amount and no effect, so it must still heal
	## instantly through the healing path — six of the seven healing abilities are this shape.
	var cleric := _cleric()
	BattleManager._execute_healing_ability(cleric, JobSystem.get_ability("cure"), [cleric])
	assert_gt(cleric.current_hp, 200, "cure still heals on the spot")
	assert_false(cleric.has_status("regen"), "and applies no lasting effect")


func test_a_heal_that_also_carries_an_effect_keeps_its_instant_heal() -> void:
	## No shipped ability has both today — regenerate is the only healing ability authoring an effect —
	## so this fixture is fabricated, and it pins which way the routing breaks a tie: an authored
	## heal_amount means the heal happens, whatever else the ability declares.
	var cleric := _cleric()
	BattleManager._execute_healing_ability(cleric, {"type": "healing", "heal_amount": 100, "effect": "regen",
		"regen_per_turn": REGEN_PER_TURN, "duration": DURATION}, [cleric])
	assert_gt(cleric.current_hp, 200, "the authored heal still lands")


func test_the_healing_path_routes_rather_than_copying_the_regen_arm() -> void:
	## One owner for what "regen" means. A second copy in the healing executor would pass every arm
	## above and drift from the support arm the first time either is edited — this repo's most-repeated
	## defect (heal_amount 10x, restore_mp's amounts, the bust crop in two files).
	var code: String = GdSourceHelper.code_of("res://src/battle/BattleManager.gd")
	var at: int = code.find("func _execute_healing_ability(")
	assert_gt(at, -1, "CONTROL: the healing executor survives stripping")
	var next_func: int = code.find("\nfunc ", at + 1)
	var body: String = code.substr(at, (next_func - at) if next_func > at else 3000)
	assert_true(body.contains("_execute_support_ability(caster, ability, targets)"),
		"the healing path must hand a lasting-effect ability to the support arm")
	assert_false(body.contains('add_status("regen"'),
		"and must not grow its own copy of what regen means")


const GdSourceHelper = preload("res://test/unit/helpers/gd_source.gd")
