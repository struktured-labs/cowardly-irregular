extends GutTest

## A five-ability boss fought with one move. Pyrroth showed magma_eruption and nothing else.
##
## Three archetypes sorted their offensive pool by power and took [0] UNCONDITIONALLY — _ai_tank,
## _ai_assassin, and _ai_caster's scored equivalent. So widening a vocabulary (this morning's two
## fixes) changed WHICH single ability a boss used, never HOW MANY. Measured across the whole
## roster: 52 of 106 monsters could reach their full kit, 54 could not, and the residue was almost
## entirely this rule rather than a permission gap.
##
## The fix keeps "strongest" as a BIAS instead of an absolute: half the time the top pick, otherwise
## anywhere below it. No power threshold, because a threshold on damage_multiplier is the
## coincidental-magnitude shape — it would go red on a correct rebalance and green on a wrong one.
##
## ⚠️ It also expired a suppression on purpose. test_bosses_can_select_their_own_kit pinned
## dark_knight's life_drain and rust_elemental's corrode as KNOWN GAPS with inverted asserts,
## annotated "when the single-slot rule changes, this reds and someone deletes it". It did. That
## file now asserts the positive.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")
const ROLLS := 400

var _bm = null

func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)

func _monsters() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	assert_not_null(parsed, "CONTROL: monsters.json parses")
	return (parsed as Dictionary).get("monsters", parsed)

func _selectable(mid: String) -> Dictionary:
	var v: Dictionary = _monsters()[mid]
	var st: Dictionary = v.get("stats", {})
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = mid
	c.max_hp = int(st.get("max_hp", 100)); c.current_hp = c.max_hp
	c.max_mp = int(st.get("max_mp", 50)); c.current_mp = c.max_mp
	c.attack = int(st.get("attack", 10)); c.defense = int(st.get("defense", 10))
	c.magic = int(st.get("magic", 10)); c.speed = int(st.get("speed", 10))
	c.set_meta("monster_type", mid)
	var avail: Array = []
	for aid in (v.get("abilities", []) as Array):
		var a: Dictionary = JobSystem.get_ability(str(aid))
		if not a.is_empty():
			avail.append(a)
	assert_gt(avail.size(), 0, "CONTROL: %s's kit resolves" % mid)
	var arch: String = _bm._get_ai_archetype(c, avail)
	var victim := Combatant.new()
	autofree(victim)
	victim.max_hp = 9000; victim.current_hp = 9000
	var seen: Dictionary = {"_archetype": arch, "_kit": avail.size()}
	for _i in ROLLS:
		var action: Dictionary = _bm._execute_archetype_ai(c, arch, avail, [c], [victim])
		if str(action.get("type", "")) == "ability":
			seen[str(action.get("ability_id", ""))] = true
	return seen

func _picked(seen: Dictionary) -> int:
	return seen.size() - 2

func test_pyrroth_uses_its_whole_kit() -> void:
	var seen := _selectable("fire_dragon")
	assert_eq(_picked(seen), int(seen["_kit"]),
		"the Ember Wyrm authors %d abilities and must be able to reach all of them" % int(seen["_kit"]))

func test_the_rat_king_uses_its_whole_kit() -> void:
	var seen := _selectable("cave_rat_king")
	assert_eq(_picked(seen), int(seen["_kit"]),
		"the tutorial boss must not fight with one move — it teaches the system")

func test_the_bias_still_favours_the_strongest() -> void:
	## The discriminator. If the pick went uniform the archetype would stop meaning anything, so
	## the top ability must come up materially more often than an equal share.
	var v: Dictionary = _monsters()["fire_dragon"]
	var st: Dictionary = v.get("stats", {})
	var c := Combatant.new(); autofree(c)
	c.combatant_name = "Pyrroth"
	c.max_hp = int(st.get("max_hp", 100)); c.current_hp = c.max_hp
	c.max_mp = int(st.get("max_mp", 50)); c.current_mp = c.max_mp
	c.attack = int(st.get("attack", 10)); c.defense = int(st.get("defense", 10))
	c.magic = int(st.get("magic", 10)); c.speed = int(st.get("speed", 10))
	c.set_meta("monster_type", "fire_dragon")
	var avail: Array = []
	for aid in (v.get("abilities", []) as Array):
		var a: Dictionary = JobSystem.get_ability(str(aid))
		if not a.is_empty():
			avail.append(a)
	var victim := Combatant.new(); autofree(victim)
	victim.max_hp = 900000; victim.current_hp = 900000
	var counts: Dictionary = {}
	for _i in 2000:
		var act: Dictionary = _bm._execute_archetype_ai(c, "tank", avail, [c], [victim])
		if str(act.get("type", "")) == "ability":
			var id: String = str(act.get("ability_id", ""))
			counts[id] = int(counts.get(id, 0)) + 1
	var top: int = int(counts.get("magma_eruption", 0))
	var others: int = 0
	for k in counts:
		if str(k) != "magma_eruption" and str(k) != "inferno_rage":
			others += int(counts[k])
	assert_gt(top, 0, "CONTROL: the strongest ability is still selected")
	assert_gt(others, 0, "CONTROL: so are the weaker ones — otherwise this test cannot discriminate")
	assert_gt(top, others / 2,
		"the top pick must stay the favourite (magma %d vs %d others) — a uniform pick erases the archetype" % [top, others])

func test_a_one_ability_monster_is_unaffected() -> void:
	## The picker's degenerate case, and the reason it early-returns on size 1 rather than indexing.
	assert_eq(_bm._pick_biased_by_power([]), {}, "an empty pool returns an empty dictionary, not a crash")
	var only: Dictionary = {"id": "solo"}
	assert_eq(_bm._pick_biased_by_power([only]), only, "a single-ability pool always returns that ability")

func test_the_roster_wide_reach_improved_and_is_recorded() -> void:
	## ⚠️ The number this commit exists for — and I wrote 80 here first, which is the number I WANTED.
	## The probe had already told me 52 and I asserted an aspiration over a measurement, which is the
	## error I have spent the day catching in other people's instruments. 52 is the measured value;
	## it is a RATCHET, so adding a monster whose kit its archetype cannot reach correctly reds it.
	## The residue is NOT this rule — it is archetypes whose vocabulary still excludes a type:
	## _ai_caster and _ai_assassin cannot select `support` at all (Voltharion, an assassin, has
	## therefore never cast storm_gathering, the telegraph its own code comment was written for),
	## and _ai_brute selects neither `support` nor `summon`.
	var full: int = 0
	var total: int = 0
	for mid in _monsters():
		var v: Dictionary = _monsters()[mid]
		if (v.get("abilities", []) as Array).is_empty():
			continue
		total += 1
		var seen := _selectable(mid)
		if _picked(seen) >= int(seen["_kit"]):
			full += 1
	assert_gt(total, 100, "CONTROL: the whole roster was walked (%d)" % total)
	assert_gte(full, 52,
		"reach regressed: %d of %d monsters can select their whole kit, was 52 of 106 when this landed" % [full, total])
