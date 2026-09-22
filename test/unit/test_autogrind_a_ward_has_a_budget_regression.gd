extends GutTest

const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## `absorb_amount` is read by live (BattleManager:5860) and by the grind NOWHERE — but unlike every
## other missing-read this lane has closed, THE MECHANISM WAS ALREADY LIVE IN THE GRIND AND UNCAPPED.
##
## The support arm's unmodelled-effect else DID add the status (`add_status("damage_absorb", 2)`),
## and Combatant.take_damage:349 honours it: `int(get_meta("_damage_absorb_budget", -1))`, where a
## MISSING meta means -1 means UNLIMITED. So the grind granted total immunity plus 1:1 self-healing
## for the full duration, on a caster the grind draws every session:
##
##   the_absence — POOLED (abstract_overworld), 8000 max HP, casts fill_the_void (absorb_amount 1000)
##
## Live had exactly this bug and fixed it on 2026-09-10, in the commit whose comment says a cast
## "made it immune AND self-healing against a whole party for two full rounds, which stalls the fight
## rather than complicating it." The grind never received that fix because it never read the key —
## a repair that lands on one engine and not the other is invisible to a key census, which sees the
## grind "handling" the effect.
##
## ⚠️ AND THE UNCAPPED DIRECTION IS THE EXPENSIVE ONE HERE. A grind is unattended: an enemy that
## cannot be damaged for two rounds at a time does not lose the fight, it runs the resolver to
## MAX_ROUNDS and terminates "stalemate", spending real session time and skewing the win rate the
## Dashboard reports.
##
## `guardian_wall` authors absorb_amount 800 with effect "barrier", and LIVE NEVER READS that 800 —
## barrier nullifies one hit outright, then breaks (3 consumer sites). The grind now does the same
## at those three executor sites. The 800 is still decoration on both engines.
##
## 🔑 PLACEMENT still decides parity, and the shared-function repair this note used to recommend
## would have been the wrong one. damage_absorb lives in Combatant.take_damage, so the grind
## inherits it. barrier does not: group attacks call take_damage on both engines and neither
## consults it. A check inside take_damage would make a grind Limit Break bounce off a ward that
## a live Limit Break still lands. The resolver's three sites are the port. The arm at the bottom
## reds if Combatant starts reading barrier anyway.
##
## ⚠️ LATENT, not live: guardian_wall is on Guardian (job type 1, debug-gated) and NO monster
## authors it. But it IS authored in three data/autobattle_rule_templates.json entries and at
## AutobattleSystem.gd:1603, so it goes live the day Guardian unlocks normally.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _authored(ability_id: String) -> Dictionary:
	var js: Node = get_node_or_null("/root/JobSystem")
	if js == null or not js.has_method("get_ability"):
		return {}
	return js.get_ability(ability_id)


func _combatant(name: String, hp: int = 8000) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": hp, "max_mp": 999,
		"attack": 30, "defense": 0, "magic": 30, "speed": 10})
	add_child_autofree(c)
	c.current_mp = c.max_mp
	c.current_hp = hp
	return c


func test_the_ward_carries_the_authored_budget() -> void:
	var ab: Dictionary = _authored("fill_the_void")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var budget: int = int(ab.get("absorb_amount", -1))
	assert_gt(budget, 0, "CONTROL: fill_the_void must still author an absorb_amount")

	var caster := _combatant("The Absence")
	_res._player_party = []
	_res._enemy_party = [caster]
	_res._resolve_ability(caster, "fill_the_void", [caster])
	assert_true(caster.has_status("damage_absorb"), "precondition: the ward is up")
	assert_eq(int(caster.get_meta("_damage_absorb_budget", -1)), budget,
		"the ward must carry the authored budget — absent meta is UNLIMITED and is what the grind had")


func test_damage_past_the_budget_lands_instead_of_being_erased() -> void:
	## The behavioural half. Without the budget the ward eats an arbitrarily large hit and HEALS off
	## it; with it, the overflow lands in the SAME hit. Asserted as an HP DELTA, never a returned
	## figure — take_damage applies its own reduction.
	var ab: Dictionary = _authored("fill_the_void")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var budget: int = int(ab.get("absorb_amount", -1))

	var warded := _combatant("The Absence")
	## Hurt first, so absorbed damage has somewhere to heal INTO — at full HP the heal is invisible
	## and an uncapped ward would look identical to a capped one.
	warded.current_hp = warded.max_hp / 2
	_res._enemy_party = [warded]
	_res._resolve_ability(warded, "fill_the_void", [warded])
	assert_true(warded.has_status("damage_absorb"), "precondition: the ward is up")

	var hp_before: int = warded.current_hp
	var swing: int = budget * 3
	warded.take_damage(swing, true)
	gut.p("    budget=%d swing=%d hp %d -> %d" % [budget, swing, hp_before, warded.current_hp])
	assert_lt(warded.current_hp, hp_before,
		"a swing of %d against a %d budget must LOSE the target HP — uncapped, it healed instead" % [swing, budget])
	assert_false(warded.has_status("damage_absorb"),
		"and the ward breaks once its budget is spent")


func test_an_unbudgeted_ward_is_still_unlimited() -> void:
	## Live keeps the pre-budget rule for any ability authored WITHOUT the key, so this pins the
	## branch rather than the ability — and it is the arm that stops the fix being "always cap".
	var warded := _combatant("Ward")
	warded.current_hp = warded.max_hp / 2
	warded.add_status("damage_absorb", 3)
	assert_false(warded.has_meta("_damage_absorb_budget"), "precondition: no budget parked")
	var hp_before: int = warded.current_hp
	warded.take_damage(500, true)
	assert_gt(warded.current_hp, hp_before, "with no budget the ward absorbs and heals, as live does")


func test_the_pooled_caster_that_makes_this_reachable_is_still_pooled() -> void:
	## Crying-wolf arm. If the_absence leaves every pool, the severity argument in the header weakens
	## and should be re-read rather than assumed; if it stays, this fix keeps earning its place.
	var es: Node = get_node_or_null("/root/EncounterSystem")
	if es == null or es.monster_database.is_empty():
		pass_test("EncounterSystem unavailable")
		return
	var pooled: Array = []
	for pool_id in es.enemy_pools:
		var entry = es.enemy_pools[pool_id]
		var mons = entry.get("monsters", entry) if entry is Dictionary else entry
		if mons is Array:
			for m in mons:
				if (str(m.get("id", m)) if m is Dictionary else str(m)) == "the_absence":
					pooled.append(pool_id)
	gut.p("    the_absence pools: %s" % str(pooled))
	assert_gt(pooled.size(), 0,
		"the_absence is the reachable caster this fix is justified by — if it is pooled nowhere, re-read the header")
	assert_true("fill_the_void" in (es.monster_database["the_absence"] as Dictionary).get("abilities", []),
		"CONTROL: and it must still cast the ability")


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


## ⛔ THIS ARM KEEPS barrier OUT of the shared damage function.
## The resolver now honours it at live's three executor sites. Combatant.take_damage must not
## grow the same check: group attacks call that function on both engines, and live does not ward
## them. A mention of the call in Combatant — comment or code — means the note above is stale.
func test_the_barrier_parity_note_has_not_gone_stale() -> void:
	var shared: String = FileAccess.get_file_as_string("res://src/battle/Combatant.gd")
	assert_ne(shared, "", "CONTROL: could not read Combatant.gd — this arm would pass vacuously")
	assert_true(shared.contains("damage_absorb"),
		"CONTROL: the SHARED function must still handle damage_absorb, the sibling this note contrasts against")
	## ⚠️ KEYED ON THE HANDLING, NOT THE WORD. This was `shared.contains("barrier")` and a const
	## LISTING barrier as dispellable satisfied it — the grind gained nothing, and the arm reported the
	## parity gap closed. The property is that the SHARED damage path READS the status, which is how
	## damage_absorb is handled one line above.
	assert_false(shared.contains("has_status(\"barrier\")"),
		"the SHARED Combatant now READS barrier, so the grind inherits it and this file's header note about the parity gap is CLOSED — update the header and delete this arm rather than leaving a deferral that reads as still-open")


## ⛔ provoke IS IN A SHIPPED AUTOBATTLE TEMPLATE AND HEADLESS HAD NO ARM, so it fell to the generic
## add_status and gave the enemy a status literally named "taunt" — a key live NEVER creates and
## nothing anywhere reads (cowir-battle, 2026-09-18). Live composes `taunted_<caster>` at
## BattleManager:5911 and reads the prefix back in _find_taunter:2983. Same junk-key shape as cleanse.
## The key is what _find_taunter reads. _select_enemy_action locks a taunted enemy onto that caster.
func test_a_taunt_composes_the_key_live_reads() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/autogrind/HeadlessBattleResolver.gd")
	assert_ne(src, "", "CONTROL: could not read the resolver — every assertion below would be vacuous")
	assert_true(src.contains('add_status("taunted_%s" % caster.combatant_name)'),
		"the resolver must compose live's taunted_<caster> key, or a grinding party's provoke writes a status nothing reads")
	assert_false(src.contains('add_status("taunt"'),
		"the resolver creates a bare \"taunt\" status — live never creates that key and _find_taunter cannot read it")
	var live: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_true(live.contains('add_status("taunted_%s" % caster.combatant_name)'),
		"CONTROL: live must still compose this key — if it changed, the parity claim above is about nothing")
	assert_true(live.contains('status.begins_with("taunted_")'),
		"CONTROL: _find_taunter must still read the prefix, else the key is decoration on both engines")
