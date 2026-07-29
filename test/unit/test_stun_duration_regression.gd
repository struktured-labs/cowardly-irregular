extends GutTest

## Turn-skip statuses were decremented TWICE per round. 2026-07-29.
##
## Two writers to one dictionary, and nobody enumerated them:
##
##   Combatant.update_buff_durations()   generic per-round tick, no exclusion list
##   the turn-skip handler               reads the duration and decrements it again
##
## Both run every round, so a declared duration burns at 2/round. Measured delivered skips:
##
##   declared      1   2   3   4   5   10
##   stun          0   1   1   1   1    1      erases on consume -> SATURATES at one skip
##   cannot_act    0   1   1   2   2    5      decrements on consume -> floor(N/2)
##
## Both are ZERO at declared 1, which is the authored value everywhere it matters: 14 of the 20
## stun abilities, all 5 `skip_turn` jailbreak consequences, and the 4 `lose_buff_or_stagger`
## stagger fallbacks. The jailbreak half is the sharp one — a player who reads a boss's persona,
## finds its vulnerability and lands the exploit gets nothing at all, on Mordaine and all four
## dragons, whenever the boss's next turn falls in a later round.
##
## MY FIRST VERSION OF THIS FILE PASSED WHILE THE FIX WAS INERT. It asserted against a local helper
## applying only the consume half — a model of the system with ONE writer. Every behavioural test
## agreed with itself and none touched `end_turn()`. cowir-battle's A/B on real production functions
## caught it: the branch moved only `declared=4`, because copying the `cannot_act` pattern converts
## stun from saturate-at-1 to floor(N/2), and nothing in the data declares 4.
##
## So the runtime assertions drive `end_turn()` — the actual generic tick. BOUNDARY, stated rather
## than implied: they do not drive `BattleManager._start_new_round()`, so the consume half is pinned
## by source derivation. The half that can be executed is executed.

const BM_SRC := "res://src/battle/BattleManager.gd"
const HBR_SRC := "res://src/autogrind/HeadlessBattleResolver.gd"


# ── runtime: the generic tick, real production ──────────────────────

func test_the_generic_tick_no_longer_eats_a_turn_skip_duration() -> void:
	# The defect, executed. Before the fix this came back 1 — the round tick spending a unit the
	# skip handler had not yet been given a chance to consume.
	var c := Combatant.new()
	c.combatant_name = "Probe"
	c.add_status("stun", 2)
	c.end_turn()
	assert_eq(int(c.status_durations.get("stun", -99)), 2,
		"the per-round tick must leave stun alone — the turn-skip handler owns its countdown")
	c.free()


func test_a_one_turn_stun_survives_to_reach_its_own_handler() -> void:
	# The live case and the worst one. Before the fix the generic tick expired a 1-turn stun to zero
	# and removed it, so the skip handler never saw it and no turn was ever skipped.
	var c := Combatant.new()
	c.add_status("stun", 1)
	c.end_turn()
	assert_true(c.has_status("stun"),
		"a 1-turn stun must still exist when its target's turn arrives — this is the jailbreak case")
	c.free()


func test_cannot_act_is_protected_too() -> void:
	# Held up as the correct reference implementation by three lanes, and double-ticked itself. It
	# decrements rather than erasing, so it degraded to floor(N/2) instead of saturating at one — a
	# different symptom of the same second writer, which is exactly why it read as correct.
	var c := Combatant.new()
	c.add_status("cannot_act", 2)
	c.end_turn()
	assert_eq(int(c.status_durations.get("cannot_act", -99)), 2,
		"cannot_act is the boss-jailbreak lockout and shares the defect")
	c.free()


func test_ordinary_statuses_still_tick() -> void:
	# CONTROL, and what makes the three above mean anything. An exclusion that swallowed everything
	# would pass them all and freeze every poison and regen in the game.
	var c := Combatant.new()
	c.add_status("poison", 3)
	c.end_turn()
	assert_eq(int(c.status_durations.get("poison", -99)), 2,
		"the generic tick must still count down statuses nobody else owns")
	c.free()


func test_an_ordinary_status_still_expires() -> void:
	# The other half of the control: exclusion must not stop expiry.
	var c := Combatant.new()
	c.add_status("poison", 1)
	c.end_turn()
	assert_false(c.has_status("poison"), "a 1-turn poison must still wear off on its own")
	c.free()


# ── the exclusion set, derived ──────────────────────────────────────

func test_every_consume_owned_status_is_excluded_from_the_generic_tick() -> void:
	# Derived from the consume sites rather than trusting the const. A third turn-skip status added
	# with its own countdown, and not added here, silently reintroduces the double-write.
	var owned: Dictionary = {}
	for path in [BM_SRC, HBR_SRC]:
		var src := FileAccess.get_file_as_string(path)
		for line in src.split("\n"):
			if not line.contains("status_durations[\""):
				continue
			if not line.contains("] = ") or not line.contains(" - 1"):
				continue
			var i := line.find("status_durations[\"")
			var rest := line.substr(i + 18)
			var name := rest.substr(0, rest.find("\""))
			if name != "":
				owned[name] = true
	assert_gt(owned.size(), 0, "no consume-owned countdown found — this derivation is blind")
	var missing: Array = []
	for s in owned:
		if not (s in Combatant.CONSUME_OWNED_DURATIONS):
			missing.append(str(s))
	assert_eq(missing, [],
		"a turn-skip handler counts these down itself while the generic tick also decrements them "
		+ "— the double-write that made a 1-turn stun deliver nothing: %s" % str(missing))


func test_the_exclusion_is_not_a_blanket() -> void:
	# The failure direction of the fix. Excluding a status nobody consumes means it never expires.
	assert_lt(Combatant.CONSUME_OWNED_DURATIONS.size(), 4,
		"only statuses with a consume-path countdown belong here — a long list means something was "
		+ "excluded to silence a test rather than because a handler owns it")


func test_both_consume_paths_still_own_their_countdown() -> void:
	# Source-derived half, and the boundary named in the header. If a handler goes back to erasing,
	# the exclusion turns a halved duration into an infinite one.
	for path in [BM_SRC, HBR_SRC]:
		var src := FileAccess.get_file_as_string(path)
		var at: int = src.find("has_status(\"stun\")")
		assert_gt(at, -1, "%s must still handle stun" % path)
		var window: String = src.substr(at, 420)
		assert_true(window.contains("status_durations.get(\"stun\""),
			"%s must read the remaining duration, not erase it" % path)
		assert_true(window.contains("- 1"),
			"%s must decrement — with the generic tick excluded, this is the ONLY writer" % path)


# ── the data this defends ───────────────────────────────────────────

func test_the_corpus_still_declares_turn_skips() -> void:
	# Positive control. Every assertion above passes in a world where nothing stuns anyone. Derived
	# through the freeze->stun alias, because four of the multi-turn ones are spelled "freeze".
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var abilities: Dictionary = raw.get("abilities", raw)
	var one_turn: int = 0
	var multi: int = 0
	for id in abilities:
		var a: Dictionary = abilities[id]
		var eff := str(a.get("effect", ""))
		var meta := str(a.get("meta_effect", ""))
		if eff == "stun" or eff == "freeze" or meta == "time_stop":
			if int(a.get("duration", 1)) > 1:
				multi += 1
			else:
				one_turn += 1
	assert_gt(one_turn, 5,
		"the 1-turn stuns are the population that delivered ZERO — found %d" % one_turn)
	assert_gt(multi, 1, "and the multi-turn ones that delivered one — found %d" % multi)
