extends GutTest

## The Masterite ladder is fine — and the check that says so did not exist, which cost me an hour.
##
## 24 Masterites across five worlds route through _make_masterite_decision instead of the archetype
## ladder, so every reachability sweep I ran today deliberately EXCLUDED them. When I finally probed
## the path, three separate probes agreed the wardens select one ability forever and deal zero damage
## — which would have meant the whole specialised AI for a shipped system never ran.
##
## ⛔ IT WAS MY FIXTURE. I built the boss from monsters.json stats and metas and never gave it a
## `job` dict, so knows_ability was false for its entire kit, can_use_ability refused every cast, and
## _execute_ability returned before doing anything. The decision function kept choosing proclamation
## (it reads a separately-passed ability list), the buff never landed, the "open with proclamation if
## you have no buffs" gate never closed, and the boss proclaimed forever. Every symptom of a real
## defect, produced entirely by an absent field a real spawn always sets.
##
## Three probes agreeing is not corroboration when all three share a fixture. The isolated bisection
## that DISAGREED was the one telling the truth, and I nearly discarded it as the odd one out.
##
## So: this file gives the path the check the archetype paths have had since this morning.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")
const TURNS := 12

var _bm = null

func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)

func _monsters() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	assert_not_null(parsed, "CONTROL: monsters.json parses")
	return (parsed as Dictionary).get("monsters", parsed)

## Shaped the way BattleEnemySpawner leaves a monster: stats, metas, AND a job carrying its kit.
func _boss(mid: String, with_job: bool = true) -> Combatant:
	var v: Dictionary = _monsters()[mid]
	var st: Dictionary = v.get("stats", {})
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = mid
	c.max_hp = int(st.get("max_hp", 5000)); c.current_hp = c.max_hp
	c.max_mp = 99999; c.current_mp = 99999
	c.attack = int(st.get("attack", 100)); c.defense = int(st.get("defense", 100))
	c.magic = int(st.get("magic", 100)); c.magic_defense = int(st.get("magic_defense", 100))
	c.speed = int(st.get("speed", 10))
	c.set_meta("monster_type", mid)
	c.set_meta("masterite", true)
	c.set_meta("masterite_type", str(v.get("masterite_type", "")))
	if with_job:
		c.job = {"id": mid, "abilities": (v.get("abilities", []) as Array).duplicate()}
	return c

func _run(mid: String, with_job: bool = true) -> Dictionary:
	var boss := _boss(mid, with_job)
	var hero := Combatant.new()
	autofree(hero)
	hero.combatant_name = "Hero"
	hero.max_hp = 400000; hero.current_hp = 400000
	hero.defense = 300; hero.magic_defense = 300
	_bm.player_party.clear(); _bm.player_party.append(hero)
	_bm.enemy_party.clear(); _bm.enemy_party.append(boss)
	var avail: Array = []
	for aid in ((_monsters()[mid] as Dictionary).get("abilities", []) as Array):
		var a: Dictionary = JobSystem.get_ability(str(aid))
		if not a.is_empty():
			avail.append(a)
	assert_gt(avail.size(), 2, "CONTROL: %s's kit resolves (%d)" % [mid, avail.size()])
	var seen: Dictionary = {}
	var damage: int = 0
	for _i in TURNS:
		boss.current_mp = 99999
		var act: Dictionary = _bm._make_masterite_decision(boss, [boss], [hero], avail)
		var before: int = hero.current_hp
		if str(act.get("type", "")) == "ability":
			var id: String = str(act.get("ability_id", ""))
			if id != "":
				seen[id] = true
				_bm._execute_ability(boss, id, act.get("targets", [hero]))
		else:
			_bm._execute_attack(boss, hero)
		damage += before - hero.current_hp
	return {"picked": seen.size(), "damage": damage, "buffs": boss.active_buffs.size()}

func test_a_warden_gets_past_its_opening_proclamation() -> void:
	var r := _run("masterite_warden_medieval")
	assert_gt(int(r["buffs"]), 0,
		"the proclamation must LAND — the ladder gates on 'no buffs yet', so a buff that never lands wedges it")
	assert_gt(int(r["picked"]), 1,
		"a warden must reach more than its opener, got %d distinct abilities" % int(r["picked"]))

func test_two_generic_buffs_on_different_stats_coexist() -> void:
	## THE MECHANISM. add_buff dedupes on the effect NAME, and the generic masterite arm labelled
	## every buff "Empower" (and every debuff "Sap"). So a second cast hit the refresh branch, which
	## updates duration and modifier and NEVER the stat — leaving one entry carrying whichever stat
	## landed first. Measured before the fix: proclamation (defense) then counter_stance (attack)
	## then haste (speed) left exactly ONE buff, stat "defense".
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Arbiter"
	c.max_hp = 5000; c.current_hp = 5000
	c.max_mp = 999; c.current_mp = 999
	c.attack = 100; c.defense = 100; c.speed = 100
	_bm._execute_support_ability(c, JobSystem.get_ability("masterite_proclamation"), [c])
	_bm._execute_support_ability(c, JobSystem.get_ability("masterite_counter_stance"), [c])
	_bm._execute_support_ability(c, JobSystem.get_ability("masterite_haste"), [c])
	assert_eq(c.active_buffs.size(), 3, "three buffs on three stats must be three entries")
	for stat in ["defense", "attack", "speed"]:
		assert_true(c.active_buffs.any(func(b): return str(b.get("stat", "")) == stat),
			"a %s buff must be present and findable by stat — the ladder gates read exactly this" % stat)

func test_two_generic_debuffs_on_different_stats_coexist() -> void:
	## The debuff twin, pinned separately because reverting it alone failed NOTHING — the buff tests
	## could not see it, and an unpinned change is an unjustified one. masterite_slow and
	## masterite_time_tax both target speed, so their collapse is invisible; masterite_resource_cut
	## targets magic, and under the shared "Sap" label it was silently folded into whichever landed
	## first.
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Victim"
	c.max_hp = 5000; c.current_hp = 5000
	c.max_mp = 999; c.current_mp = 999
	c.attack = 100; c.magic = 100; c.speed = 100
	_bm._execute_support_ability(c, JobSystem.get_ability("masterite_slow"), [c])
	_bm._execute_support_ability(c, JobSystem.get_ability("masterite_resource_cut"), [c])
	assert_eq(c.active_debuffs.size(), 2, "a speed debuff and a magic debuff must be two entries")
	assert_true(c.active_debuffs.any(func(b): return str(b.get("stat", "")) == "speed"), "speed debuff present")
	assert_true(c.active_debuffs.any(func(b): return str(b.get("stat", "")) == "magic"),
		"magic debuff present — under one shared label it was folded into the speed entry")

func test_the_arbiter_stops_posturing_and_attacks() -> void:
	## The consequence. `has_atk_buff` gates its stance; with every buff collapsed onto the
	## proclamation's DEFENSE entry that gate could never close, so it re-cast counter stance every
	## turn and dealt ZERO damage over 12 turns.
	var r := _run("masterite_arbiter_medieval")
	assert_gt(int(r["damage"]), 0, "the Arbiter must reach its strikes")
	assert_gte(int(r["picked"]), 3, "and use more than a stance, got %d distinct" % int(r["picked"]))

func test_the_tempo_stops_re_hasting_itself() -> void:
	## Same gate, `has_spd_buff`. Tempo is a debuffer so its damage is low by design — the property
	## that matters is that it gets PAST haste, not that it hits hard.
	var r := _run("masterite_tempo_medieval")
	assert_gte(int(r["picked"]), 3,
		"the Tempo must reach its slows and strike, got %d distinct" % int(r["picked"]))

func test_the_two_that_already_worked_still_do() -> void:
	## CONTROL. Warden and Curator gate on nothing that collapsed, so they fought correctly before
	## this fix and must be unchanged by it — otherwise the repair moved something it should not.
	for mid in ["masterite_warden_medieval", "masterite_curator_medieval"]:
		var r := _run(mid)
		assert_gt(int(r["damage"]), 0, "%s dealt no damage" % mid)
		assert_gte(int(r["picked"]), 2, "%s must use more than its opener" % mid)

func test_a_masterite_without_a_job_dict_is_inert_and_that_is_the_fixture_trap() -> void:
	## Pinned deliberately, because this is what a broken probe looks like and the next person to
	## build one from monsters.json alone will see exactly this and believe the AI is wedged.
	var with_job := _run("masterite_warden_medieval", true)
	var without := _run("masterite_warden_medieval", false)
	assert_gt(int(with_job["damage"]), 0, "CONTROL: a properly-built boss fights")
	assert_eq(int(without["damage"]), 0,
		"a boss with no job dict knows no abilities, so can_use_ability refuses every cast and it proclaims forever")
	assert_eq(int(without["picked"]), 1, "and it never gets past the opener")

func test_the_roster_all_routes_through_this_ladder() -> void:
	## Names the population, so a Masterite added without the flag surfaces rather than quietly
	## falling into the archetype path this file does not cover.
	var mons := _monsters()
	var flagged: Array = []
	for mid in mons:
		if bool((mons[mid] as Dictionary).get("masterite", false)):
			flagged.append(mid)
	assert_eq(flagged.size(), 24,
		"the Masterite roster changed (%d, was 24) — check the newcomers reach their kit" % flagged.size())
