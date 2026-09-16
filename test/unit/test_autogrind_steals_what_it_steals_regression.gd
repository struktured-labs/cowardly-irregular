extends GutTest

## `success_rate` + `steals` are authored by 3 abilities and read by the live engine in two places —
## BattleManager:6147 (the support `steal` effect) and :4655 (mug's steal half). HeadlessBattleResolver
## read NEITHER, and had zero mentions of steal at all. So in the grind:
##
##   PLAYER SIDE   `steal` and `mug` are BOTH in the Rogue's base kit — not level-gated, not
##                 purchased. A Rogue in a grinding party earned zero steal-gold where live pays
##                 5-50 per landed steal, scaled by the victim's max HP. The grind UNDERSTATED a
##                 gold build, which is the same full-parity break as the reward_multiplier one
##                 this file already records ("ludicrous/headless MUST receive the same yields").
##   THE VICTIM    `steal` authors `effect: "steal"` with no `stat`, so it fell to the support arm's
##                 unmodelled-effect else and gave the target a junk STATUS called "steal". Exactly
##                 the cleanse bug documented one branch up, and the reason that else exists.
##
## Axis 2 checked BEFORE building: live reads success_rate for `steal` inside _execute_support_ability
## (one of the four executors) and for `mug` inline in _execute_ability's "physical" arm, so the two
## reads land on the two arms wired here — not on one shared path.
##
## ⚠️ WHAT WAS DELIBERATELY *NOT* MIRRORED (and is now agreed on both sides): live's two add_gold
## calls had NO caster-side check, so an ENEMY's steal paid the party it just robbed. That is reachable — goblin, spiteful_crow and conveyor_gremlin author `steal` across 7
## pools, and "support" is in UTILITY_ABILITY_TYPES, which _ai_brute and _ai_assassin both draw from
## at 0.2/0.25. Copying it into an engine that runs hundreds of unattended battles turns a per-fight
## bug into a gold fountain. Reported to @cowir-battle, who owns BattleManager, and CONFIRMED by them
## behaviourally before the fix — so this file found a live defect by declining to mirror it.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _authored(ability_id: String) -> Dictionary:
	var js: Node = get_node_or_null("/root/JobSystem")
	if js == null or not js.has_method("get_ability"):
		return {}
	return js.get_ability(ability_id)


## max_mp matters — _resolve_ability RETURNS if the caster cannot pay mp_cost, and a no-op cast
## measures 0 gold against a working fix.
func _combatant(name: String, hp: int = 500) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": hp, "max_mp": 999,
		"attack": 30, "defense": 10, "magic": 30, "speed": 10})
	add_child_autofree(c)
	c.current_mp = c.max_mp
	c.current_hp = hp
	return c


## `steal` authors 0.5, so ONE cast proves nothing either way. 30 casts make a false red 0.5^30.
const _CASTS := 30


func test_a_party_steal_actually_moves_gold() -> void:
	var ab: Dictionary = _authored("steal")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	assert_gt(float(ab.get("success_rate", 0.0)), 0.0, "CONTROL: steal must still author a success_rate")
	var rogue := _combatant("Rogue")
	_res._player_party = [rogue]
	var victim := _combatant("Goblin", 500)
	for _i in _CASTS:
		rogue.current_mp = rogue.max_mp
		_res._resolve_ability(rogue, "steal", [victim])
	gut.p("    steal x%d -> %d gold" % [_CASTS, _res._stolen_gold])
	assert_gt(_res._stolen_gold, 0,
		"a Rogue's steal must take gold in the grind as it does in live — %d casts took %d" % [_CASTS, _res._stolen_gold])


func test_the_victim_no_longer_gets_a_junk_status_called_steal() -> void:
	## Deterministic whichever way the rate rolls: the old arm added the status on EVERY cast.
	if _authored("steal").is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var rogue := _combatant("Rogue")
	_res._player_party = [rogue]
	var victim := _combatant("Goblin", 500)
	for _i in _CASTS:
		rogue.current_mp = rogue.max_mp
		_res._resolve_ability(rogue, "steal", [victim])
	## FLOOR, and this arm had none until 2026-09-16: an absence assertion passes just as happily when
	## the cast never happened. _resolve_ability RETURNS silently on unpayable MP or an unknown id, so
	## a no-op run would have "proved" the junk status was gone. Require the steal to have RESOLVED.
	assert_gt(_res._battle_log.size(), 0, "FLOOR: the casts must have produced log lines at all")
	assert_true("\n".join(_res._battle_log).contains("steal"),
		"FLOOR: the steal branch must have been reached — otherwise this arm is green over a no-op")
	assert_false(victim.has_status("steal"),
		"steal is a gold transfer, not a status — the unmodelled-effect else used to brand the victim with it")


func test_mug_still_hits_AND_steals() -> void:
	## mug is "attack and steal in one action". The grind's physical arm read neither half of the
	## steal, so it was a plain hit — and an arm that only checked the gold could pass on a mug that
	## stopped dealing damage.
	var ab: Dictionary = _authored("mug")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	assert_true(bool(ab.get("steals", false)), "CONTROL: mug must still author the steals flag")
	var rogue := _combatant("Rogue")
	_res._player_party = [rogue]
	var victim := _combatant("Sandbag", 999999)
	var hp0: int = victim.current_hp
	for _i in _CASTS:
		rogue.current_mp = rogue.max_mp
		_res._resolve_ability(rogue, "mug", [victim])
	gut.p("    mug x%d -> %d gold, %d damage" % [_CASTS, _res._stolen_gold, hp0 - victim.current_hp])
	assert_gt(hp0 - victim.current_hp, 0, "mug must still deal its damage")
	assert_gt(_res._stolen_gold, 0, "and mug's steal half must pay out")


func test_an_enemys_steal_does_not_pay_the_party_it_robbed() -> void:
	## Written as a DELIBERATE DIVERGENCE — live had no caster-side check and this asserted the grind
	## did. @cowir-battle then reproduced it behaviourally (party_gold 1000 -> 1014 off a goblin's
	## steal) and fixed live in `_award_stolen_gold`, so once that folds the two engines AGREE and
	## this arm pins parity instead. The assertion is identical either way, which is the only reason
	## it was safe to write before the ruling existed.
	## ⚠️ Still OPEN and explicitly struktured's: whether an enemy's steal should COST the party gold.
	## The amount scales with the VICTIM's max HP, so against a party member it is far larger than the
	## same ability yields against a goblin — an unsized drain on monsters a level-3 party meets. The
	## grind takes no position on that; it only refuses to PAY the victim.
	if _authored("steal").is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var hero := _combatant("Hero")
	var goblin := _combatant("Goblin")
	_res._player_party = [hero]
	_res._enemy_party = [goblin]
	for _i in _CASTS:
		goblin.current_mp = goblin.max_mp
		_res._resolve_ability(goblin, "steal", [hero])
	assert_eq(_res._stolen_gold, 0,
		"a monster stealing from the party must not CREDIT the party — live does, and a grind runs it hundreds of times")
	## and it is not a silent no-op: the attempt is still logged, so the divergence is visible.
	var joined := "\n".join(_res._battle_log)
	assert_true(joined.contains("steal"),
		"the enemy's steal must still resolve and log — a silent skip would hide the divergence: %s" % joined.substr(0, 300))


func test_the_amount_matches_lives_formula_and_a_missed_roll_takes_nothing() -> void:
	## Direct on the helper so the RATE is not in play: live's amount is
	## randi_range(5, 50) * (1 + int(max_hp / 500.0)), so a 500-HP victim yields 10..100.
	var rogue := _combatant("Rogue")
	_res._player_party = [rogue]
	var victim := _combatant("Goblin", 500)
	_res._roll_steal(rogue, {}, [victim], 1.0)
	gut.p("    guaranteed steal off a 500 HP victim -> %d" % _res._stolen_gold)
	assert_between(_res._stolen_gold, 10, 100,
		"a 500 HP victim yields randi_range(5,50) x 2 = 10..100, and the grind took %d" % _res._stolen_gold)

	_res._stolen_gold = 0
	_res._roll_steal(rogue, {}, [victim], 0.0)
	assert_eq(_res._stolen_gold, 0, "a rate of 0 must never pay out — otherwise the roll is decoration")


func test_a_dead_victim_cannot_be_robbed() -> void:
	## Mirrors live's `_st.is_alive` guard, which is also why mug rolls AFTER its damage.
	var rogue := _combatant("Rogue")
	_res._player_party = [rogue]
	var victim := _combatant("Goblin", 500)
	victim.take_damage(999999, true)
	assert_false(victim.is_alive, "CONTROL: the victim must actually be dead")
	_res._roll_steal(rogue, {}, [victim], 1.0)
	assert_eq(_res._stolen_gold, 0, "a corpse carries no purse — live skips dead targets on both steal paths")


func test_stolen_gold_survives_a_defeat() -> void:
	## Every other reward in _build_results is victory-only. Live calls add_gold the MOMENT the steal
	## lands, so gold taken off a monster is kept even if the party then wipes. Written as an arm
	## because the obvious implementation — adding it inside `if victory:` — passes every arm above.
	var rogue := _combatant("Rogue")
	_res._player_party = [rogue]
	_res._enemy_party = []
	var victim := _combatant("Goblin", 500)
	_res._roll_steal(rogue, {}, [victim], 1.0)
	var taken: int = _res._stolen_gold
	assert_gt(taken, 0, "CONTROL: the steal must have landed or this arm proves nothing")
	var lost: Dictionary = _res._build_results(false)
	gut.p("    stole %d, defeat paid %d" % [taken, int(lost["gold_gained"])])
	assert_gt(int(lost["gold_gained"]), 0,
		"gold already stolen must survive a wipe — live credited it mid-battle, %d was taken and the loss paid %d" % [taken, int(lost["gold_gained"])])


func test_a_support_ability_that_is_not_steal_pays_nothing() -> void:
	## CONTROL. Without it, an arm that credited gold on every support cast would pass everything above.
	if _authored("protect").is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var cleric := _combatant("Cleric")
	_res._player_party = [cleric]
	var ally := _combatant("Ally")
	for _i in _CASTS:
		cleric.current_mp = cleric.max_mp
		_res._resolve_ability(cleric, "protect", [ally])
	## FLOOR, same reason: a protect that never resolved also takes no gold. Require the buff to exist.
	assert_gt(ally.active_buffs.size(), 0,
		"FLOOR: protect must actually have applied — a no-op cast would pass the assertion below for free")
	assert_eq(_res._stolen_gold, 0, "only a steal takes gold — a buff must not")


## ── the reachability claims this fix rests on ────────────────────────────────────────────────────
## Both arms below exist so a DATA change reds the claim rather than silently voiding it. A licence
## that outlives its premise is the failure mode the fleet hit three times today.

func test_steal_is_still_reachable_by_the_forms_that_made_it_worth_fixing() -> void:
	var js: Node = get_node_or_null("/root/JobSystem")
	var es: Node = get_node_or_null("/root/EncounterSystem")
	if js == null or es == null or es.monster_database.is_empty():
		pass_test("autoloads unavailable")
		return
	## FORM 2 — the Rogue's base kit. If steal/mug ever become level-gated or purchased, the
	## player-side justification in the header weakens and this should be revisited, not assumed.
	var rogue_kit: Array = []
	if js.has_method("get_job"):
		rogue_kit = (js.get_job("rogue") as Dictionary).get("abilities", [])
	assert_true(rogue_kit.has("steal") and rogue_kit.has("mug"),
		"the Rogue's base kit is form 2 for both abilities — got %s" % str(rogue_kit))
	## FORM 1 — pooled casters. The monster side of the divergence declaration depends on this.
	var casters: Array = []
	for mid in es.monster_database:
		var abl: Array = (es.monster_database[mid] as Dictionary).get("abilities", [])
		if abl.has("steal") or abl.has("mug"):
			casters.append(mid)
	gut.p("    monsters authoring steal/mug: %s" % str(casters))
	assert_gt(casters.size(), 0,
		"if no monster casts steal, the enemy-side divergence this file declares stops existing and the declaration should go")


func test_the_unported_boss_half_is_still_unreachable_in_a_grind() -> void:
	## first_steal_guaranteed and steal_response are NOT ported, on the measured ground that
	## rogue_lockward is their only author and no grind can field it. This arm CRIES WOLF: it reds
	## the moment any author of either flag becomes pooled or autogrind_spawned, because at that
	## point the omission is a real gap rather than a scoped-out one. An oracle that wrongly says
	## UNREACHABLE passes an offender, so its errors must fall this way.
	var es: Node = get_node_or_null("/root/EncounterSystem")
	if es == null or es.monster_database.is_empty():
		pass_test("EncounterSystem unavailable")
		return
	var pooled: Dictionary = {}
	for pool_id in es.enemy_pools:
		var entry = es.enemy_pools[pool_id]
		var mons = entry.get("monsters", entry) if entry is Dictionary else entry
		if mons is Array:
			for m in mons:
				pooled[str(m.get("id", m)) if m is Dictionary else str(m)] = true
	var authors: Array = []
	var reachable: Array = []
	for mid in es.monster_database:
		var m: Dictionary = es.monster_database[mid]
		if not (m.get("first_steal_guaranteed", false) or m.has("steal_response")):
			continue
		authors.append(mid)
		if pooled.has(mid) or m.get("autogrind_spawned", false):
			reachable.append(mid)
	gut.p("    steal-response authors: %s | grind-reachable: %s" % [str(authors), str(reachable)])
	assert_gt(authors.size(), 0,
		"CONTROL: if nothing authors these flags the scan is measuring nothing and would pass empty")
	assert_eq(reachable.size(), 0,
		"a monster carrying first_steal_guaranteed/steal_response is now grind-reachable (%s) — the omission is a real gap, port it" % str(reachable))


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
const _PINNED_COUNT := 7

func test_every_resolver_member_this_file_reaches_still_exists() -> void:
	## @cowir-ai's counter to the snapshot limit above, and it converts the failure mode rather than
	## documenting it: a static list fails toward INCOMPLETENESS — add a reach tomorrow and the floor
	## silently covers all-but-one. This counts the distinct members reached in the text BEFORE this
	## function, so the arm cannot count its own `get`/`has_method` calls — @cowir-ai's bare-Object
	## exclusion replaced by SCOPING, which they named as the alternative. A new reach reds here.
	var own_src: String = FileAccess.get_file_as_string(get_script().resource_path)
	var cut: int = own_src.find("func %s(" % _FLOOR_ARM_NAME)
	assert_gt(cut, 0, "CONTROL: located this arm, so the scoped slice is real")
	var before: String = own_src.substr(0, cut)
	var reached: Dictionary = {}
	## ⛔ SKIP PATH LITERALS. `AutogrindSystem.gd` inside a res:// string matched as a member named
	## "gd" — the same false positive I fixed in the generator two hours earlier and reintroduced
	## here. A regex reading source cannot tell a member reach from a filename by shape.
	for raw_line in before.split("\n"):
		if raw_line.contains("res://") or raw_line.strip_edges().begins_with("#"):
			continue
		## ⛔ TRAILING COMMENTS TOO, per @cowir-sprites: a floor exists to catch a RENAME, and the commit
		## that renames a member is the one whose prose explains the rename BY NAME. `_res.foo()  #
		## renamed from _res.bar` would inflate this count and red a CORRECT file. Leading-## lines were
		## already skipped; this drops the trailing half. Measured 2026-09-16: strict and lenient
		## extraction agree on all ten floored files, so this is latent rather than a live repair.
		## NOT stripped: a member named inside a triple-quoted block. Measured absent in these files,
		## and recorded rather than handled — a quote-aware stripper here would be its own hazard.
		var code_only: String = raw_line.split("#")[0]
		for m in RegEx.create_from_string("(?:_res|AutogrindSystem)\\.([A-Za-z_][A-Za-z_0-9]*)").search_all(code_only):
			reached[m.get_string(1)] = true
	reached.erase("_test_disable_persistence")
	reached.erase("PER_BATTLE_METAS")   ## read from SOURCE on purpose — see the arm above
	gut.p("    reaches before this arm: %d | pinned: %d" % [reached.size(), _PINNED_COUNT])
	assert_gt(reached.size(), 0, "CONTROL: the scan found reaches, or this count proves nothing")
	assert_eq(reached.size(), _PINNED_COUNT,
		"this file now reaches %d distinct members and the floor pins %d — add the new one, the list is a snapshot: %s" % [reached.size(), _PINNED_COUNT, str(reached.keys())])

	var missing: Array = []
	if _res.get("_battle_log") == null: missing.append("_battle_log")
	if _res.get("_enemy_party") == null: missing.append("_enemy_party")
	if _res.get("_player_party") == null: missing.append("_player_party")
	if _res.get("_stolen_gold") == null: missing.append("_stolen_gold")
	if not _res.has_method("_build_results"): missing.append("_build_results()")
	if not _res.has_method("_resolve_ability"): missing.append("_resolve_ability()")
	if not _res.has_method("_roll_steal"): missing.append("_roll_steal()")
	assert_eq(missing, [],
		"the resolver no longer has these, so the arms above would ABORT into a silent pass: %s" % str(missing))
