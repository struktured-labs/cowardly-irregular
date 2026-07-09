extends GutTest

## Class-killer (2026-07-09): a support/song/status ability whose `effect` has
## no arm in BattleManager._execute_support_ability falls to the `_:` default
## and SILENTLY FIZZLES — MP+AP spent, animation plays, nothing happens. This
## class has bitten twice already (tick 378 soul_wail, tick 380 fester). This
## scans every authored support-family effect against the live match arms so a
## new ability can't join the class unnoticed.

## Effects deliberately handled OUTSIDE the support match (documented routes).
const ROUTED_ELSEWHERE := {
	"copy_last_ability": "mimic path, tick 406 — intercepted before the match",
}


func _support_match_arms() -> Dictionary:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var i := src.find("func _execute_support_ability")
	assert_gt(i, 0, "_execute_support_ability must exist")
	var body := src.substr(i, src.find("\nfunc ", i + 10) - i)
	var arms := {}
	var rx := RegEx.new()
	rx.compile("(?m)^\\t\\t((?:\"[a-z_]+\"(?:,\\s*)?)+):")
	var inner := RegEx.new()
	inner.compile("\"([a-z_]+)\"")
	for m in rx.search_all(body):
		for im in inner.search_all(m.get_string(1)):
			arms[im.get_string(1)] = true
	return arms


func test_every_support_effect_has_a_match_arm() -> void:
	var arms := _support_match_arms()
	assert_gt(arms.size(), 40, "sanity: the support match should expose its arm roster")
	var abilities = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var checked := 0
	for aid in abilities:
		var ab = abilities[aid]
		if typeof(ab) != TYPE_DICTIONARY:
			continue
		if not (str(ab.get("type", "")) in ["support", "song", "status"]):
			continue
		var eff := str(ab.get("effect", ""))
		if eff == "" or ROUTED_ELSEWHERE.has(eff):
			continue
		checked += 1
		assert_true(arms.has(eff),
			"ability '%s' authors effect '%s' with NO arm in _execute_support_ability — it will fall to '_:' and silently fizzle (MP spent, nothing happens; the soul_wail/fester class)" % [aid, eff])
	assert_gt(checked, 30, "sanity: the support-ability roster should be scanned")


func test_death_sentence_stays_honest_while_inert() -> void:
	# F1 ruling keeps the doom INERT (no player delete-button). The old
	# description promised "dies in 3 turns" — a 30-MP no-op with a lying
	# tooltip. The text now admits the backlog; if someone activates the
	# doom later, update BOTH the chance and this pin together.
	var abilities = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var ds: Dictionary = abilities["death_sentence"]
	assert_false(ds.has("effect_chance"), "stays inert per the F1 ruling")
	assert_false("dies in" in str(ds.get("description", "")).to_lower(),
		"description must not promise a death the effect never applies")
	assert_true("no effect" in str(ds.get("description", "")).to_lower(),
		"description admits the inertness (honestly, with a bureau)")
