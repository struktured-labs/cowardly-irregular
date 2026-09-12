extends GutTest

## The friendly-fire guard turned HARM into a SILENT NO-OP for every ability whose type has no arm.
## Strictly better than damaging the party — and cowir-sfx's finding the same hour is that a fix
## which degrades gracefully BLINDS the guard that found it: "does nothing" and "correctly handled"
## are indistinguishable from the outside, so the population can quietly convert into "fine".
##
## cowir-battle measured 21 ally-targeted abilities now inert in every grind — the entire meta-job
## kit plus Raise. CLAUDE.md calls meta jobs "all five REAL" and a design pillar, so this is a
## pillar that does not function in the mode the game is named for. That is a DESIGN question
## (what should undo_death do mid-grind?), explicitly struktured's, not a bug to invent an answer to.
##
## This census does not fix it. It refuses to let it go quiet: the count is pinned and the failure
## message NAMES the abilities, so implementing one forces a deliberate edit here rather than
## letting the set drift silently in either direction.

## ENUMERATED, not substring-matched. The first version used markers ["ally","self","party"] and
## silently dropped every all_allies ability, because "all_allies" does NOT contain "ally" — it
## contains "alli". Six abilities invisible, and the census under-reported with nothing to show it.
## Pinned by test_the_target_type_vocabulary_has_not_grown so a new shape cannot reopen the hole.
const ALLY_TARGET_TYPES := ["all_allies", "all_rat_allies", "dead_ally", "self", "single_ally"]
const ENEMY_TARGET_TYPES := ["all_enemies", "single_enemy", "last_attacker"]


func _type_of(ability_id: String) -> String:
	var f := FileAccess.open("res://data/abilities.json", FileAccess.READ)
	if f == null:
		return ""
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	var table: Dictionary = parsed.get("abilities", parsed)
	var v = table.get(ability_id, {})
	return str((v as Dictionary).get("type", "")) if typeof(v) == TYPE_DICTIONARY else ""


func _fresh(cname: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": cname, "max_hp": 400, "max_mp": 40,
		"attack": 10, "defense": 10, "magic": 20, "speed": 10
	})
	add_child_autofree(c)
	return c


## Observable state, not source text: HP, MP, buff/debuff count, status count. An ability that
## changes none of these did nothing to its target, whatever its implementation looks like.
func _fingerprint(c: Combatant) -> Array:
	## active_debuffs is a SEPARATE array from active_buffs (Combatant:89-90). Omitting it made
	## this census BLIND TO EVERY DEBUFF — a debuff-only ability read as inert, so the instrument
	## under-reported working abilities and would have missed a broken one. Found when mapping
	## volatility_down turned hedge_position from a bogus status into a real debuff and the census
	## called that a regression.
	return [c.current_hp, c.current_mp, c.active_buffs.size(), c.active_debuffs.size(), c.status_effects.size()]


func _ally_targeted_ability_ids() -> Array[String]:
	var out: Array[String] = []
	var f := FileAccess.open("res://data/abilities.json", FileAccess.READ)
	if f == null:
		return out
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	var table: Dictionary = parsed.get("abilities", parsed)
	for k in table.keys():
		var v = table[k]
		if typeof(v) != TYPE_DICTIONARY:
			continue
		if ALLY_TARGET_TYPES.has(str(v.get("target_type", ""))):
			out.append(str(k))
	return out


func _target_type_of(ability_id: String) -> String:
	var ability: Dictionary = JobSystem.get_ability(ability_id)
	return str(ability.get("target_type", "")) if ability is Dictionary else ""


func _effect_of(ability_id: String) -> String:
	var ability: Dictionary = JobSystem.get_ability(ability_id)
	return str(ability.get("effect", "")) if ability is Dictionary else ""


func _inert_ids() -> Array[String]:
	var inert: Array[String] = []
	for ability_id in _ally_targeted_ability_ids():
		var resolver := HeadlessBattleResolver.new()
		var caster := _fresh("Caster")
		var target := _fresh("Target")
		target.current_mp = 0        # leave headroom so a restore is observable
		target.current_hp = 200      # and so a heal is observable
		## Put the target in the state the ability is FOR. A revival hands back a corpse and
		## declines a living ally (mirroring BattleManager:5473), so a census that only ever
		## offers a LIVING target reads a correctly-declining arm as an absent one — which is
		## exactly what it did to `raise` the day revival was armed.
		if _target_type_of(ability_id) == "dead_ally":
			target.current_hp = 0
			target.is_alive = false
		## The same trap one effect over: esuna and garbage_collect CLEAR ailments, so an
		## unafflicted target leaves a correct arm with nothing to do and it reads as absent.
		## ⚠️ This only removes a false RED — it adds no detection, and do not trust it to.
		## Both states change the fingerprint: armed clears blind (1 status -> 0), unarmed writes
		## a bogus status named "cleanse" (1 -> 2). "Something changed" cannot separate them.
		## What cleanse actually does is guarded in test_a_grind_can_cure_what_it_inflicts.
		if _effect_of(ability_id) == "cleanse":
			target.add_status("blind", 3)
		resolver._player_party = [caster, target]
		resolver._enemy_party = []
		var before := _fingerprint(target)
		resolver._resolve_ability(caster, ability_id, [target])
		if _fingerprint(target) == before:
			inert.append(ability_id)
	return inert


## Types this resolver deliberately does not model. Deriving the expectation from TYPE rather than
## pinning a count: I measured 20 where cowir-battle derived 21 and could not explain the gap, and
## a number I cannot explain is not a ratchet — it is a coincidence waiting to be "fixed".
const UNMODELLED_TYPES := ["meta", "summon", "escape"]


func test_everything_inert_is_inert_for_a_KNOWN_reason() -> void:
	## The census refuses to let the population go quiet. It does not assert HOW MANY — it asserts
	## that every silent ability is silent because its TYPE is unmodelled. An ability that goes
	## inert for any other reason (an arm regressing) names itself here.
	var offenders: Array[String] = []
	for ability_id in _inert_ids():
		if not UNMODELLED_TYPES.has(_type_of(ability_id)):
			offenders.append("%s(%s)" % [ability_id, _type_of(ability_id)])
	assert_eq(offenders.size(), 0,
		("these abilities do NOTHING in a headless grind and their type IS modelled — an arm " +
		"regressed: %s") % str(offenders))


func test_the_inert_population_is_reported_not_hidden() -> void:
	## Names the set on every run. cowir-battle measured 21 ally-targeted abilities silenced by the
	## friendly-fire guard — the whole meta-job kit plus Raise. CLAUDE.md calls meta jobs a design
	## pillar, so this is a pillar that does not function in autogrind. Design, struktured's call.
	var inert := _inert_ids()
	inert.sort()
	gut.p("INERT IN HEADLESS (%d): %s" % [inert.size(), str(inert)])
	assert_gt(inert.size(), 0,
		"if this ever reaches zero the meta kit was implemented — delete this census, it has done its job")


func test_an_armed_ability_is_not_counted_inert() -> void:
	## ARM+. Without this a resolver that did nothing at all would score every ability inert and
	## the census would still "pass" once EXPECTED_INERT was updated to match.
	var inert := _inert_ids()
	for armed in ["cure", "pray", "battle_hymn"]:
		assert_false(inert.has(armed),
			"%s IS handled — if it appears here, its arm regressed and the census is measuring a broken resolver" % armed)


func test_the_census_can_actually_detect_inertness() -> void:
	## ARM+ the other way: prove the fingerprint notices a real no-op. A fabricated id reaches
	## nothing, so it must register as inert; if it does not, the detector is broken.
	var resolver := HeadlessBattleResolver.new()
	var caster := _fresh("Caster")
	var target := _fresh("Target")
	resolver._player_party = [caster, target]
	var before := _fingerprint(target)
	resolver._resolve_ability(caster, "zzq_not_a_real_ability", [target])
	assert_eq(_fingerprint(target), before,
		"control: an unknown ability must leave the target untouched, or the fingerprint is blind")


func _all_target_types() -> Array[String]:
	var seen: Array[String] = []
	var f := FileAccess.open("res://data/abilities.json", FileAccess.READ)
	if f == null:
		return seen
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	var table: Dictionary = parsed.get("abilities", parsed)
	for k in table.keys():
		var v = table[k]
		if typeof(v) != TYPE_DICTIONARY:
			continue
		var tt := str(v.get("target_type", ""))
		if tt != "" and not seen.has(tt):
			seen.append(tt)
	return seen


func test_the_target_type_vocabulary_has_not_grown() -> void:
	## The census can only see target types it enumerates. A new one silently falls outside BOTH
	## lists and its abilities become invisible — which is exactly how the substring version lost
	## all_allies. This makes that failure loud instead.
	var unknown: Array[String] = []
	for tt in _all_target_types():
		if not ALLY_TARGET_TYPES.has(tt) and not ENEMY_TARGET_TYPES.has(tt):
			unknown.append(tt)
	assert_eq(unknown.size(), 0,
		"unrecognised target_type(s) %s — add each to ALLY_ or ENEMY_TARGET_TYPES, or this census is blind to them" % str(unknown))


func test_the_ally_list_actually_selects_something_known() -> void:
	# ARM+: an empty or wrong ALLY list would make the census trivially pass everything above.
	var ids := _ally_targeted_ability_ids()
	assert_true(ids.has("pray"), "control: pray (single_ally) must be a candidate")
	assert_true(ids.has("battle_hymn"), "control: battle_hymn (all_allies) must be a candidate — the case the substring filter LOST")
	assert_false(ids.has("fire"), "control: an enemy-targeted ability must NOT be a candidate")


## ── SUPPORT-ARM CENSUS ──────────────────────────────────────────────────────────────────────
## The census above counts abilities reaching the `_:` default. My .242 support/song/status arm
## moved a different population OUT of that default and into add_status(effect) — so those 54 are
## outside the census BY CONSTRUCTION, which is the blind spot my own fix created.
##
## add_status() accepts ANY string, so a fabricated status is inert rather than an error: it
## neither works nor complains. This names the population instead of judging it — which effects
## are real statuses (invisible/reflect/regen are) versus fabrications (dispel/cleanse are not) is
## a design question, and there is NO canonical status vocabulary to answer it from: Combatant
## branches on 5 names, BattleManager carries a separate list of 10, no single source of truth.

## DERIVED from _effect_to_stat's own source, never copied. A hardcoded duplicate made this test
## hollow: deleting magic_defense_up from the RESOLVER left the suite green, because the test was
## consulting its own copy of the map. Mutation caught it; the same two-sources-one-surface class
## this file exists to police.
func _mapped_effects() -> Array[String]:
	var out: Array[String] = []
	var src: String = load("res://src/autogrind/HeadlessBattleResolver.gd").source_code
	var start: int = src.find("func _effect_to_stat")
	var stop: int = src.find("\nfunc ", start + 1)
	if start < 0 or stop < 0:
		return out
	var body: String = src.substr(start, stop - start)
	var re := RegEx.new()
	re.compile('"([a-z_]+)":\\s*return')
	for m in re.search_all(body):
		out.append(m.get_string(1))
	return out

## Handled by their own branch rather than by the stat map.
const SPECIAL_EFFECTS := ["all_stats_down", "mp_restore_and_ap"]


func _support_arm_effects_falling_to_add_status() -> Array[String]:
	var out: Array[String] = []
	var f := FileAccess.open("res://data/abilities.json", FileAccess.READ)
	if f == null:
		return out
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	var table: Dictionary = parsed.get("abilities", parsed)
	for k in table.keys():
		var v = table[k]
		if typeof(v) != TYPE_DICTIONARY:
			continue
		if not ["support", "song", "status"].has(str(v.get("type", ""))):
			continue
		if str(v.get("stat", "")) != "":
			continue          # explicit stat wins; never reaches the effect map
		var e := str(v.get("effect", ""))
		if e == "" or _mapped_effects().has(e) or SPECIAL_EFFECTS.has(e):
			continue
		if not out.has(e):
			out.append(e)
	out.sort()
	return out


func test_every_stat_shaped_effect_is_mapped() -> void:
	## The part with no design content: an effect ending _up/_down names a STAT, so falling to
	## add_status is unambiguously wrong. This is how magic_defense_up and volatility_down were
	## found — I had shipped a map covering only the effects the four songs happened to use.
	var unmapped: Array[String] = []
	for e in _support_arm_effects_falling_to_add_status():
		if e.ends_with("_up") or e.ends_with("_down"):
			unmapped.append(e)
	assert_eq(unmapped.size(), 0,
		"stat-shaped effects with no map entry — they become a bogus status instead of a buff: %s" % str(unmapped))


func test_the_unmapped_effect_population_is_reported() -> void:
	## Names what routes to add_status every run, so the set cannot quietly become "fine".
	## NOT asserting a count: which of these are real statuses is undecided, and pinning a number
	## would freeze a figure nobody has ruled on.
	var falling := _support_arm_effects_falling_to_add_status()
	gut.p("EFFECTS ROUTED TO add_status (%d distinct): %s" % [falling.size(), str(falling)])
	assert_true(falling.size() > 0,
		"if this reaches zero every effect is modelled — delete this census, it has done its job")


func test_the_effect_scan_can_actually_find_something() -> void:
	# ARM+: a filter that selected nothing would pass the stat-shaped assertion vacuously.
	var falling := _support_arm_effects_falling_to_add_status()
	assert_true(falling.has("dispel"),
		"control: dispel authors no stat and is unmapped, so the scan must see it")
	assert_false(falling.has("attack_up"),
		"control: a MAPPED effect must NOT appear — it never reaches add_status")


func test_the_map_derivation_reads_the_real_function() -> void:
	## ARM+ for the derivation: if this returned [] the stat-shaped assertion would pass by
	## calling EVERY effect unmapped... no — it would FAIL loudly, which is the safe direction.
	## But an over-broad match would silently mark everything mapped, so pin both ends.
	var mapped := _mapped_effects()
	assert_true(mapped.has("attack_up"), "control: a known map entry must be derived, got %s" % str(mapped))
	assert_false(mapped.has("dispel"), "control: a non-entry must NOT be derived — the regex is over-broad")


## ── REACHABILITY ────────────────────────────────────────────────────────────────────────────
## The census reported "21 inert" all day. Accurate for its corpus and MISLEADING ABOUT IMPACT:
## 18 of them belong to advanced/meta jobs a grinding party cannot have, or to monsters. The
## number invited exactly the reading I gave it, which is the same way field elites "working in
## W1 only" hid which cases mattered.
##
## And "in a starter job's kit" is itself a DEFINITION, not what a party holds — cowir-music's
## rule: a key being mentioned is not the same as a consumer loading it. Starting kits are lean
## and the rest are level-gated, so this reads BOTH stores: the base `abilities` list and
## `abilities_at_level`. Traced 2026-09-09: flee is a Rogue base ability (level 1), raise unlocks
## for the Cleric at level 10 — mid-W1, so a cleric carries it for most of a real playthrough.

const STARTER_JOB_TYPE := 0

## EIGHT, not the seven I first wrote: the ratchet below caught my own hardcoded list being short by
## new_game_plus_warp (skiptrotter, unlock_condition "beat_game_once"). I produced the seven with a
## throwaway script and the guard — which reads the real store — disagreed and named the missing one.
## File-level so both the missing-entry arm AND the stale-entry arm read ONE list; two copies would
## be the duplication class this file exists to police.
const KNOWN_INERT := ["flee", "bypass_puzzle", "sequence_break", "skip_cutscene",
	"warp_to_boss", "recursive_summon", "new_game_plus_warp"]


## ⛔ CORRECTED 2026-09-09: this read STARTER jobs only, because a comment of mine asserted that
## advanced/meta jobs are "gated behind debug mode" and a grinding party cannot have them. I never
## grepped the consumer. JobSystem.is_job_unlocked returns true for a starter job, true under
## debug, and otherwise consults unlock_condition — so debug is a BYPASS, not the gate. Measured:
## all 4 advanced jobs and 2 of 5 meta jobs (bossbinder, skiptrotter) carry unlock_conditions and
## are reachable in normal play. My "2 reachable" was really 7.
## cowir-main's rule, the day it went fleet-wide: a comment naming a consumer is a QUERY, not a
## fact — and this one was mine, in the guard whose job is to stop exactly this kind of overreach.
func _player_reachable_abilities() -> Dictionary:
	var out: Dictionary = {}
	var f := FileAccess.open("res://data/jobs.json", FileAccess.READ)
	if f == null:
		return out
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	var jobs: Dictionary = parsed.get("jobs", parsed)
	for jid in jobs.keys():
		var j = jobs[jid]
		if typeof(j) != TYPE_DICTIONARY:
			continue
		## Starter always, everything else only if it carries an unlock_condition — mirroring
		## is_job_unlocked, minus the debug bypass, which is not "normal play".
		var jt: int = int(j.get("type", j.get("job_type", -1)))
		var cond = j.get("unlock_condition", {})
		var unlockable: bool = (jt == STARTER_JOB_TYPE) or (typeof(cond) == TYPE_DICTIONARY and not (cond as Dictionary).is_empty())
		if not unlockable:
			continue
		for a in j.get("abilities", []):
			out[str(a)] = 1
		var gated = j.get("abilities_at_level", {})
		if typeof(gated) == TYPE_DICTIONARY:
			for lv in gated.keys():
				for a in gated[lv]:
					var prev: int = int(out.get(str(a), 9999))
					out[str(a)] = mini(prev, int(str(lv)))
	return out


func test_the_census_separates_REACHABLE_from_unreachable() -> void:
	## The headline count is not the actionable one. Print the split so nobody (including me)
	## reads 20 as 20 problems.
	var reach := _player_reachable_abilities()
	var hit: Array[String] = []
	var unreachable := 0
	for a in _inert_ids():
		if reach.has(a):
			hit.append("%s(lv%d)" % [a, int(reach[a])])
		else:
			unreachable += 1
	hit.sort()
	gut.p("INERT + REACHABLE WITHOUT DEBUG (%d): %s" % [hit.size(), str(hit)])
	gut.p("INERT but unreachable in a normal grind (%d): meta/advanced jobs or monster abilities" % unreachable)
	assert_gt(reach.size(), 0, "control: the starter-kit store must load, else everything reads unreachable")


func test_no_NEW_starter_reachable_ability_becomes_inert() -> void:
	## The ratchet that matters. These two are known and go to struktured as design questions —
	## raise lands in the headless-revival gap he already owns. A THIRD one appearing is a
	## regression and names itself here rather than hiding inside an aggregate of 20.
	## The seven a player can actually reach without debug mode. Was ["flee","raise"] while this
	## read starter jobs only — skiptrotter's four and summoner's recursive_summon were invisible.
	var unexpected_known := KNOWN_INERT
	var reach := _player_reachable_abilities()
	var unexpected: Array[String] = []
	for a in _inert_ids():
		if reach.has(a) and not unexpected_known.has(a):
			unexpected.append(a)
	assert_eq(unexpected.size(), 0,
		"a starter-reachable ability became inert in headless: %s" % str(unexpected))


func test_the_reachability_reader_is_not_vacuous() -> void:
	# ARM+: an empty or wrong store would make every ability look unreachable and the ratchet above
	# would pass no matter what broke.
	var reach := _player_reachable_abilities()
	assert_true(reach.has("cure"), "control: cure is a Cleric base ability and must resolve")
	assert_true(reach.has("raise"), "control: raise is level-gated and must still be found")
	assert_eq(int(reach.get("raise", -1)), 10, "raise unlocks at level 10 — the gate must be READ, not assumed")
	assert_false(reach.has("undo_death"),
		"control: undo_death belongs to Time Mage, which has NO unlock_condition — debug-only, so not reachable")
	assert_true(reach.has("warp_to_boss"),
		"control: skiptrotter HAS an unlock_condition, so its abilities ARE reachable — the case my starter-only reader missed")


func test_the_KNOWN_allowlist_can_EXPIRE() -> void:
	## cowir-sprites: "an exception justified by a HUMAN JUDGEMENT cannot expire on its own, because
	## the judgement is not re-computable." KNOWN is exactly that — its reason is "these are design
	## questions for struktured", which no check re-derives.
	##
	## The rot was one-directional. The ratchet above catches a NEW inert ability missing from
	## KNOWN, but nothing catches an entry that no longer needs suppressing: implement headless
	## revival and `raise` drops out of the inert set, the ratchet stops consulting it, and the
	## entry survives forever suppressing nothing. That is a suppression whose condition has ended
	## with no transition anyone can detect.
	##
	## This makes it expire: every KNOWN entry must STILL be inert. When one gets fixed, this reds
	## and names it, and a human removes it deliberately.
	var inert := _inert_ids()
	var stale: Array[String] = []
	for a in KNOWN_INERT:
		if not inert.has(a):
			stale.append(a)
	assert_eq(stale.size(), 0,
		("these are allowlisted as known-inert but are NOT inert any more — someone fixed them, " +
		"so remove them from KNOWN_INERT rather than leaving a suppression with no subject: %s") % str(stale))


func test_no_suppression_entry_outlives_its_reason() -> void:
	## An UNMODELLED_TYPES line for a type the detector can no longer emit suppresses NOTHING, and
	## it hides the next real regression in that type behind a permanently-satisfied exemption.
	## revival was armed on 2026-09-09 and its entry sat here still reading as reasonable — the
	## census stayed green whether or not the entry belonged, which is the whole failure mode.
	var live_types: Dictionary = {}
	for ability_id in _inert_ids():
		live_types[_type_of(ability_id)] = true
	var stale: Array[String] = []
	for t in UNMODELLED_TYPES:
		if not live_types.has(t):
			stale.append(t)
	assert_eq(stale.size(), 0,
		("these types are exempted as unmodelled but the census can no longer produce them — " +
		"the arm was implemented and the exemption is now inert, delete it: %s") % str(stale))
