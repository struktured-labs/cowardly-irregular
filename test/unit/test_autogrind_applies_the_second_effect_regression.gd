extends GutTest

## 9 abilities author `secondary_effect` — a follow-up status or stat change on top of their primary —
## and the grind honoured none of them. The live engine's own comment records that these were all
## dropped once before (BattleManager tick 433): "enrage was a free 2.0x attack buff with no defense
## penalty, web_shot only slowed without the stun, howl never frightened any enemies". That fix landed
## in the live engine and never reached the resolver.
##
## SIX OF THE CASTERS ARE POOLED MONSTERS a grind draws every session, and they are ordinary W1
## enemies: spider (web_shot -> stun) · wolf (howl -> fear) · ogre and cave_troll (enrage ->
## defense_down) · barbarian and blood_wolf_alpha (frenzy) · conveyor_gremlin (sabotage) ·
## optimization_itself (streamline). So the grind read easier than live on routine encounters, and any
## autobattle rule conditioned on a status the party SHOULD be suffering never fired — which is the
## half that matters for a mode whose whole point is testing rules.
##
## Support secondaries were the original gap. `toxic_embrace` is physical, and both engines now apply
## its speed_down from the physical arm. `subset_drain` stays magic, so its magic_down stays dropped
## on both sides — a design hold, and applying it only here would make the grind harsher than live.
##
## Fifth instance of this resolver's documented class: heal_amount, mp_amount, hits, drain_percentage.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const SRC := "res://src/autogrind/HeadlessBattleResolver.gd"

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _authored(ability_id: String) -> Dictionary:
	var js: Node = get_node_or_null("/root/JobSystem")
	if js == null or not js.has_method("get_ability"):
		return {}
	return js.get_ability(ability_id)


## HP/MP set AFTER add_child — entering the tree restores full HP, so a pre-add assignment is
## silently discarded (cost me two cycles on the drain fix).
func _combatant(name: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 500, "max_mp": 999,
		"attack": 30, "defense": 10, "magic": 30, "speed": 10})
	add_child_autofree(c)
	c.current_mp = c.max_mp
	return c


func _sides(players: Array, enemies: Array) -> void:
	_res._player_party = players
	_res._enemy_party = enemies


func test_a_secondary_stat_change_is_applied_beside_the_primary() -> void:
	var ab: Dictionary = _authored("enrage")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	assert_eq(str(ab.get("secondary_effect", "")), "defense_down",
		"CONTROL: enrage must still author the defense penalty that pays for its attack buff")
	var ogre := _combatant("Ogre")
	_sides([], [ogre])
	var def_before: float = ogre.get_buffed_stat("defense", ogre.defense)
	var atk_before: float = ogre.get_buffed_stat("attack", ogre.attack)
	_res._resolve_ability(ogre, "enrage", [ogre])
	var atk_after: float = ogre.get_buffed_stat("attack", ogre.attack)
	var def_after: float = ogre.get_buffed_stat("defense", ogre.defense)
	gut.p("    enrage: atk %.1f -> %.1f   def %.1f -> %.1f" % [atk_before, atk_after, def_before, def_after])
	assert_gt(atk_after, atk_before, "CONTROL: the PRIMARY attack buff must still land")
	assert_lt(def_after, def_before,
		"enrage's defense penalty never applied — it was a free attack buff, which is the tradeoff removed")


func test_a_monster_secondary_aimed_at_all_enemies_hits_the_PARTY() -> void:
	## The side logic, and the one thing in this fix that can be wrong in a way nothing else catches:
	## `all_enemies` is relative to the CASTER. A wolf's howl must frighten the party, never its pack.
	var ab: Dictionary = _authored("howl")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	assert_eq(str(ab.get("secondary_target", "")), "all_enemies", "CONTROL: howl must still target all enemies")
	var sec: String = str(ab.get("secondary_effect", ""))
	var hero := _combatant("Hero")
	var wolf := _combatant("Wolf")
	var packmate := _combatant("Packmate")
	_sides([hero], [wolf, packmate])
	seed(0x5EED)
	## Chance is 0.3, so cast until it lands rather than asserting one roll — bounded, and the
	## precondition below fails loudly if it never does.
	var landed := false
	for _i in 200:
		_res._resolve_ability(wolf, "howl", [wolf])
		if hero.has_status(sec):
			landed = true
			break
	assert_true(landed, "CONTROL: howl's %s must land on the party within 200 casts at its authored chance" % sec)
	assert_false(packmate.has_status(sec),
		"the wolf frightened its own packmate — `all_enemies` was read from a fixed party instead of relative to the caster")
	assert_false(wolf.has_status(sec), "and it frightened itself")


func test_an_ability_with_no_secondary_applies_nothing_extra() -> void:
	## A dispatcher that fired unconditionally would add a junk status to every support cast.
	var ab: Dictionary = _authored("protect")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	assert_false(ab.has("secondary_effect"), "CONTROL: protect must author no secondary, or it cannot police the default")
	var hero := _combatant("Hero")
	_sides([hero], [])
	_res._resolve_ability(hero, "protect", [hero])
	assert_eq(hero.status_effects.size(), 0,
		"a support ability authoring no secondary gained %s — the dispatcher fired on nothing" % str(hero.status_effects))


func test_subset_drain_stays_magic_and_toxic_embrace_stays_physical() -> void:
	## subset_drain's magic_down is a design hold: the magic arm must not grow a secondary call just
	## because the ability changed type. toxic_embrace stays physical, and the physical arm applies it.
	for pair in [["subset_drain", "magic"], ["toxic_embrace", "physical"]]:
		var ab: Dictionary = _authored(pair[0])
		if ab.is_empty():
			pass_test("JobSystem autoload unavailable")
			return
		assert_true(ab.has("secondary_effect"), "CONTROL: %s must still author a secondary" % pair[0])
		assert_eq(str(ab.get("type", "")), pair[1],
			"%s changed type — the secondary dispatch has to be revisited with it" % pair[0])
	## ⚠️ BOUNDED TO THE ARM, not a fixed window. A 4000-char slice from the arm's start ran PAST it
	## and matched the helper's own `func _apply_secondary_effect(` declaration, so deleting the CALL
	## left this green — mention read as invocation, in the arm meant to pin the invocation.
	var code: String = GdSource.code_of(SRC)
	var arm_start: int = code.find('"support", "song", "status":')
	assert_gt(arm_start, 0, "CONTROL: the support arm must be locatable")
	var arm_end: int = code.find("\n\t\t_:", arm_start)
	assert_gt(arm_end, arm_start, "CONTROL: the arm must be bounded by the default arm that follows it")
	var support_arm: String = code.substr(arm_start, arm_end - arm_start)
	assert_false(support_arm.contains("func _apply_secondary_effect"),
		"CONTROL: the slice must stop before the helper's declaration, or a call is indistinguishable from it")
	assert_true(support_arm.contains("_apply_secondary_effect("),
		"the dispatcher must be CALLED from the SUPPORT arm, which is where live calls it")


func test_every_authored_secondary_is_reachable_in_a_grind() -> void:
	var es: Node = get_node_or_null("/root/EncounterSystem")
	if es == null or not ("enemy_pools" in es):
		pass_test("EncounterSystem unavailable")
		return
	var abilities: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var monsters: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var support_secondaries: Array = []
	for aid in abilities.keys():
		var a: Dictionary = abilities[aid]
		if str(a.get("secondary_effect", "")) != "" and str(a.get("type", "")) == "support":
			support_secondaries.append(aid)
	assert_gt(support_secondaries.size(), 0, "CONTROL: abilities.json must still author a support-typed secondary")
	var pooled: Dictionary = {}
	for region in es.enemy_pools.keys():
		for entry in es.enemy_pools[region]:
			pooled[str(entry.get("id", entry) if entry is Dictionary else entry)] = true
	var casters: Array = []
	for mid in monsters.keys():
		if not pooled.has(mid):
			continue
		for aid in (monsters[mid] as Dictionary).get("abilities", []):
			if support_secondaries.has(aid):
				casters.append("%s/%s" % [mid, aid])
	gut.p("    pooled casters: %s" % str(casters))
	assert_gt(casters.size(), 0,
		"no pooled monster casts a support secondary any more — re-justify this dispatcher rather than keeping it on faith")


func test_the_dispatcher_mirrors_the_live_defaults() -> void:
	## Structural. The behavioural arms above pass on a dispatcher that hardcodes enrage's numbers;
	## these are the defaults live uses, and getting one wrong is silent in every arm above.
	var code: String = GdSource.code_of(SRC)
	assert_gt(code.length(), 5000, "CONTROL: the resolver was actually read")
	assert_true(code.contains('ability.get("secondary_chance", 1.0)'), "secondary_chance defaults to 1.0 in live")
	assert_true(code.contains('ability.get("secondary_modifier", 0.7)'), "secondary_modifier defaults to 0.7 in live")
	assert_true(code.contains("_SECONDARY_STAT_DEBUFF_MAP"), "the debuff map must exist, or defense_down falls through to add_status")


## ⛔ THE INTERACTION @cowir-main ASKED ABOUT, ANSWERED RATHER THAN ASSUMED. This branch now sits on
## top of the drain and scales_with fixes, and all four mechanisms edit `_resolve_ability`. The
## question was whether a secondary fires on a drained or stat-scaled hit.
##
## The physical arm now calls the dispatcher too, because toxic_embrace is a strike with a secondary.
## `hits`, `drain_percentage` and `scales_with` still belong to the damage step. No ability that
## reaches the dispatcher authors one of those beside a secondary. subset_drain is magic, so it does
## not reach the dispatcher — magic_down stays a hold — and is excluded from that pairing check.
func test_no_ability_exercises_both_the_support_and_the_damage_mechanisms() -> void:
	var abilities: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var damage_keys: Array = ["hits", "drain_percentage", "scales_with"]
	var checked := 0
	var both: Array = []
	for aid in abilities.keys():
		var a: Dictionary = abilities[aid]
		if str(a.get("secondary_effect", "")) == "":
			continue
		checked += 1
		var typ := str(a.get("type", ""))
		if typ != "support" and typ != "physical":
			continue  # magic (subset_drain) still does not reach the dispatcher
		for k in damage_keys:
			if a.has(k):
				both.append("%s (%s)" % [aid, k])
	assert_gt(checked, 5, "CONTROL: the corpus must still hold abilities authoring a secondary")
	assert_eq(both, [],
		"%s authors a secondary AND a damage-arm key — the first ability to exercise an interaction nobody designed. Decide the order deliberately rather than letting the next merge pick it" % str(both))
	## Physical applies secondaries (toxic_embrace). Magic does not (subset_drain / magic_down).
	var code: String = GdSource.code_of(SRC)
	var phys: int = code.find('"physical":')
	var magic: int = code.find('"magic":')
	assert_gt(phys, 0, "CONTROL: the physical arm must be locatable")
	assert_gt(magic, 0, "CONTROL: the magic arm must be locatable")
	var phys_arm: String = code.substr(phys, code.find("\n\t\t\"", phys + 12) - phys)
	var magic_arm: String = code.substr(magic, code.find("\n\t\t\"", magic + 12) - magic)
	assert_true(phys_arm.contains("_apply_secondary_effect("),
		"the physical arm must call the secondary dispatcher — toxic_embrace's slow is a physical strike")
	assert_false(magic_arm.contains("_apply_secondary_effect("),
		"the magic arm must not call it — subset_drain's magic_down is a design hold")


## ⛔ `seed()` SETS THE PROCESS-WIDE RNG AND GUT RUNS EVERY FILE IN ONE PROCESS, so a file that
## seeds and does not restore makes every LATER file deterministic — @cowir-battle measured a probe
## drawing one identical value three times after a seeded file, and three different ones after the
## restore. The hazard is ORDER-DEPENDENCE: a later probabilistic arm's result then depends on which
## files preceded it, so a flake reads as a real failure and a probabilistic bug reads as absent.
## Same class as the Input-singleton leak CLAUDE.md documents for physics tests, and not in that list.
## after_all, not after_each: determinism WITHIN this file is deliberate and untouched — only the
## exit is cleaned up.
func after_all() -> void:
	randomize()


## FLOOR. Measured 2026-09-16: renaming a member this file reaches leaves it SILENT —
## e.g. pierces_what_it_pierces went Asserts 17 -> 15 at EC=0, Passing unchanged, no Risky.
## That is rung 3, which `.366`'s exit 4 cannot reach: the arms assert and THEN abort, so GUT
## scores them Passing. `get()` and `has_method()` ANSWER rather than raise — an existence arm
## written with a direct read aborts alongside the arms it exists to catch.
## ⚠️ THIS LIST IS A SNAPSHOT, NOT A DERIVATION, and that is the live limit. It was derived once by
## a script from this file's own `_res.` / AutogrindSystem reaches and then written as literals — so
## a member reached by a NEW arm added later is not covered, and the list goes quietly incomplete
## rather than loudly wrong. @cowir-cutscenes' rule puts it on the wrong side of the line: a figure
## the guard's claim DEPENDS on should be derived, and this is one.
## Deliberately not converted to a runtime derivation, per @cowir-sfx's reasoning: doing that needs
## @cowir-ai's bare-Object exclusion, because a runtime scan of this file would collect the `get` and
## `has_method` calls THIS ARM ITSELF makes and pin the mechanism it is written in. That is a real
## defence against a real hazard, and writing it tonight would be shipping it untested. Correct as of
## 2026-09-16; if you add an arm that reaches a new member, add it here or derive the set properly.
const _FLOOR_ARM_NAME := "test_every_resolver_member_this_file_reaches_still_exists"
const _PINNED_MEMBERS := ["_enemy_party", "_player_party", "_resolve_ability"]

func test_every_resolver_member_this_file_reaches_still_exists() -> void:
	## @cowir-ai's counter to the snapshot limit above, and it converts the failure mode rather than
	## documenting it: a static list fails toward INCOMPLETENESS — add a reach tomorrow and the floor
	## silently covers all-but-one. This counts the distinct members reached in the text BEFORE this
	## function, so the arm cannot count its own `get`/`has_method` calls — @cowir-ai's bare-Object
	## exclusion replaced by SCOPING, which they named as the alternative. A new reach reds here.
	## ⛔ THE SHARED STRIPPER, not a tenth private one. My first version split each line on "#" —
	## adding another inline comment-strip on the day this fleet counted EIGHTEEN redundant
	## private ones (@cowir-music, who used gd_source rather than writing a sixth). It is
	## quote-aware and escape-aware, which a split on "#" is not: a `#` inside a string
	## literal truncates the line and can hide a real reach.
	var own_src: String = GdSource.code_of(get_script().resource_path)
	var cut: int = own_src.find("func %s(" % _FLOOR_ARM_NAME)
	assert_gt(cut, 0, "CONTROL: located this arm, so the scoped slice is real")
	var before: String = own_src.substr(0, cut)
	var reached: Dictionary = {}
	## ⛔ SKIP PATH LITERALS. `AutogrindSystem.gd` inside a res:// string matched as a member named
	## "gd" — the same false positive I fixed in the generator two hours earlier and reintroduced
	## here. A regex reading source cannot tell a member reach from a filename by shape.
	for raw_line in before.split("\n"):
		if raw_line.contains("res://"):
			continue
		## ⛔ TRAILING COMMENTS TOO, per @cowir-sprites: a floor exists to catch a RENAME, and the commit
		## that renames a member is the one whose prose explains the rename BY NAME. `_res.foo()  #
		## renamed from _res.bar` would inflate this count and red a CORRECT file. Leading-## lines were
		## already skipped; this drops the trailing half. Measured 2026-09-16: strict and lenient
		## extraction agree on all ten floored files, so this is latent rather than a live repair.
		## NOT stripped: a member named inside a triple-quoted block. Measured absent in these files,
		## and recorded rather than handled — a quote-aware stripper here would be its own hazard.
		for m in RegEx.create_from_string("(?:_res|AutogrindSystem)\\.([A-Za-z_][A-Za-z_0-9]*)").search_all(raw_line):
			reached[m.get_string(1)] = true
	reached.erase("_test_disable_persistence")
	reached.erase("PER_BATTLE_METAS")   ## read from SOURCE on purpose — see the arm above
	## ⛔ SETS, NOT SIZES. This compared COUNTS until 2026-09-16, and @cowir-cutscenes' completeness
	## finding is why that is not enough: pin {A,B,X} where X exists but is never reached, while the
	## file reaches {A,B,C}, and the existence arm passes (all three exist) AND the count passes
	## (3 == 3) — with C unpinned and X spurious. Equal cardinality is not equal membership, and an
	## over-count is the same defect as an under-count in a louder coat.
	var pinned: Dictionary = {}
	for x in _PINNED_MEMBERS:
		pinned[x] = true
	assert_gt(reached.size(), 0, "CONTROL: the scan found reaches, or this comparison proves nothing")
	var unpinned: Array = []
	for k in reached:
		if not pinned.has(k):
			unpinned.append(k)
	var spurious: Array = []
	for k in pinned:
		if not reached.has(k):
			spurious.append(k)
	gut.p("    reaches: %d | pinned: %d | unpinned: %s | spurious: %s" % [reached.size(), pinned.size(), str(unpinned), str(spurious)])
	assert_eq(unpinned, [], "this file reaches members the floor does not pin — the list is a snapshot: %s" % str(unpinned))
	assert_eq(spurious, [], "the floor pins members this file no longer reaches — stale entries: %s" % str(spurious))

	var missing: Array = []
	if _res.get("_enemy_party") == null: missing.append("_enemy_party")
	if _res.get("_player_party") == null: missing.append("_player_party")
	if not _res.has_method("_resolve_ability"): missing.append("_resolve_ability()")
	assert_eq(missing, [],
		"the resolver no longer has these, so the arms above would ABORT into a silent pass: %s" % str(missing))
