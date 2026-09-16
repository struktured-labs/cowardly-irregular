extends GutTest

## BattleManager.start_battle:519-534 clears, for EVERY combatant, at the start of every battle:
## active_buffs · active_debuffs · status_effects · status_durations · is_defending · doom_counter.
## Its own comment says why: so edge cases "can't leak into the next encounter."
##
## HeadlessBattleResolver.resolve_battle clears NONE of them. Measured: active_buffs, active_debuffs,
## status_effects and status_durations occur ZERO times in that file (control: add_status occurs 7).
##
## And the grind is exactly the engine where that matters, because AutogrindController holds `_party`
## as Combatant OBJECTS (:34), populated ONCE in start_grind (:101-110) and reused for every battle in
## the session. So state does not merely survive a battle — it accumulates across hundreds of them,
## unattended, with nothing clearing it.
##
##   a buff won in battle 1      makes the party stronger than live for battles 2..N
##   a poison taken in battle 1  keeps ticking into battles the game would have started clean
##   is_defending                carries a damage reduction into the next fight
##   doom_counter                @cowir-battle made doom LETHAL this morning (48a70e4dd). A doom
##                               applied in battle N can kill in battle N+1, where live cleared it.
##
## This is the one gap so far that is not about a single ability: it is the battle BOUNDARY itself.
## Enemies are rebuilt per battle so only the party leaks — which is also why every arm below tests a
## party member rather than a foe.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const GRIND := "res://src/autogrind/HeadlessBattleResolver.gd"

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _hero() -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": "Hero", "max_hp": 99999, "max_mp": 999,
		"attack": 500, "defense": 50, "magic": 500, "speed": 30})
	add_child_autofree(c)
	c.current_mp = c.max_mp
	c.current_hp = c.max_hp
	return c


## 1 HP, no offence — the battle ends in round 1 so the arms measure the BOUNDARY, not attrition.
func _chaff() -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": "Chaff", "max_hp": 1, "max_mp": 0,
		"attack": 1, "defense": 0, "magic": 1, "speed": 1})
	add_child_autofree(c)
	c.current_hp = 1
	return c


func test_a_status_does_not_survive_into_the_next_battle() -> void:
	var hero := _hero()
	hero.add_status("poison", 5)
	assert_true(hero.has_status("poison"), "precondition: the status is on")
	_res.resolve_battle([hero], [_chaff()])
	assert_false(hero.has_status("poison"),
		"live clears status_effects at start_battle; a grind reuses ONE party for the whole session, so this accumulated")


func test_a_buff_does_not_survive_into_the_next_battle() -> void:
	var hero := _hero()
	hero.add_buff("carryover", "attack", 1.5, 5)
	assert_gt(hero.active_buffs.size(), 0, "precondition: the buff is on")
	_res.resolve_battle([hero], [_chaff()])
	assert_eq(hero.active_buffs.size(), 0,
		"a buff won in one grind battle must not make the party stronger than live in the next")


func test_a_debuff_does_not_survive_into_the_next_battle() -> void:
	var hero := _hero()
	hero.add_debuff("carryover", "defense", 0.5, 5)
	assert_gt(hero.active_debuffs.size(), 0, "precondition: the debuff is on")
	_res.resolve_battle([hero], [_chaff()])
	assert_eq(hero.active_debuffs.size(), 0, "and a debuff must not follow the party either — the leak runs both ways")


## ⚠️ THIS ARM ALREADY PASSED BEFORE THE FIX and is kept deliberately, labelled. The resolver clears
## is_defending at :151 inside its own round loop, so the flag never survived. It pins the SCOPE of
## live's block rather than defending the fix — an arm that reds for neither the bug nor the repair
## is worth having only if it says so.
func test_the_defending_flag_does_not_survive() -> void:
	var hero := _hero()
	hero.is_defending = true
	_res.resolve_battle([hero], [_chaff()])
	assert_false(hero.is_defending,
		"is_defending is a per-battle posture; live clears it so a Defer cannot pay out in the NEXT fight")


func test_a_doom_counter_does_not_follow_the_party_into_the_next_battle() -> void:
	## The lethal one. @cowir-battle wired doom to KILL this morning, and live resets the counter to
	## its -1 "not doomed" sentinel at every start_battle. Without that, a doom survived in a grind
	## and killed in a battle the game would have started clean.
	var hero := _hero()
	hero.doom_counter = 2
	_res.resolve_battle([hero], [_chaff()])
	assert_eq(hero.doom_counter, -1,
		"doom must reset to the -1 sentinel, not 0 — 0 is a live counter and Combatant.gd:84 documents -1 as 'not doomed'")


func test_the_clear_does_not_wipe_what_live_keeps() -> void:
	## CONTROL, and the arm that stops this fix becoming "reset the party". Live clears SIX fields at
	## start_battle and nothing else: HP, MP and permanent injuries all survive a battle boundary in
	## both engines, and a grind that healed the party between fights would be a far worse bug than
	## the leak it fixed.
	var hero := _hero()
	hero.current_hp = 500
	hero.current_mp = 7
	var hp_before: int = hero.current_hp
	## Array[DICTIONARY], not Array[String] — I appended a String here first and the control failed
	## while the code was fine. The typed-array trap CLAUDE.md documents, inside the arm written to
	## catch over-clearing.
	hero.permanent_injuries.append({"id": "cracked_rib", "name": "Cracked Rib"})
	_res.resolve_battle([hero], [_chaff()])
	## ⛔ THIS ASSERTED `== 500` AND WAS FLAKY, which is how it shipped green and red the same day.
	## The chaff has attack 1 and sometimes lands a hit before it dies, so the exact figure depended
	## on turn order. CLAUDE.md's coincidental-value trap: the PROPERTY is "the boundary did not
	## restore this combatant", and 500 was merely what that produced on a run where nothing connected.
	## Asserted as a band now — damaged is fine, healed to full is the over-clear this arm exists for.
	assert_lt(hero.current_hp, hero.max_hp,
		"HP must carry across the boundary, not be restored — that is the whole risk model of a grind")
	assert_gt(hero.current_hp, 0, "and the party must not be wiped either")
	assert_lte(hero.current_hp, hp_before, "a battle can only cost HP here; nothing in the clear may add it")
	assert_lt(hero.current_mp, hero.max_mp, "and MP must not be restored by the boundary")
	var kept: bool = false
	for inj in hero.permanent_injuries:
		if str(inj.get("id", "")) == "cracked_rib":
			kept = true
	assert_true(kept, "and permanent injuries are permanent")


func test_the_enemy_side_is_cleared_too_because_live_clears_all_combatants() -> void:
	## Live iterates `all_combatants`, not just the party. Enemies are rebuilt per battle in a grind
	## so this is belt-and-braces — but mirroring the SCOPE keeps the two engines comparable, and a
	## future caller that recycles an enemy gets live's behaviour rather than a surprise.
	var foe := _chaff()
	foe.add_status("poison", 5)
	_res.resolve_battle([_hero()], [foe])
	assert_false(foe.has_status("poison"), "the clear covers both sides, as live's does")


## ── metas, added after live's clear grew ──────────────────────────────────────────────────────────
## ⚠️ I TOLD @cowir-battle THAT META-CLEARING WAS SYMMETRIC AND THAT MY SCOPE WAS THEREFORE RIGHT BY
## PARITY. It was true when I measured it — neither engine cleared a single meta — and their
## ec70e8e43 then extended live's clear from FIELDS to METAS, after _summon_followup kept a lingering
## eidolon hitting in the NEXT encounter. My claim was correct and is now superseded, which is the
## difference between a stale measurement and a wrong one; the licence it issued ("I need not clear
## metas") is what expired. No arm of mine asserted the symmetry, so nothing here had to be undone —
## but nothing here would have NOTICED either, and that is what the last arm below is for.

func test_a_charge_does_not_follow_the_party_into_the_next_battle() -> void:
	## _next_attack_multiplier is the one I raised with them: ungated per-battle state on a persistent
	## object. Gated metas hide behind a status the boundary already clears; this one is read directly.
	var hero := _hero()
	hero.set_meta("_next_attack_multiplier", 1.5)
	_res.resolve_battle([hero], [_chaff()])
	assert_false(hero.has_meta("_next_attack_multiplier"),
		"a charge banked at the end of one grind battle must not pay out in the next")


func test_a_ward_budget_does_not_follow_the_party_into_the_next_battle() -> void:
	## Bounded by a status the boundary clears, so this cannot misfire today — it is here because
	## dropping the status WITHOUT its budget is exactly how the ward went uncapped in the first place.
	var hero := _hero()
	hero.add_status("damage_absorb", 3)
	hero.set_meta("_damage_absorb_budget", 400)
	_res.resolve_battle([hero], [_chaff()])
	assert_false(hero.has_meta("_damage_absorb_budget"),
		"the ward's budget must not outlive the ward — a number nothing owns is how this broke before")


func test_every_meta_this_file_sets_is_cleared_at_the_boundary() -> void:
	## THE INSTRUMENT, not a case. It scans the resolver for set_meta("...") literals and requires
	## each to be listed in PER_BATTLE_METAS. A new meta added without being cleared reds HERE rather
	## than surviving as a leak nobody enumerated — which is precisely how live's own metas escaped
	## its field-clear for months. @cowir-battle's "a new set_meta undeclared" mutation, adopted.
	var code: String = GdSource.code_of(GRIND)
	assert_gt(code.length(), 2000, "CONTROL: the source must actually have loaded")
	## ⛔ THIS READ `_res.PER_BATTLE_METAS` UNTIL 2026-09-16 AND THAT DEFEATED THE WHOLE ARM. Rename or
	## delete the const — the exact drift this guard exists to catch — and the direct reference raises
	## "Invalid access to property or key" at RUNTIME, which ABORTS the function after the two floors
	## above have already passed. GUT then scores it PASSING: it asserted, so it is not Risky; nothing
	## failed, so it is not Failing. Measured: Passing 10 -> 10, Risky 0 -> 0, EC 0 -> 0, and ONLY
	## Asserts moved, 22 -> 17. A guard that reports success when its subject vanishes.
	## Read from SOURCE instead — @cowir-battle's distinction: a source-pin naming a symbol in a string
	## runs against any version of the subject, a direct reference only against one.
	var declared: Array = _declared_metas(code)
	assert_gt(declared.size(), 0,
		"PER_BATTLE_METAS is gone or empty — the boundary clears nothing and the arm below would pass over it")

	var found: Dictionary = {}
	var at: int = code.find("set_meta(\"")
	while at >= 0:
		var start: int = at + 10
		var end: int = code.find("\"", start)
		if end > start:
			found[code.substr(start, end - start)] = true
		at = code.find("set_meta(\"", at + 1)
	gut.p("    set_meta keys in the resolver: %s" % str(found.keys()))
	assert_gt(found.size(), 0, "CONTROL: the scan must find the set_meta calls, or it proves nothing")

	## ⚠️ COMPOSITION IS TESTED FIRST, AND "LITERAL" MEANS THE WHOLE ARGUMENT IS ONE QUOTED STRING.
	## My first version compared call counts, and a composed key that STARTS with a quote —
	## set_meta("_bark_" + face) — was filed as the literal "_bark_". It reddened only by luck,
	## through the unlisted check below, and a composed key whose prefix WAS listed would have passed
	## both. That is @cowir-cutscenes' exact miss from this morning, reproduced inside the instrument
	## I wrote to catch it. Measured, not assumed: every set_meta here is a whole-string literal today.
	assert_eq(_composed_meta_sites(code), [],
		"a set_meta key in the resolver is COMPOSED, not a literal: %s — the scan below cannot see it, so extend both it and PER_BATTLE_METAS" % str(_composed_meta_sites(code)))
	var total_sets: int = code.count("set_meta(")
	assert_eq(total_sets, found.size() + _duplicate_literal_sets(code),
		"a set_meta call does not begin with a quoted key at all — same consequence, different shape")

	var unlisted: Array = []
	for k in found:
		if not declared.has(k):
			unlisted.append(k)
	assert_eq(unlisted, [],
		"these metas are set by the grind and NOT cleared at the battle boundary: %s — add them to PER_BATTLE_METAS or say why they outlive a battle" % str(unlisted))


## set_meta("_next_attack_multiplier", ...) appears twice (set and reset), so the literal COUNT
## exceeds the distinct-key count. This returns that surplus so the composed-key check above
## compares like with like instead of reding on an honest duplicate.
func _duplicate_literal_sets(code: String) -> int:
	var literal_calls: int = code.count("set_meta(\"")
	var distinct: Dictionary = {}
	var at: int = code.find("set_meta(\"")
	while at >= 0:
		var start: int = at + 10
		var end: int = code.find("\"", start)
		if end > start:
			distinct[code.substr(start, end - start)] = true
		at = code.find("set_meta(\"", at + 1)
	return literal_calls - distinct.size()


## A set_meta whose key is built rather than written. "Literal" = the closing quote is followed by a
## comma; anything else (notably `+`) is composition wearing a literal's opening quote.
##
## ⚠️ THIS ASSERTS ABOUT A CHARACTER, NOT ABOUT THE PROPERTY — @cowir-cutscenes' name-vs-property
## smell, and their own instance was the same shape (`begins_with('"')` standing in for "is a
## literal"). Knowing that, the failure DIRECTION is what makes it safe to keep, and it was measured
## rather than hoped for: every way I can defeat this errs toward CRYING WOLF, never toward silence.
##   set_meta("_k" , v)        space before the comma  -> flagged, wrongly. Loud, harmless.
##   set_meta("_k".repeat(2))  a method on the literal -> flagged. Correct, by luck of the same rule.
##   set_meta(("_k" + b), v)   parenthesised           -> this scan never sees it, and the
##                             total-vs-literal count check above catches it instead.
## A real answer needs a parser. Until one is cheap, this is a syntax heuristic that fails loud, and
## saying so is the point — an instrument that cannot state its own blind spot has two.
func _composed_meta_sites(code: String) -> Array:
	var out: Array = []
	var at: int = code.find("set_meta(\"")
	while at >= 0:
		var start: int = at + 10
		var end: int = code.find("\"", start)
		if end > start:
			var after: String = code.substr(end + 1, 1)
			if after != ",":
				out.append(code.substr(start, end - start))
		at = code.find("set_meta(\"", at + 1)
	return out


## The boundary's declared key list, parsed out of the source so a missing const REDS here instead of
## aborting this arm into a silent pass. Returns [] when the declaration is absent, which the caller
## treats as the failure it is.
func _declared_metas(code: String) -> Array:
	var at: int = code.find("const PER_BATTLE_METAS")
	if at < 0:
		return []
	## AFTER the `=`, not after the const name: the type annotation `Array[String]` carries its own
	## brackets, and finding those parsed the list as ["String"]. The clean run redded on it, which is
	## the arm's floor doing its job on the arm's own parser.
	var eq: int = code.find("=", at)
	if eq < 0:
		return []
	var open_b: int = code.find("[", eq)
	var close_b: int = code.find("]", open_b)
	if open_b < 0 or close_b < open_b:
		return []
	var out: Array = []
	for part in code.substr(open_b + 1, close_b - open_b - 1).split(","):
		var t: String = part.strip_edges().replace("\"", "")
		if t != "":
			out.append(t)
	return out


## FLOOR FOR THE WHOLE FILE, added 2026-09-16. Every arm here reaches members of the resolver,
## and a member that is RENAMED does not fail — it aborts the arm at runtime, which GUT scores
## PASSING when the abort lands after the last assert. Measured on my own meta guard that day:
## Passing 10 -> 10, Failing 0, Risky 0, EC 0, and only Asserts moved (22 -> 17).
## @cowir-sfx's form, and it needs no judgement about WHY a member is reached: the silent-abort
## failure does not care, so a vehicle is as worth pinning as a subject. `get()` returns null for
## an absent property rather than raising; `assert_ne(x, null)` is NOT usable — it deep-compares.
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
const _PINNED_MEMBERS := ["resolve_battle"]

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
	## "gd" — the same false positive fixed in the generator and reintroduced here.
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
	if not _res.has_method("resolve_battle"): missing.append("resolve_battle()")
	assert_eq(missing, [],
		"the resolver no longer has these, so the arms above would ABORT into a silent pass: %s" % str(missing))
