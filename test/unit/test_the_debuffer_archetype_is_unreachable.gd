extends GutTest

## The debuffer archetype cannot be reached, and if it were, it could not find a debuff.
##
## TWO DEAD LOOKUPS IN SERIES, which is why neither ever surfaced — repairing either one alone
## changes nothing observable, so nobody repairing one would have seen a result.
##
##   1. _get_ai_archetype returns "debuffer" only when the combatant has an ability whose TYPE is
##      "debuff" or "status". abilities.json authors NEITHER type; the ten that exist are escape,
##      healing, magic, meta, mp_restore, physical, revival, song, summon, support. So the arm is
##      permanently false.
##   2. The other route in is monsters.json `ai_pattern`, an explicit override. ZERO of 106 monsters
##      author that key.
##   3. And _ai_debuffer's own body filters on the same two absent types, so even a monster forced
##      into the archetype would find an empty pool and fall through to its offensive branch.
##
## ⛔ THIS FILE DELIBERATELY DOES NOT FIX IT. Debuffs are all `support`-typed, and as of today every
## archetype can select support through the shared utility slot — so a monster with a debuff already
## uses it, whatever archetype it lands in. Making the classifier live would reclassify 26 monsters
## for a behaviour they already have. That is a design call, not a repair, and it is struktured's.
##
## What this file IS for: the arm and the body look like working code, and a reader who repairs
## _ai_debuffer's filter will see nothing change and reasonably conclude their fix was wrong. Every
## assert below is INVERTED and expires the moment its reason does — author one debuff-typed ability
## or one ai_pattern and this goes red naming what changed.

const SRC := "res://src/battle/BattleManager.gd"

## ⚠️ monsters.json has NO "monsters" wrapper — the root IS the roster. `.get("monsters", {})`
## therefore returns an EMPTY dictionary, silently, and every loop over it does nothing. My first
## version of this file used that default in two places and the archetype walk produced zero
## archetypes; the CONTROL is the only reason it did not read as "debuffer is unreachable, proven".
func _monsters() -> Dictionary:
	var d: Dictionary = _json("res://data/monsters.json")
	return d.get("monsters", d)

func _json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_not_null(parsed, "CONTROL: %s parses" % path)
	return parsed

func test_no_ability_authors_a_debuff_or_status_type() -> void:
	var d: Dictionary = _json("res://data/abilities.json")
	var ab: Dictionary = d.get("abilities", d)
	var offenders: Array = []
	var types: Dictionary = {}
	for aid in ab:
		var t: String = str((ab[aid] as Dictionary).get("type", ""))
		types[t] = true
		if t in ["debuff", "status"]:
			offenders.append(aid)
	assert_gt(types.size(), 5, "CONTROL: the type vocabulary read non-empty (%s)" % str(types.keys()))
	assert_eq(offenders.size(), 0,
		"an ability now authors a debuff/status type, so the classifier's arm is LIVE — delete this file and decide what _ai_debuffer should do: " + str(offenders))

func test_no_monster_authors_an_ai_pattern() -> void:
	var d: Dictionary = _json("res://data/monsters.json")
	var mons: Dictionary = d.get("monsters", d)
	var authored: Array = []
	for mid in mons:
		if (mons[mid] as Dictionary).has("ai_pattern"):
			authored.append(mid)
	assert_gt(mons.size(), 50, "CONTROL: the roster read non-empty (%d)" % mons.size())
	assert_eq(authored.size(), 0,
		"a monster now overrides its archetype by hand, so the second route in is LIVE: " + str(authored))

func test_both_filters_still_name_the_absent_types() -> void:
	## If someone repairs ONE of the two, this reds and names which — the point being that repairing
	## one alone is invisible, and the reader deserves to know the other exists.
	var src := FileAccess.get_file_as_string(SRC)
	assert_gt(src.length(), 1000, "CONTROL: read BattleManager")
	var classifier: int = src.count("var debuff_abilities = available_abilities.filter(func(a): return a.get(\"type\", \"\") in [\"debuff\", \"status\"])")
	var body: int = src.count("var debuff_abilities = abilities.filter(func(a): return a.get(\"type\", \"\") in [\"debuff\", \"status\"])")
	assert_eq(classifier, 1, "the classifier's debuff filter moved — if you made it live, the BODY at _ai_debuffer is the other half")
	assert_eq(body, 1, "_ai_debuffer's filter moved — if you made it live, the CLASSIFIER is the other half and still cannot route to you")

func test_the_archetype_the_classifier_can_actually_return() -> void:
	## Behavioural half: walk the real roster through the real classifier and confirm "debuffer"
	## never comes out. A source-level claim about a filter is not a claim about a result.
	var bm = load("res://src/battle/BattleManager.gd").new()
	add_child_autofree(bm)
	var mons: Dictionary = _monsters()
	var seen: Dictionary = {}
	for mid in mons:
		var v: Dictionary = mons[mid]
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
		if avail.is_empty():
			continue
		seen[bm._get_ai_archetype(c, avail)] = true
	assert_gt(seen.size(), 3, "CONTROL: the classifier produced several archetypes (%s)" % str(seen.keys()))
	assert_false(seen.has("debuffer"),
		"the debuffer archetype is now REACHABLE — this file's whole premise expired, delete it")

func test_debuffs_are_reachable_anyway_which_is_why_this_is_not_a_bug() -> void:
	## The reason this is documentation and not a defect report: debuff abilities are `support`, and
	## every archetype can select support through the shared utility slot as of today. spiteful_crow
	## is an assassin carrying taunt; it reaches it without the debuffer archetype existing.
	var bm = load("res://src/battle/BattleManager.gd").new()
	add_child_autofree(bm)
	var mons: Dictionary = _monsters()
	var v: Dictionary = mons["spiteful_crow"]
	var st: Dictionary = v.get("stats", {})
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "spiteful_crow"
	c.max_hp = int(st.get("max_hp", 100)); c.current_hp = c.max_hp
	c.max_mp = 99999; c.current_mp = 99999
	c.attack = int(st.get("attack", 10)); c.defense = int(st.get("defense", 10))
	c.magic = int(st.get("magic", 10)); c.speed = int(st.get("speed", 10))
	c.set_meta("monster_type", "spiteful_crow")
	var avail: Array = []
	for aid in (v.get("abilities", []) as Array):
		var a: Dictionary = JobSystem.get_ability(str(aid))
		if not a.is_empty():
			avail.append(a)
	var arch: String = bm._get_ai_archetype(c, avail)
	var hero := Combatant.new()
	autofree(hero)
	hero.max_hp = 900000; hero.current_hp = 900000
	var seen: Dictionary = {}
	for _i in 400:
		var act: Dictionary = bm._execute_archetype_ai(c, arch, avail, [c], [hero])
		if str(act.get("type", "")) == "ability":
			seen[str(act.get("ability_id", ""))] = true
	assert_ne(arch, "debuffer", "CONTROL: it is not classified as a debuffer")
	assert_true(seen.has("taunt") or seen.has("steal"),
		"and it reaches its support abilities regardless — the archetype is redundant, not missing")
