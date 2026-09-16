extends GutTest

## pre_battle_check and check_new_injuries are LIVE, each with exactly ONE real caller:
## AutogrindController:227 gates every grind battle on the first, GameLoop:5552 reads the second
## for the session injury warning. A third GameLoop mention of pre_battle_check is a COMMENT, not
## a call — counted as a consumer in my first audit pass. Neither function was named by any test. An audit of AutogrindSystem's 60 public funcs found 9 in that state.
## These two carry the real consequences: an interrupt that stops firing grinds a wiped party
## forever, and an injury count that stops rising hides permanent damage from the session report.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")

var _system
var _party: Array[Combatant] = []


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system._test_disable_persistence = true
	_party.clear()
	for i in range(3):
		var c = Combatant.new()
		c.initialize({
			"name": "Grinder%d" % i,
			"max_hp": 100, "max_mp": 20,
			"attack": 10, "defense": 10, "magic": 5, "speed": 10
		})
		add_child_autofree(c)
		_party.append(c)
	_system.grind_party = _party
	_system.battles_completed = 0
	_system.meta_corruption_level = 0.0
	## Explicit, not the shipped defaults — item_depleted defaults TRUE and a fixture party
	## carries no potions, so the shipped dict makes every "clean" case return a reason.
	_system.interrupt_rules = {
		"hp_threshold": 0.0, "party_death": false, "item_depleted": false,
		"corruption_limit": 999.0, "max_battles": 999
	}


func _injure(c: Combatant, id: String) -> void:
	## permanent_injuries is Array[DICTIONARY]; a String append aborts THIS HELPER silently.
	c.apply_permanent_injury({"id": id, "name": id})


func test_a_clean_party_is_cleared_to_fight() -> void:
	assert_eq(_system.pre_battle_check(), "",
		"with every interrupt disarmed the check must clear the battle")


func test_hp_threshold_stops_the_battle_and_says_so() -> void:
	_system.interrupt_rules["hp_threshold"] = 20.0
	_party[1].current_hp = 10
	var reason: String = _system.pre_battle_check()
	assert_ne(reason, "", "a member below the HP threshold must stop the grind")
	assert_true(reason.contains("HP"), "the reason must name HP, not just refuse")


func test_hp_threshold_does_not_fire_above_the_line() -> void:
	# ARM+. Without this the predicate could return a reason unconditionally.
	_system.interrupt_rules["hp_threshold"] = 20.0
	_party[1].current_hp = 90
	assert_eq(_system.pre_battle_check(), "", "a healthy party must not trip the HP interrupt")


func test_party_death_stops_the_battle() -> void:
	_system.interrupt_rules["party_death"] = true
	_party[2].current_hp = 0
	_party[2].is_alive = false
	var reason: String = _system.pre_battle_check()
	assert_ne(reason, "", "a dead party member must stop the grind")
	assert_true(reason.contains("died"), "the reason must name the death")


## ⛔ THE TWO RULES WERE NEVER ARMED TOGETHER. Every arm above disarms one to test the other, and
## that is how this survived: a corpse reads 0% HP, so with hp_threshold ON it tripped the HP rule
## before party_death was ever consulted. Two consequences, both player-visible — a death was
## reported as "HP threshold reached", and turning "stop on death" OFF in the console could not keep
## a grind running, because the corpse kept stopping it under the other rule's name.
func test_a_corpse_does_not_trip_the_hp_rule() -> void:
	_system.interrupt_rules["hp_threshold"] = 20.0
	_system.interrupt_rules["party_death"] = false
	_party[2].current_hp = 0
	_party[2].is_alive = false
	assert_eq(_system.pre_battle_check(), "",
		"stop-on-death is OFF, so a fallen member must not stop the grind under the HP rule — the console offers these as two independent switches")


func test_a_death_is_reported_as_a_death_not_an_hp_stop() -> void:
	## BOTH armed, which no other arm does. The stop reason reaches the player: GameLoop plays a cue
	## per reason and the Summary prints "Stopped: <reason>".
	_system.interrupt_rules["hp_threshold"] = 20.0
	_system.interrupt_rules["party_death"] = true
	_party[2].current_hp = 0
	_party[2].is_alive = false
	var reason: String = _system.pre_battle_check()
	assert_true(reason.contains("died"),
		"a death must be reported as a death; got %s" % reason)
	assert_false(reason.contains("HP"),
		"the HP rule must not claim a death — the player set two switches and deserves the right one named")


func test_a_living_member_below_the_line_still_stops_it() -> void:
	## Control for both arms above: the skip must be for the DEAD only, or the HP rule is gone.
	_system.interrupt_rules["hp_threshold"] = 20.0
	_system.interrupt_rules["party_death"] = true
	_party[1].current_hp = 10
	var reason: String = _system.pre_battle_check()
	assert_true(reason.contains("HP"),
		"a LIVING member below the threshold must still stop the grind; got %s" % reason)


func test_a_wiped_party_is_still_stopped_elsewhere() -> void:
	## The skip above is only safe because a full wipe is caught before rules are evaluated. That
	## guard lives in the controller, not here, so this pins it rather than assuming it.
	var code: String = GdSource.code_of("res://src/autogrind/AutogrindController.gd")
	assert_true(code.contains("func _process"), "CONTROL: the stripper kept the controller's process loop")
	var at: int = code.find("not m.is_alive")
	assert_gt(at, -1, "the controller must still detect an all-dead party, or skipping the dead above could grind a corpse party forever")
	assert_true(code.substr(at, 120).contains("stop_grind("),
		"detecting the wipe must STOP the grind, not merely notice it")


func test_max_battles_stops_the_battle() -> void:
	_system.interrupt_rules["max_battles"] = 5
	_system.battles_completed = 5
	assert_ne(_system.pre_battle_check(), "",
		"reaching the battle cap must stop the grind — it is the runaway backstop")


func test_corruption_limit_stops_the_battle() -> void:
	_system.interrupt_rules["corruption_limit"] = 4.5
	_system.meta_corruption_level = 4.5
	assert_ne(_system.pre_battle_check(), "",
		"corruption at the limit must stop the grind before system collapse")


func test_new_injuries_counts_only_damage_taken_this_session() -> void:
	_injure(_party[0], "cracked_rib")
	_system._injury_baseline = 1
	_injure(_party[1], "burned_hand")
	assert_eq(_system.check_new_injuries(), 1,
		"only the injury taken after the baseline counts as new")


func test_new_injuries_never_reports_negative() -> void:
	# The max(0, …) clamp: a party member leaving mid-session drops the total below baseline.
	_system._injury_baseline = 5
	assert_eq(_system.check_new_injuries(), 0,
		"a total below the baseline must clamp to 0, never a negative injury count")


func test_new_injuries_publishes_to_the_session_field() -> void:
	# GameLoop reads injuries_this_session, not the return value — a pure return is not enough.
	_injure(_party[0], "cracked_rib")
	_injure(_party[1], "burned_hand")
	_system._injury_baseline = 0
	_system.check_new_injuries()
	assert_eq(_system.injuries_this_session, 2,
		"check_new_injuries must publish to injuries_this_session, which is what the report reads")
