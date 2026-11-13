extends GutTest

## A boss now gathers its signature on a clock (cowir-battle .795), but the party's own lines never noticed it.
## The enemy snapshot carries `charging`, the `enemy_charging` tag holds on it, each starter job has a line
## for that moment, and the LLM party-line prompt says which enemy is gathering power.

const DP := preload("res://src/llm/DialoguePrompts.gd")
const TAGS := preload("res://src/llm/VoiceLineTags.gd")
const STARTERS: Array[String] = ["fighter", "cleric", "mage", "rogue", "bard"]


func _foe(name: String, charging: bool, hp: float = 80.0) -> Dictionary:
	return {"name": name, "hp_pct": hp, "charging": charging}


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


func test_the_battle_snapshot_says_who_is_charging() -> void:
	var pc := _combatant("Brom")
	var boss := _combatant("Glacius")
	var cfg: Dictionary = BossCadence.config(EncounterSystem.monster_database.get("ice_dragon", {}))
	assert_false(cfg.is_empty(), "CONTROL: ice_dragon carries a cadence row")
	if cfg.is_empty():
		return
	var clock: Dictionary = BossCadence.fresh_state()
	for i in int(cfg["every"]) + 1:
		clock = BossCadence.next(clock, cfg)["state"]
	assert_true(BossCadence.is_charging(clock), "CONTROL: every+1 turns put the clock into its charge")
	boss.set_meta("_cadence", clock)
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
	assert_eq(ctx.enemies.size(), 2, "CONTROL: both enemies are in the snapshot")
	assert_eq([bool(ctx.enemies[0].get("charging", false)), bool(ctx.enemies[1].get("charging", true))], [true, false],
		"the charging boss reads charging; the slime with no clock does not")


func test_the_tag_holds_only_while_a_living_enemy_charges() -> void:
	assert_true(TAGS.is_moment_tag("enemy_charging"), "a charge is rare enough to outrank the generic pool")
	assert_true(TAGS.tag_holds("enemy_charging", _ctx([_foe("Glacius", true), _foe("Slime", false)])), "a boss charging: holds")
	assert_false(TAGS.tag_holds("enemy_charging", _ctx([_foe("Glacius", false), _foe("Slime", false)])), "nobody charging: does not")
	assert_false(TAGS.tag_holds("enemy_charging", _ctx([_foe("Glacius", true, 0.0), _foe("Slime", false)])), "a dead boss's clock is not a threat")
	assert_false(TAGS.tag_holds("enemy_charging", _ctx([{"name": "Old", "hp_pct": 80.0}])), "a snapshot without the key reads not charging")


func test_every_starter_has_a_line_for_the_charge_and_it_wins_the_turn() -> void:
	var charging := _ctx([_foe("Glacius", true), _foe("Slime", false)])
	var calm := _ctx([_foe("Glacius", false), _foe("Slime", false)])
	var missing: Array = []
	for job in STARTERS:
		var picked: Array = PartyPersonas.eligible_trigger_entries(job, "turn_start", charging)
		var ok: bool = not picked.is_empty() and picked.all(func(e): return (e["tags"] as Array).has("enemy_charging"))
		var leaks: bool = PartyPersonas.eligible_trigger_entries(job, "turn_start", calm).any(
			func(e): return (e["tags"] as Array).has("enemy_charging"))
		if not ok or leaks:
			missing.append(job)
	assert_eq(missing, [], "each starter speaks its charge line while a boss charges, and never while none does")


func test_the_llm_is_told_which_enemy_is_gathering_power() -> void:
	var charging: String = DP.build_party_line("a fighter", [], _ctx([_foe("Glacius", true), _foe("Slime", false)]).to_dict())
	var calm: String = DP.build_party_line("a fighter", [], _ctx([_foe("Glacius", false), _foe("Slime", false)]).to_dict())
	assert_string_contains(charging, "Glacius: HP 80%, GATHERING POWER", "the charging boss is named as gathering power")
	assert_false(charging.contains("Slime: HP 80%, GATHERING"), "and the slime is not")
	assert_false(calm.contains("GATHERING POWER"), "with nobody charging the prompt is as before")
