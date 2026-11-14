extends GutTest

## The party saw a boss gather its signature (.799); breaking that charge with a stun or a sleep went unremarked.
## The enemy snapshot carries `charge_broken` until the boss's next turn, the `enemy_charge_broken` tag holds on it,
## each starter has a line for the moment, and the LLM party-line prompt names the boss whose charge broke.

const DP := preload("res://src/llm/DialoguePrompts.gd")
const TAGS := preload("res://src/llm/VoiceLineTags.gd")
const STARTERS: Array[String] = ["fighter", "cleric", "mage", "rogue", "bard"]


func _foe(name: String, broken: bool, hp: float = 80.0, charging: bool = false) -> Dictionary:
	return {"name": name, "hp_pct": hp, "charging": charging, "charge_broken": broken}


func _ctx(enemies: Array) -> PartyCombatLineContext:
	var c := PartyCombatLineContext.new()
	c.event_kind = PartyCombatLineContext.EVENT_TURN_START
	c.speaker_name = "Brom"
	c.speaker_job_id = "fighter"
	c.party = [{"name": "Brom", "job_id": "fighter", "hp_pct": 100.0, "is_alive": true},
		{"name": "Mira", "job_id": "cleric", "hp_pct": 100.0, "is_alive": true}]
	c.enemies = enemies
	return c


func _combatant(cname: String, hp: int = 500) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": cname, "max_hp": hp, "max_mp": 50, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func _snapshot(boss_clock: Dictionary) -> Array:
	var pc := _combatant("Brom")
	var boss := _combatant("Glacius")
	boss.set_meta("_cadence", boss_clock)
	var slime := _combatant("Slime", 50)
	var saved_party: Array[Combatant] = BattleManager.player_party
	var saved_enemies: Array[Combatant] = BattleManager.enemy_party
	var party: Array[Combatant] = [pc]
	var foes: Array[Combatant] = [boss, slime]
	BattleManager.player_party = party
	BattleManager.enemy_party = foes
	var ctx: PartyCombatLineContext = BattleManager._build_party_line_context(pc, "turn_start", {})
	BattleManager.player_party = saved_party
	BattleManager.enemy_party = saved_enemies
	return ctx.enemies


func test_the_battle_snapshot_says_whose_charge_broke_until_it_acts_again() -> void:
	var cfg: Dictionary = BossCadence.config(EncounterSystem.monster_database.get("ice_dragon", {}))
	assert_false(cfg.is_empty(), "CONTROL: ice_dragon carries a cadence row")
	if cfg.is_empty():
		return
	var clock: Dictionary = BossCadence.fresh_state()
	for i in int(cfg["every"]) + 1:
		clock = BossCadence.next(clock, cfg)["state"]
	assert_true(BossCadence.is_charging(clock), "CONTROL: every+1 turns put the clock into its charge")
	var interrupt: String = str((cfg["interrupted_by"] as Array)[0])
	var broken: Dictionary = BossCadence.on_status(clock, cfg, interrupt)
	var charging_rows: Array = _snapshot(clock)
	var broken_rows: Array = _snapshot(broken)
	var acted_rows: Array = _snapshot(BossCadence.next(broken, cfg)["state"])
	assert_eq(broken_rows.size(), 2, "CONTROL: both enemies are in the snapshot")
	assert_eq([bool(charging_rows[0].get("charge_broken", true)), bool(broken_rows[0].get("charge_broken", false)),
		bool(broken_rows[1].get("charge_broken", true)), bool(acted_rows[0].get("charge_broken", true))],
		[false, true, false, false],
		"still charging: not broken; %s landed: broken (the slime is not); the boss's next turn clears it" % interrupt)


func test_the_tag_holds_only_while_a_living_enemy_has_just_been_broken() -> void:
	assert_true(TAGS.is_moment_tag("enemy_charge_broken"), "a broken charge is rare enough to outrank the generic pool")
	assert_true(TAGS.tag_holds("enemy_charge_broken", _ctx([_foe("Glacius", true), _foe("Slime", false)])), "broken: holds")
	assert_false(TAGS.tag_holds("enemy_charge_broken", _ctx([_foe("Glacius", false, 80.0, true), _foe("Slime", false)])),
		"still charging is not broken")
	assert_false(TAGS.tag_holds("enemy_charge_broken", _ctx([_foe("Glacius", true, 0.0), _foe("Slime", false)])), "a dead boss is no news")
	assert_false(TAGS.tag_holds("enemy_charge_broken", _ctx([{"name": "Old", "hp_pct": 80.0}])), "a snapshot without the key reads not broken")


func test_every_starter_has_a_line_for_the_break_and_it_wins_the_turn() -> void:
	var broken := _ctx([_foe("Glacius", true), _foe("Slime", false)])
	var charging := _ctx([_foe("Glacius", false, 80.0, true), _foe("Slime", false)])
	var missing: Array = []
	for job in STARTERS:
		var picked: Array = PartyPersonas.eligible_trigger_entries(job, "turn_start", broken)
		var ok: bool = not picked.is_empty() and picked.all(func(e): return (e["tags"] as Array).has("enemy_charge_broken"))
		var leaks: bool = PartyPersonas.eligible_trigger_entries(job, "turn_start", charging).any(
			func(e): return (e["tags"] as Array).has("enemy_charge_broken"))
		if not ok or leaks:
			missing.append(job)
	assert_eq(missing, [], "each starter speaks its break line once a charge breaks, and never while it is still gathering")


func test_the_llm_is_told_whose_charge_broke() -> void:
	var broken: String = DP.build_party_line("a fighter", [], _ctx([_foe("Glacius", true), _foe("Slime", false)]).to_dict())
	var charging: String = DP.build_party_line("a fighter", [], _ctx([_foe("Glacius", false, 80.0, true), _foe("Slime", false)]).to_dict())
	assert_string_contains(broken, "Glacius: HP 80%, CHARGE BROKEN", "the broken boss is named")
	assert_false(broken.contains("Slime: HP 80%, CHARGE"), "and the slime is not")
	assert_false(charging.contains("CHARGE BROKEN"), "a boss still gathering is not reported broken")
	assert_string_contains(charging, "GATHERING POWER", "CONTROL: the charging marker is unchanged")
