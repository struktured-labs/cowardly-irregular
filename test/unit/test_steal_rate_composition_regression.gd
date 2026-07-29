extends GutTest

## Two paths roll for a steal and each grew its own inline clamp. 2026-07-29.
##
## @cowir-battle wired the Rogue `steal_boost` passive into the pure Steal handler — a real fix for a
## starter-job passive that promised "+30% steal success rate" and was read by nothing. Mug rolls its
## own steal in the physical branch, with a second clamp assembled independently, and the passive did
## not reach it. Tick 462 had already done the same thing one layer over: it wired thiefs_glove's
## `steal_bonus` into one of the two sites.
##
##   Steal   clampf(success_rate + steal_bonus + passive_steal, 0, 1)   both bonuses
##   Mug     clampf(success_rate + steal_bonus, 0, 1)                   equipment only
##
## So a Rogue equipping the passive got +30% on Steal and nothing on Mug. That does not read as a bug
## to a player — steals are already a dice roll, so a bonus that applies to half of them reads as
## variance. Two independent fixes each found one site; neither found two.
##
## Fixed by composing in one place. The guard below derives the site list from the STEAL ROLL itself
## rather than naming Steal and Mug — a third steal path would otherwise be the third time.

const SRC := "res://src/battle/BattleManager.gd"


func _source() -> String:
	return FileAccess.get_file_as_string(SRC)


## A steal roll is a line that consults `_first_steal_guaranteed` — the one-shot bypass BOTH paths
## share. Deriving from that finds a new steal path on the day it is written; a list of two never
## would, which is precisely how this defect reached its second author.
func _steal_roll_rate_vars() -> Array:
	var vars: Array = []
	for line in _source().split("\n"):
		if not line.contains("_first_steal_guaranteed("):
			continue
		if not line.contains("randf()"):
			continue
		var idx := line.find("randf() <")
		if idx < 0:
			continue
		var tail := line.substr(idx + 9).strip_edges()
		var name := ""
		for c in tail:
			if c.is_valid_identifier() or c == "_" or (name != "" and c.is_valid_int()):
				name += c
			else:
				break
		if name != "":
			vars.append(name)
	return vars


# ── the invariant ───────────────────────────────────────────────────

func test_every_steal_roll_composes_its_rate_in_one_place() -> void:
	# The general form. Each rate variable a steal roll compares against must be assigned from the
	# shared helper, not from a locally assembled clampf.
	var src := _source()
	var unrouted: Array = []
	for v in _steal_roll_rate_vars():
		var assigned_here := false
		for line in src.split("\n"):
			if line.contains("var %s:" % v) or line.contains("var %s " % v) or line.contains("var %s=" % v):
				if line.contains("_steal_success_rate("):
					assigned_here = true
		if not assigned_here:
			unrouted.append(v)
	assert_eq(unrouted, [],
		"steal roll(s) whose rate is composed locally instead of through _steal_success_rate: %s — "
			% str(unrouted)
		+ "that is how the passive reached Steal and not Mug")


func test_no_steal_path_reassembles_the_clamp_inline() -> void:
	# The direct form of the same thing. An inline clamp adding steal_bonus is the shape both
	# previous fixes left behind, and it is what a third author would copy.
	var offenders: Array = []
	for line in _source().split("\n"):
		var t := line.strip_edges()
		if t.begins_with("#") or t.begins_with("##"):
			continue
		if t.contains("clampf(") and t.contains("steal_bonus") and not t.contains("_steal_success_rate("):
			offenders.append(t.substr(0, 90))
	assert_eq(offenders, [], "a steal rate is being assembled outside the helper:\n  %s"
		% "\n  ".join(offenders))


func test_the_helper_reads_both_sources() -> void:
	# The helper is only worth routing through if it composes BOTH contributions. Asserting it
	# exists would pass against a helper that returns the base rate unchanged.
	var src := _source()
	var i := src.find("func _steal_success_rate(")
	assert_gt(i, -1, "the shared helper must exist")
	var body := src.substr(i, 700)
	assert_true(body.contains("steal_bonus"), "helper must read the equipment special effect")
	assert_true(body.contains("steal_chance"), "helper must read the passive stat_mod")
	assert_true(body.contains("clampf("), "helper must keep the 0..1 bound both sites had")


# ── the value the helper reads is real ──────────────────────────────

func test_the_passive_actually_yields_a_steal_chance() -> void:
	# Source routing proves the plumbing; this proves there is water in it. get_passive_mods
	# composes unknown keys rather than dropping them, which is why the value was always available
	# and merely unread — if that ever changes, routing correctly to a zero is still a dead passive.
	var ps: Node = get_node_or_null("/root/PassiveSystem")
	if ps == null:
		pending("PassiveSystem autoload unavailable")
		return
	var c := Combatant.new()
	c.combatant_name = "Rogue"
	c.equipped_passives.append("steal_boost")
	var mods: Dictionary = ps.get_passive_mods(c)
	assert_almost_eq(float(mods.get("steal_chance", 0.0)), 0.3, 0.001,
		"steal_boost authors stat_mods.steal_chance 0.3 — the helper reads this key")
	c.free()


func test_an_unequipped_rogue_gets_nothing() -> void:
	# Control. The assertion above passes against a get_passive_mods that returns 0.3 for anything.
	var ps: Node = get_node_or_null("/root/PassiveSystem")
	if ps == null:
		pending("PassiveSystem autoload unavailable")
		return
	var c := Combatant.new()
	c.combatant_name = "Rogue"
	var mods: Dictionary = ps.get_passive_mods(c)
	assert_almost_eq(float(mods.get("steal_chance", 0.0)), 0.0, 0.001,
		"a combatant with no passives must compose no steal_chance")
	c.free()


# ── positive control ────────────────────────────────────────────────

func test_the_derivation_finds_the_real_steal_rolls() -> void:
	# Every assertion above passes vacuously against a scan that returns []. Two steal paths exist
	# today; the count is asserted as a floor so adding a third is not a failure, but finding fewer
	# than two means the derivation stopped working and the greens above mean nothing.
	var vars: Array = _steal_roll_rate_vars()
	assert_gt(vars.size(), 1,
		"expected at least the Steal and Mug rolls — found %s. If _first_steal_guaranteed was "
			% str(vars)
		+ "renamed, this derivation is blind and every assertion above is vacuous")
	assert_true(_source().contains("_first_steal_guaranteed("),
		"the predicate this scan derives from must still exist in the source")
