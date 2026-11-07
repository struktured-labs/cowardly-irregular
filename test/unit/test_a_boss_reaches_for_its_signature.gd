extends GutTest

## The 3-path sweep's one real gap (battle 23034, main 23035): every W1 boss carries a signature that is wired, sequenced,
## carded and tested by CASTING it directly, but nothing proved the boss's own AI ever CHOOSES it. An archetype can lock a
## boss out of abilities in its own kit (the TANK/permission findings), so a signature could ship and never be seen.
## This drives the REAL _make_ai_decision at full, 66% and 33% HP, seeded, and needs the signature picked at least once.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")
const W1_BOSSES := ["cave_rat_king", "fire_dragon", "ice_dragon", "lightning_dragon", "shadow_dragon", "chancellor_mordaine"]
const HP_PHASES := [1.0, 0.66, 0.33]
const ROLLS_PER_PHASE := 300
const SEED := 20261107

var _bm = null


func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)
	seed(SEED)


func _monsters() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	assert_not_null(parsed, "CONTROL: monsters.json parses")
	return (parsed as Dictionary).get("monsters", parsed)


func _from_data(mid: String) -> Combatant:
	var v: Dictionary = _monsters()[mid]
	var st: Dictionary = v.get("stats", {})
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = mid
	c.max_hp = int(st.get("max_hp", 100)); c.current_hp = c.max_hp
	c.max_mp = int(st.get("max_mp", 9999)); c.current_mp = c.max_mp
	c.attack = int(st.get("attack", 10)); c.defense = int(st.get("defense", 10))
	c.magic = int(st.get("magic", 10)); c.magic_defense = int(st.get("magic_defense", 10))
	c.speed = int(st.get("speed", 10))
	c.set_meta("monster_type", mid)
	c.job = {"id": mid, "abilities": (v.get("abilities", []) as Array).duplicate()}
	return c


func _member(job_id: String) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = job_id
	c.max_hp = 5000; c.current_hp = 5000
	c.job = {"id": job_id, "abilities": []}
	return c


## The W1 party (it always carries a Cleric, which some intents filter for).
func _party() -> Array:
	return [_member("fighter"), _member("cleric"), _member("mage"), _member("rogue"), _member("bard")]


## {phase_frac: {ability_id: count}} over the REAL decision path. Phase transitions run as in a fight (HP descends).
func _choices(mid: String) -> Dictionary:
	var boss := _from_data(mid)
	var foes := _party()
	var out := {}
	for frac in HP_PHASES:
		var counts := {}
		for _i in ROLLS_PER_PHASE:
			boss.current_hp = maxi(1, int(boss.max_hp * frac))
			boss.current_mp = boss.max_mp
			var action: Dictionary = _bm._make_ai_decision(boss, [boss], foes)
			var aid := str(action.get("ability_id", "")) if str(action.get("type", "")) == "ability" else str(action.get("type", ""))
			counts[aid] = int(counts.get(aid, 0)) + 1
		out[frac] = counts
	return out


func test_every_w1_boss_chooses_its_signature_in_a_real_fight() -> void:
	var monsters := _monsters()
	var never: Array = []
	for mid in W1_BOSSES:
		var sig := str((monsters[mid] as Dictionary).get("fx_signature", ""))
		assert_ne(sig, "", "CONTROL: %s authors an fx_signature" % mid)
		assert_true(sig in (monsters[mid] as Dictionary).get("abilities", []), "CONTROL: %s's signature %s is in its kit" % [mid, sig])
		var by_phase := _choices(mid)
		var picked := 0
		var other := 0
		for frac in by_phase:
			for aid in by_phase[frac]:
				if aid == sig:
					picked += int(by_phase[frac][aid])
				elif aid != "":
					other += int(by_phase[frac][aid])
		gut.p("  %s (%s): %s" % [mid, sig, str(by_phase)])
		assert_gt(other, 0, "CONTROL: %s chose something other than its signature, so the count is about choice" % mid)
		if picked == 0:
			never.append("%s never chose %s over %d rolls at %s HP" % [mid, sig, ROLLS_PER_PHASE * HP_PHASES.size(), str(HP_PHASES)])
	assert_eq(never, [], "a W1 boss's own AI never reaches for its signature, so a player never sees it")


func test_a_kit_without_the_signature_never_chooses_it() -> void:
	var boss := _from_data("fire_dragon")
	var sig := str((_monsters()["fire_dragon"] as Dictionary).get("fx_signature", ""))
	(boss.job["abilities"] as Array).erase(sig)
	var foes := _party()
	var seen_any := 0
	for _i in ROLLS_PER_PHASE:
		boss.current_hp = boss.max_hp
		boss.current_mp = boss.max_mp
		var action: Dictionary = _bm._make_ai_decision(boss, [boss], foes)
		assert_ne(str(action.get("ability_id", "")), sig, "CONTROL: a signature outside the kit cannot be chosen")
		seen_any += 1 if not action.is_empty() else 0
	assert_gt(seen_any, 0, "CONTROL: the decision path ran")
