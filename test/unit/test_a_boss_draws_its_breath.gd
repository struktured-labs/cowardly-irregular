extends GutTest

## BossCadence: a boss with a `cadence` row plays `every` ordinary turns, charges visibly, then releases its signature.
## A stun or silence landing mid-charge breaks the breath and the count starts over.


func _beats(cfg: Dictionary, n: int) -> Array:
	var st := BossCadence.fresh_state()
	var out: Array = []
	for i in n:
		var r: Dictionary = BossCadence.next(st, cfg)
		out.append(r["beat"])
		st = r["state"]
	return out


func _cfg(every: int, charge: int) -> Dictionary:
	return BossCadence.config({"cadence": {"signature": "absolute_zero", "every": every, "charge_turns": charge}})


func test_a_row_without_a_cadence_only_plays_plain_turns() -> void:
	assert_eq(BossCadence.config({}), {}, "no cadence key, no clock")
	assert_eq(BossCadence.config({"cadence": {"every": 2}}), {}, "a cadence naming no signature is no clock")
	assert_eq(_beats({}, 6), ["plain", "plain", "plain", "plain", "plain", "plain"])


func test_every_three_then_one_charge_then_the_release_and_round_again() -> void:
	assert_eq(_beats(_cfg(3, 1), 10),
		["plain", "plain", "plain", "charge", "release", "plain", "plain", "plain", "charge", "release"])


func test_a_longer_charge_holds_for_its_turns() -> void:
	assert_eq(_beats(_cfg(1, 2), 5), ["plain", "charge", "charge", "release", "plain"])


func test_a_stun_mid_charge_breaks_the_breath_and_the_count_restarts() -> void:
	var cfg := _cfg(2, 1)
	var st := BossCadence.fresh_state()
	for i in 3:
		st = BossCadence.next(st, cfg)["state"]
	assert_true(BossCadence.is_charging(st), "control: after plain, plain, charge the boss is charging")
	st = BossCadence.on_status(st, cfg, "stun")
	assert_false(BossCadence.is_charging(st), "the stun broke the charge")
	assert_true(bool(st["interrupted"]), "the break is reported, so the scene can say so")
	var after: Array = []
	for i in 3:
		var r: Dictionary = BossCadence.next(st, cfg)
		after.append(r["beat"])
		st = r["state"]
	assert_eq(after, ["plain", "plain", "charge"], "no release follows a broken charge; the clock starts over")


func test_a_status_that_does_not_interrupt_leaves_the_charge() -> void:
	var cfg := _cfg(1, 1)
	var st: Dictionary = BossCadence.next(BossCadence.next(BossCadence.fresh_state(), cfg)["state"], cfg)["state"]
	assert_true(BossCadence.is_charging(st), "control: charging")
	st = BossCadence.on_status(st, cfg, "poison")
	assert_true(BossCadence.is_charging(st), "poison does not break a breath")
	assert_eq(BossCadence.next(st, cfg)["beat"], "release")


func test_a_stun_while_building_does_not_reset_the_count() -> void:
	var cfg := _cfg(3, 1)
	var st: Dictionary = BossCadence.next(BossCadence.fresh_state(), cfg)["state"]
	st = BossCadence.next(st, cfg)["state"]
	st = BossCadence.on_status(st, cfg, "stun")
	assert_false(bool(st["interrupted"]), "nothing to interrupt before the charge")
	assert_eq(int(st["count"]), 2, "the count it had is kept")


func test_every_authored_cadence_names_a_signature_its_boss_can_cast() -> void:
	var mons: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	mons = mons.get("monsters", mons)
	var abil: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	abil = abil.get("abilities", abil)
	var seen := 0
	for id in mons:
		var row: Variant = mons[id]
		if not row is Dictionary or not (row as Dictionary).has("cadence"):
			continue
		seen += 1
		var cfg := BossCadence.config(row)
		assert_false(cfg.is_empty(), "%s: its cadence parses" % id)
		var sig := str(cfg.get("signature", ""))
		assert_has((row as Dictionary).get("abilities", []), sig, "%s: the signature is in its own kit" % id)
		assert_true(abil.has(sig), "%s: %s resolves in abilities.json" % [id, sig])
	assert_true(mons.has("ice_dragon") and (mons["ice_dragon"] as Dictionary).has("cadence"), "Glacius carries the first cadence")
	assert_gt(seen, 0, "floor: the walk found an authored cadence")


func _glacius() -> Combatant:
	var c: Combatant = Combatant.new()
	add_child_autofree(c)
	c.initialize({"name": "Glacius", "max_hp": 100, "max_mp": 100, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	c.set_meta("monster_type", "ice_dragon")
	return c


## The charge turn reads boss_dialogue.json, so the accessor story authors against has a reader (ai 24683, main 24685).
func test_an_authored_charge_line_is_what_the_log_says() -> void:
	var boss := _glacius()
	assert_eq(BattleManager._boss_persona_id(boss), "glacius", "CONTROL: Glacius resolves to the persona boss_dialogue.json keys")
	var entry: Dictionary = BossDialogue._data.get("glacius", {})
	var had: Variant = entry.get("charge_line", null)
	entry["charge_line"] = "PLANTED: the cavern holds its breath."
	BossDialogue._data["glacius"] = entry
	watch_signals(BattleManager)
	BattleManager._execute_boss_charge(boss, "absolute_zero")
	if had == null:
		entry.erase("charge_line")
	else:
		entry["charge_line"] = had
	var params: Array = get_signal_parameters(BattleManager, "battle_log_message")
	assert_false(params.is_empty(), "the charge turn logs a line")
	assert_string_contains(str(params[0]) if not params.is_empty() else "", "PLANTED: the cavern holds its breath.")


func test_an_unauthored_boss_gets_the_generic_line() -> void:
	var boss := _glacius()
	boss.set_meta("llm_persona_id", "nobody_authored_this_boss")
	watch_signals(BattleManager)
	BattleManager._execute_boss_charge(boss, "absolute_zero")
	var params: Array = get_signal_parameters(BattleManager, "battle_log_message")
	assert_false(params.is_empty(), "the charge turn logs a line")
	assert_string_contains(str(params[0]) if not params.is_empty() else "", "is gathering power for")


func test_a_stun_on_a_charging_boss_breaks_it_through_the_battle_manager() -> void:
	var boss := _glacius()
	var cfg: Dictionary = BattleManager._cadence_config(boss)
	assert_false(cfg.is_empty(), "CONTROL: Glacius's row reaches the battle manager's cadence reader")
	boss.set_meta("_cadence", {"phase": "charging", "count": 0, "charge_left": 1, "interrupted": false})
	watch_signals(BattleManager)
	BattleManager._on_cadence_status("stun", boss)
	assert_signal_emitted_with_parameters(BattleManager, "boss_charge_broken", [boss, "stun"])
	assert_signal_emitted_with_parameters(BattleManager, "boss_charge_changed", [boss, false])
	assert_false(BossCadence.is_charging(boss.get_meta("_cadence", {})), "the boss is no longer charging")


func test_turns_to_release_counts_down_to_the_breath() -> void:
	var cfg := _cfg(3, 1)
	var st := BossCadence.fresh_state()
	var seen: Array = [BossCadence.turns_to_release(st, cfg)]
	for i in 4:
		st = BossCadence.next(st, cfg)["state"]
		seen.append(BossCadence.turns_to_release(st, cfg))
	assert_eq(seen, [5, 4, 3, 2, 1], "plain, plain, plain, charge, then the release is the next turn")
	assert_eq(BossCadence.next(st, cfg)["beat"], "release", "and it is")
	assert_eq(BossCadence.turns_to_release(st, {}), -1, "no clock, no countdown")


## A rule can see the breath coming: both conditions read the live boss through AutobattleSystem's own evaluator.
func test_a_rule_reads_the_charge_and_the_countdown() -> void:
	var hero: Combatant = Combatant.new()
	add_child_autofree(hero)
	hero.initialize({"name": "Hero", "max_hp": 100, "max_mp": 10, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	var boss := _glacius()
	var saved_players: Array[Combatant] = BattleManager.player_party.duplicate()
	var saved_enemies: Array[Combatant] = BattleManager.enemy_party.duplicate()
	var players: Array[Combatant] = [hero]
	var enemies: Array[Combatant] = [boss]
	BattleManager.player_party = players
	BattleManager.enemy_party = enemies
	var charging := {"type": "enemy_charging"}
	var soon := {"type": "enemy_signature_in", "op": "<=", "value": 1}
	var a_far := AutobattleSystem._evaluate_grid_condition(hero, charging)
	var b_far := AutobattleSystem._evaluate_grid_condition(hero, soon)
	boss.set_meta("_cadence", {"phase": "charging", "count": 0, "charge_left": 1, "interrupted": false})
	var a_near := AutobattleSystem._evaluate_grid_condition(hero, charging)
	var b_near := AutobattleSystem._evaluate_grid_condition(hero, soon)
	BattleManager.player_party = saved_players
	BattleManager.enemy_party = saved_enemies
	assert_false(a_far, "a fresh boss is not charging")
	assert_false(b_far, "and its breath is more than one turn off")
	assert_true(a_near, "a charging boss reads as charging")
	assert_true(b_near, "and its release is the next turn")


## Glacius's own clock as BossCadence plays it, n turns from fresh: the beat each turn lands on.
func _authored_beats(boss: Combatant, n: int) -> Array:
	var cfg: Dictionary = BattleManager._cadence_config(boss)
	var st := BossCadence.fresh_state()
	var out: Array = []
	for i in n:
		var r: Dictionary = BossCadence.next(st, cfg)
		out.append(r["beat"])
		st = r["state"]
	return out


## The clock is in the real decision: Glacius's turns through the battle manager's own picker, up to his first release.
func test_glacius_charges_then_breathes_through_the_live_picker() -> void:
	var boss := _glacius()
	var hero: Combatant = Combatant.new()
	add_child_autofree(hero)
	hero.initialize({"name": "Hero", "max_hp": 100, "max_mp": 10, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	boss.job = {"abilities": ["absolute_zero", "frost_armor"], "name": "Glacius"}
	boss.set_meta("boss_dialogue_phase", 99)
	var expect: Array = _authored_beats(boss, 12)
	var first_release: int = expect.find("release")
	assert_gt(first_release, 0, "CONTROL: Glacius's authored clock releases within 12 turns: %s" % str(expect))
	var kinds: Array = []
	var sigs: Array = []
	for i in first_release + 1:
		boss.current_mp = boss.max_mp
		var a: Dictionary = BattleManager._make_ai_decision(boss, [boss], [hero], true)
		kinds.append(str(a.get("type", "")))
		sigs.append(str(a.get("ability_id", "")) == "absolute_zero" and str(a.get("type", "")) == "ability")
		if i == first_release:
			assert_eq(str(a.get("ability_id", "")), "absolute_zero", "the release turn is the breath itself")
			assert_eq((a.get("targets", []) as Array).size(), 1, "on everyone the boss can reach (one hero here)")
	assert_eq(kinds[first_release - 1], "charge", "the turn before is the visible charge: %s" % str(kinds))
	assert_eq(kinds[first_release], "ability", "and then it releases: %s" % str(kinds))
	var want: Array = []
	for b in expect.slice(0, first_release + 1):
		want.append(b == "release")
	assert_eq(sigs, want, "the breath is the clock's alone: the ladder never casts it unannounced")


## Many build turns, one breath per clock: over 25 turns the signature lands exactly on the authored release beats.
func test_the_ladder_never_casts_a_clocked_signature() -> void:
	var boss := _glacius()
	var hero: Combatant = Combatant.new()
	add_child_autofree(hero)
	hero.initialize({"name": "Hero", "max_hp": 100, "max_mp": 10, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	boss.job = {"abilities": ["absolute_zero"], "name": "Glacius"}
	boss.set_meta("boss_dialogue_phase", 99)
	var want: Array = []
	var expect: Array = _authored_beats(boss, 25)
	for i in expect.size():
		if expect[i] == "release":
			want.append(i + 1)
	assert_gt(want.size(), 1, "CONTROL: the authored clock releases more than once in 25 turns: %s" % str(want))
	var cast_on: Array = []
	for i in 25:
		boss.current_mp = boss.max_mp
		var a: Dictionary = BattleManager._make_ai_decision(boss, [boss], [hero], true)
		if str(a.get("type", "")) == "ability" and str(a.get("ability_id", "")) == "absolute_zero":
			cast_on.append(i + 1)
	assert_eq(cast_on, want, "only the release beats cast it")
