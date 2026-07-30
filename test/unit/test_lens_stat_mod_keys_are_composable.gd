extends GutTest

## A Lens stat_mod key that get_passive_mods does not already carry is SILENTLY
## DROPPED, and the Lens does nothing.
##
## PassiveSystem._compose_lens_mods:407
##     for key in lens_mods:
##         if not total_mods.has(key):
##             continue          # <- no warning, no log, no effect
##
## The two paths are asymmetric and only one of them is forgiving:
##   passives  _compose_mod CREATES a missing key (steal_chance reaches
##             BattleManager._steal_success_rate exactly this way)
##   lenses    skipped unless total_mods already has it
##
## So the passive author's intuition — "add a stat_mod key and read it downstream" —
## is correct for passives and silently wrong for Lenses. Nothing in the code says
## so. The rule is documented only in data/lenses.json's `_stat_mod_vocabulary`
## prose field, which is a data file no code reads: the same place a six-month-old
## known defect (AbilitiesMenu's `or true`) sat undiscovered until 2026-07-30.
##
## All 4 shipped Lenses are fine today (attack/defense/max_hp multipliers). This
## guard exists so the FIFTH one cannot ship inert.
##
## The composable key set is DERIVED at runtime from get_passive_mods rather than
## copied, so adding a key to that dict automatically widens what Lenses may use —
## a pinned list would be a second source that drifts the moment someone extends it.

const LENSES_PATH := "res://data/lenses.json"


func _composable_keys() -> Dictionary:
	var ps: Node = get_node_or_null("/root/PassiveSystem")
	assert_not_null(ps, "PassiveSystem autoload must exist")
	if ps == null:
		return {}
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "KeyProbe"
	# No passives equipped, so this returns exactly the baseline dict that
	# _compose_lens_mods checks against with total_mods.has(key).
	return ps.get_passive_mods(c)


func _lenses() -> Dictionary:
	var txt := FileAccess.get_file_as_string(LENSES_PATH)
	assert_ne(txt, "", "lenses.json must be readable")
	var parsed: Variant = JSON.parse_string(txt)
	assert_true(parsed is Dictionary, "lenses.json must parse as a Dictionary")
	if not (parsed is Dictionary):
		return {}
	return (parsed as Dictionary).get("lenses", {})


func test_every_lens_stat_mod_key_survives_composition() -> void:
	var composable := _composable_keys()
	var lenses := _lenses()
	assert_gt(composable.size(), 5,
		"the baseline mod dict must have real keys, else every assertion below is vacuous")
	assert_gt(lenses.size(), 0,
		"lenses.json must carry lenses, else this guard tests nothing")
	var dropped: Array[String] = []
	var checked := 0
	for lid in lenses:
		var mods: Variant = (lenses[lid] as Dictionary).get("stat_mods", {})
		if not (mods is Dictionary):
			continue
		for key in (mods as Dictionary):
			checked += 1
			if not composable.has(key):
				dropped.append("%s.%s" % [lid, key])
	assert_gt(checked, 0, "must check real stat_mod keys, else the assertion below is vacuous")
	assert_eq(dropped, [] as Array[String],
		"these Lens stat_mods are silently dropped by _compose_lens_mods — the Lens "
		+ "equips, reads correctly in the UI, and has NO combat effect. Either add the "
		+ "key to get_passive_mods' baseline dict or use one it already carries.")


## Positive control: the probe must be able to SEE a bad key. Without this the test
## above passes because _composable_keys returned something permissive, not because
## the shipped Lenses are correct.
func test_an_unsupported_key_would_be_detected() -> void:
	var composable := _composable_keys()
	assert_false(composable.has("zzz_not_a_real_stat"),
		"an invented key must NOT be composable, else the guard cannot fail")
	assert_true(composable.has("attack_multiplier"),
		"a key the shipped Lenses actually use must be composable, else the guard "
		+ "would fail on correct data")


## Pins the asymmetry itself, so a refactor that makes lens composition additive
## (or passive composition strict) fails here rather than silently changing which
## authoring mistakes are survivable.
func test_passive_composition_creates_missing_keys_but_lens_does_not() -> void:
	var total := {"attack_multiplier": 1.0}
	PassiveSystem._compose_mod(total, "zzz_novel_key", 0.25)
	assert_true(total.has("zzz_novel_key"),
		"_compose_mod must CREATE unknown keys — this is why passive stat_mods like "
		+ "steal_chance reach their consumers")
	var src := FileAccess.get_file_as_string("res://src/jobs/PassiveSystem.gd")
	assert_true(src.contains("if not total_mods.has(key):"),
		"_compose_lens_mods must still guard on has(key) — if this changes, the "
		+ "silent-drop this file documents no longer exists and the guard needs revisiting")
