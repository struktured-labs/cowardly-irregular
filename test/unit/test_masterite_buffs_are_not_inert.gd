extends GutTest

## Every Masterite buff and debuff applied at exactly 1.0. The log said "+0%".
##
## _execute_support_ability reads `stat_modifier`. The generic `buff` and `debuff` arms — the whole
## masterite_* family — author `modifier` instead. The key is absent, the default is 1.0, and
## add_buff stored a ×1.0 entry: an icon, a duration, a log line, and no arithmetic. Measured before
## the fix, masterite_proclamation on a 100-defense boss left defense at 100 while announcing
## "DEFENSE +0% for 3 turns".
##
## Seven abilities, 28 monsters: all 24 Masterites across five worlds, plus four of the five
## Spotlight Duel minibosses (fighter_skeleton_knight, mage_prismatic_construct,
## bard_hostile_courtier, rogue_lockward). Their defensive identity — Iron Guard, Counter Stance,
## Haste, Slow, Time Tax, Resource Cut — has never done anything.
##
## No ability authors BOTH keys, so reading `modifier` as the fallback is unambiguous rather than a
## precedence guess. That is checked below, because "they never collide" is exactly the premise that
## turns a safe fallback into a silent override later.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")

var _bm = null

func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)

func _abilities() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	assert_not_null(parsed, "CONTROL: abilities.json parses")
	return (parsed as Dictionary).get("abilities", parsed)

func _target() -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Subject"
	c.max_hp = 1000; c.current_hp = 1000
	c.max_mp = 999; c.current_mp = 999
	c.attack = 100; c.defense = 100; c.magic = 100; c.magic_defense = 100; c.speed = 100
	return c

## Applies the ability to a fresh target and returns its buffed value for the stat it names.
func _applied(aid: String) -> int:
	var ab: Dictionary = JobSystem.get_ability(aid)
	assert_false(ab.is_empty(), "CONTROL: %s resolves through JobSystem" % aid)
	var c := _target()
	_bm._execute_support_ability(c, ab, [c])
	return c.get_buffed_stat(str(ab.get("stat", "attack")), 100)

func test_the_proclamation_actually_raises_defense() -> void:
	assert_eq(_applied("masterite_proclamation"), 130,
		"authored modifier is 1.3 — before this fix it applied 1.0 and defense stayed 100")

func test_iron_guard_and_counter_stance_land() -> void:
	assert_eq(_applied("masterite_iron_guard"), 150, "Iron Guard authors 1.5 on defense")
	assert_eq(_applied("masterite_counter_stance"), 140, "Counter Stance authors 1.4 on attack")

func test_the_debuff_half_lands_too() -> void:
	## Same arm, opposite direction — a fallback that only fixed buffs would leave Slow inert and
	## look correct in every test that only checked a buff.
	assert_eq(_applied("masterite_slow"), 60, "Slow authors 0.6 on speed")
	assert_eq(_applied("masterite_resource_cut"), 70, "Resource Cut authors 0.7 on magic")

func test_abilities_that_author_stat_modifier_are_unchanged() -> void:
	## The discriminator. 50 abilities author stat_modifier and must be untouched by the fallback;
	## if the fallback took precedence instead of filling in, every one of them would shift.
	##
	## ⚠️ Not routed through _applied(): protect authors effect=defense_up and NO `stat` key, so the
	## helper's `ability.get("stat", "attack")` looked at the wrong stat and reported 100. The code
	## was right and my probe was reading the wrong column — named here because the failure looked
	## exactly like the defect this file is about.
	var ab: Dictionary = JobSystem.get_ability("protect")
	assert_true(ab.has("stat_modifier"), "CONTROL: protect authors stat_modifier, not modifier")
	assert_false(ab.has("stat"), "CONTROL: and no `stat` key — its arm hardcodes defense")
	var c := _target()
	_bm._execute_support_ability(c, ab, [c])
	assert_eq(c.get_buffed_stat("defense", 100), 150,
		"protect must still apply its own 1.5")

	## ⚠️ AND THE LIMIT OF THIS TEST, measured rather than assumed: inverting the fallback to read
	## `modifier` FIRST fails NOTHING. It cannot — no ability authors both keys, so the two orderings
	## are behaviourally identical on this corpus. The ordering is therefore NOT pinned by behaviour,
	## and test_no_ability_authors_both_keys is the guard that matters: it keeps the question
	## unobservable, and reds the moment it stops being.

func test_no_ability_authors_both_keys() -> void:
	## The premise the fallback rests on, measured. If an ability ever authors both, one of them is
	## being silently ignored and this stops being a fill-in and becomes a precedence decision.
	var ab := _abilities()
	var both: Array = []
	var only_modifier: Array = []
	for aid in ab:
		var v: Dictionary = ab[aid]
		if v.has("modifier") and v.has("stat_modifier"):
			both.append(aid)
		elif v.has("modifier"):
			only_modifier.append(aid)
	assert_eq(both.size(), 0,
		"an ability authors both keys — the fallback is now a precedence guess: " + str(both))
	assert_eq(only_modifier.size(), 7,
		"the modifier-only set changed (%d, was 7) — new members were inert until this fix, check them" % only_modifier.size())

func test_the_masterite_roster_is_the_blast_radius() -> void:
	## Records who this repairs, so a future roster change surfaces rather than drifting.
	var ab := _abilities()
	var inert: Dictionary = {}
	for aid in ab:
		var v: Dictionary = ab[aid]
		if v.has("modifier") and not v.has("stat_modifier"):
			inert[aid] = true
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var mons: Dictionary = (parsed as Dictionary).get("monsters", parsed)
	assert_gt(mons.size(), 50, "CONTROL: the roster read non-empty (%d)" % mons.size())
	var owners: Array = []
	for mid in mons:
		for aid in ((mons[mid] as Dictionary).get("abilities", []) as Array):
			if inert.has(str(aid)):
				owners.append(mid)
				break
	assert_gte(owners.size(), 28,
		"fewer monsters carry these than when the fix landed (%d, was 28)" % owners.size())
