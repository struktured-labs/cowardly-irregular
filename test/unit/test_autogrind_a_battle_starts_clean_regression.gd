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
	## Array[DICTIONARY], not Array[String] — I appended a String here first and the control failed
	## while the code was fine. The typed-array trap CLAUDE.md documents, inside the arm written to
	## catch over-clearing.
	hero.permanent_injuries.append({"id": "cracked_rib", "name": "Cracked Rib"})
	_res.resolve_battle([hero], [_chaff()])
	assert_eq(hero.current_hp, 500, "HP must carry across the boundary — that is the whole risk model of a grind")
	assert_eq(hero.current_mp, 7, "and so must MP")
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
	var declared: Array = _res.PER_BATTLE_METAS
	assert_gt(declared.size(), 0, "CONTROL: PER_BATTLE_METAS must be readable and non-empty")

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

	var unlisted: Array = []
	for k in found:
		if not declared.has(k):
			unlisted.append(k)
	assert_eq(unlisted, [],
		"these metas are set by the grind and NOT cleared at the battle boundary: %s — add them to PER_BATTLE_METAS or say why they outlive a battle" % str(unlisted))
