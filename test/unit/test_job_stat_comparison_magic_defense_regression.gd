extends GutTest

## JobMenu stat comparison must surface magic_defense (2026-07-29).
##
## magic_defense became a real stat hours ago — Combatant.take_damage
## picks it for magical damage instead of defense. ALL 14 jobs author a
## modifier for it, spread +30..+70, so switching job moves it by as much
## as 40 points.
##
## _get_stat_comparison iterated ["attack","defense","magic","speed",
## "max_hp"] and skipped it. The one screen whose entire job is showing
## how a job change moves your stats rendered that swing as NOTHING —
## not a zero, not a dash, absent. A player comparing Fighter (+70)
## against Summoner (+30) saw no difference in how much magic would hurt
## them.
##
## Behavioural, not a source pin: this calls the real method on a real
## JobMenu with real job dictionaries and reads the string a player
## would see. A contains() ratchet on the stat list would pass against a
## loop that skipped the value.

var _menu: JobMenu


func before_each() -> void:
	_menu = JobMenu.new()
	add_child_autofree(_menu)


func _character_with(mods: Dictionary) -> Combatant:
	var c: Combatant = autofree(Combatant.new())
	c.combatant_name = "Test"
	c.job = {"id": "test_current", "name": "Current", "stat_modifiers": mods}
	return c


## ── the regression ───────────────────────────────────────────────────

func test_magic_defense_delta_is_shown() -> void:
	_menu.character = _character_with({"magic_defense": 30})
	var out: String = _menu._get_stat_comparison(
		{"id": "t", "name": "T", "stat_modifiers": {"magic_defense": 70}})
	assert_string_contains(out, "MDF",
		"a magic_defense change must appear — it decides how much magic hurts")
	assert_string_contains(out, "+40",
		"the delta must be the real difference (70 - 30), not a placeholder")


func test_magic_defense_is_not_confused_with_magic() -> void:
	# StatNames maps magic->MAG and magic_defense->MDF precisely because
	# the substr fallback yields MAG for both. If that collision ever
	# returns, this screen would label a defensive change as offensive.
	_menu.character = _character_with({"magic": 10, "magic_defense": 30})
	var out: String = _menu._get_stat_comparison(
		{"id": "t", "name": "T", "stat_modifiers": {"magic": 10, "magic_defense": 70}})
	assert_string_contains(out, "MDF", "the changed stat is magic_defense")
	assert_false(out.contains("MAG"),
		"magic did NOT change here — labelling the MDF delta as MAG would invert the meaning for the player")


func test_unchanged_magic_defense_is_omitted_like_every_other_stat() -> void:
	# The screen lists only DIFFERENCES. A zero-delta MDF must stay quiet,
	# or adding the stat would add noise to every job comparison.
	_menu.character = _character_with({"magic_defense": 50, "attack": 10})
	var out: String = _menu._get_stat_comparison(
		{"id": "t", "name": "T", "stat_modifiers": {"magic_defense": 50, "attack": 25}})
	assert_string_contains(out, "ATK", "the stat that DID change must show")
	assert_false(out.contains("MDF"),
		"an unchanged magic_defense must not be listed — this screen shows deltas, not a stat block")


## ── the real corpus, so the fixture cannot drift from shipped data ────

func test_every_stat_any_job_modifies_is_surfaced() -> void:
	# THE PROPERTY, replacing the incident (@cowir-story msg 3398, and
	# @cowir-controller's derive-don't-list on the equipment panel).
	#
	# This file originally asserted that magic_defense appears — the stat
	# that happened to be broken. That is the bug report, not the
	# invariant. Deriving the set from jobs.json found max_mp equally
	# invisible: all 14 jobs author it, spread 30..100, so a Fighter ->
	# Summoner change more than TRIPLES the MP pool and the screen said
	# nothing. My incident-shaped guard passed the whole time.
	#
	# Derived, so a stat added to jobs.json tomorrow fails here until the
	# screen shows it. No allowlist — every entry is a real authored stat.
	var f: FileAccess = FileAccess.open("res://data/jobs.json", FileAccess.READ)
	assert_not_null(f)
	var jobs: Dictionary = JSON.parse_string(f.get_as_text())
	var modified: Dictionary = {}
	for jid in jobs:
		var mods: Variant = (jobs[jid] as Dictionary).get("stat_modifiers", {})
		if mods is Dictionary:
			for s in (mods as Dictionary):
				modified[str(s)] = true
	assert_gt(modified.size(), 3,
		"sanity: expected several modified stats, got %d — if this fires the parse is wrong and every assertion below is vacuous" % modified.size())
	for stat_name in modified:
		# A job differing ONLY in this stat must produce visible output.
		_menu.character = _character_with({stat_name: 10})
		var out: String = _menu._get_stat_comparison(
			{"id": "t", "name": "T", "stat_modifiers": {stat_name: 40}})
		assert_ne(out, "",
			"jobs author '%s' but a change in it renders NOTHING — the comparison screen omits a stat the player is choosing between" % stat_name)
		assert_string_contains(out, StatNames.short_code(stat_name),
			"a '%s' change must be labelled with its own code, not another stat's" % stat_name)
		# PREDICATE, not just presence (@cowir-sfx msg-3511): "non-empty and
		# contains the code" passes on a delta rendered with the WRONG SIGN.
		# Measured: inverting `new_val - current_val` is caught only by the two
		# hardcoded-value tests below, so it is covered for magic_defense and
		# invisible for any stat added later — which is the one case this
		# derived test exists to cover.
		assert_string_contains(out, "+30 %s" % StatNames.short_code(stat_name),
			"a +30 change in '%s' must render as +30, not -30 — a sign inversion tells the player a gain is a loss" % stat_name)


func test_every_shipped_job_authors_magic_defense() -> void:
	# The premise of the fix. If jobs stopped authoring it, the screen
	# would correctly show nothing and this regression would be moot —
	# so assert the premise rather than assuming it holds forever.
	var f: FileAccess = FileAccess.open("res://data/jobs.json", FileAccess.READ)
	assert_not_null(f)
	var jobs: Dictionary = JSON.parse_string(f.get_as_text())
	var missing: Array[String] = []
	for jid in jobs:
		var mods: Variant = (jobs[jid] as Dictionary).get("stat_modifiers", {})
		if not (mods is Dictionary) or not (mods as Dictionary).has("magic_defense"):
			missing.append(str(jid))
	assert_eq(missing, [] as Array[String],
		"every job authors magic_defense; if one stops, the comparison screen silently omits it again")


func test_real_job_pair_shows_the_swing() -> void:
	# Fighter +70 vs Summoner +30 — the widest authored gap, and the one
	# a player is most likely to be misled by. Driven from jobs.json so a
	# rebalance updates the expectation instead of falsifying it.
	var f: FileAccess = FileAccess.open("res://data/jobs.json", FileAccess.READ)
	var jobs: Dictionary = JSON.parse_string(f.get_as_text())
	if not (jobs.has("fighter") and jobs.has("summoner")):
		pending("fighter/summoner not present")
		return
	var fighter: Dictionary = jobs["fighter"]
	var summoner: Dictionary = jobs["summoner"]
	var expected: int = int((summoner["stat_modifiers"] as Dictionary)["magic_defense"]) \
		- int((fighter["stat_modifiers"] as Dictionary)["magic_defense"])
	if expected == 0:
		pending("fighter and summoner now share magic_defense — nothing to surface")
		return
	_menu.character = _character_with(fighter["stat_modifiers"])
	var out: String = _menu._get_stat_comparison(summoner)
	assert_string_contains(out, "%+d MDF" % expected,
		"the real Fighter->Summoner magic_defense swing must render, sign and all")
