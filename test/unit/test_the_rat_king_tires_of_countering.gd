extends GutTest

## struktured 2026-11-15, six straight Rat King wipes at L6: "the counter is exponentially less likely as it hits per round".
## A monster's n-th counter in one round fires at COUNTER_CHANCE * counter_decay^n; counter_decay is 0.5 on cave_rat_king only.

const RESOLVER := preload("res://src/autogrind/HeadlessBattleResolver.gd")
const RAT_KING := "cave_rat_king"
const UNDECAYED := "optimization_itself"

var _res = null


func before_each() -> void:
	seed(20261115)
	_res = RESOLVER.new()


## HeadlessBattleResolver is RefCounted: dropping the reference frees it.
func after_each() -> void:
	_res = null


func _make(name_str: String, monster_type: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name_str, "max_hp": 9999999, "max_mp": 0,
		"attack": 60, "defense": 50, "magic": 10, "speed": 100})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	if monster_type != "":
		c.set_meta("monster_type", monster_type)
	return c


## Counters a monster of `monster_type` throws back at `n` basic attacks landed inside ONE round.
func _counters_in_one_round(monster_type: String, n: int) -> int:
	var hero := _make("Hero", "")
	var foe := _make("Foe", monster_type)
	_res._player_party = [hero]
	_res._enemy_party = [foe]
	_res._current_round = 1
	_res._battle_log.clear()
	for i in n:
		_res._execute_action({"type": "attack", "combatant": hero, "target": foe})
	var lines := 0
	for line in _res._battle_log:
		if ("Foe answers with" in str(line)) or ("Foe counters with" in str(line)):
			lines += 1
	return lines


func _row(monster_type: String) -> Dictionary:
	return EncounterSystem.monster_database.get(monster_type, {})


func test_the_chance_halves_with_each_counter_and_resets_next_round() -> void:
	var m := Node.new()
	add_child_autofree(m)
	assert_almost_eq(RESOLVER.counter_chance(0.5, m, 3), 0.4, 0.0001, "the first counter of a round keeps the base 40%")
	RESOLVER.note_counter(m, 3)
	assert_almost_eq(RESOLVER.counter_chance(0.5, m, 3), 0.2, 0.0001, "the second counter in the same round is half as likely")
	RESOLVER.note_counter(m, 3)
	assert_almost_eq(RESOLVER.counter_chance(0.5, m, 3), 0.1, 0.0001, "the third is a quarter")
	assert_almost_eq(RESOLVER.counter_chance(0.5, m, 4), 0.4, 0.0001, "a new round starts back at the base 40%")


func test_no_decay_authored_means_the_old_flat_chance() -> void:
	var m := Node.new()
	add_child_autofree(m)
	for i in 3:
		RESOLVER.note_counter(m, 7)
	assert_almost_eq(RESOLVER.counter_chance(1.0, m, 7), 0.4, 0.0001, "counter_decay 1.0 (the default) never decays")


func test_only_the_rat_king_authors_the_decay() -> void:
	assert_almost_eq(float(_row(RAT_KING).get("counter_decay", 1.0)), 0.5, 0.0001, "cave_rat_king carries counter_decay 0.5")
	assert_false(_row(UNDECAYED).has("counter_decay"), "the control counterer stays on the flat 40%")


## The decay reaches a real swing: 40 hits in one round. Flat 40% averages 16 counters; halving caps the expected total under 0.8.
func test_forty_swings_in_one_round_draw_few_counters_from_the_rat_king() -> void:
	var control := _counters_in_one_round(UNDECAYED, 40)
	assert_gt(control, 8, "CONTROL: an undecayed counterer answers many of 40 swings (got %d); if this is low the swing path is not countering at all" % control)
	_res = RESOLVER.new()
	var rk := _counters_in_one_round(RAT_KING, 40)
	assert_lt(rk, 5, "the Rat King answers few of 40 swings in one round once each counter halves the next (got %d)" % rk)


## Live and the grind must read the same rule, or the measured win table describes a different boss.
func test_live_reads_the_shared_rule() -> void:
	var f := FileAccess.open("res://src/battle/BattleManager.gd", FileAccess.READ)
	var src := f.get_as_text()
	f.close()
	var i := src.find("func _trigger_monster_counter(")
	assert_gt(i, -1, "FLOOR: BattleManager._trigger_monster_counter is gone")
	var body := src.substr(i, src.find("\nfunc ", i + 10) - i)
	assert_string_contains(body, "HeadlessBattleResolver.counter_chance(", "live rolls through the shared chance")
	assert_string_contains(body, "HeadlessBattleResolver.note_counter(", "live records each counter it fires")
	assert_string_contains(body, "\"counter_decay\"", "live reads the monster's counter_decay")
