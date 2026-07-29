extends GutTest

## steal_boost promised +30% and did nothing (2026-07-29).
##
## Found by cowir-story (msg-3520) after fixing their own guard, which
## had been counting COMMENT lines as consumers. steal_boost is a ROGUE
## passive — a starter job — describing "+30% steal success rate" on an
## equip button, with stat_mods.steal_chance read by nothing.
##
## THE IDENTICAL DEFECT WAS ALREADY FIXED ONE LAYER OVER. Tick 462 wired
## equipment's steal_bonus into the same expression, with a comment
## saying thiefs_glove "gave the stat boost but not the headline +25%
## steal success the name promised". The passive version survived that
## fix because the fix enumerated equipment, not the class.
##
## get_passive_mods composes UNKNOWN keys rather than dropping them
## (_compose_mod creates the entry then adds), so the value was always
## available and simply unread — data with a producer, no consumer.

const PASSIVES: String = "res://data/passives.json"


## ── the promise, from shipped data ───────────────────────────────────

func test_steal_boost_authors_what_its_description_claims() -> void:
	var f: FileAccess = FileAccess.open(PASSIVES, FileAccess.READ)
	assert_not_null(f)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	assert_true(d.has("steal_boost"), "steal_boost must exist")
	var p: Dictionary = d["steal_boost"]
	assert_string_contains(str(p.get("description", "")), "30",
		"the description promises a concrete percentage — that is what makes it a lie when unread")
	assert_almost_eq(float((p.get("stat_mods", {}) as Dictionary).get("steal_chance", 0.0)), 0.3, 0.001,
		"stat_mods.steal_chance must match the advertised 30%")


## ── the value survives the accessor ──────────────────────────────────

func test_get_passive_mods_carries_steal_chance_through() -> void:
	# The premise of the fix. _compose_mod creates unknown keys rather
	# than filtering to a known set — if that ever changes to a filter,
	# the read below silently returns 0.0 and the passive goes quiet
	# again with nothing failing.
	var ps: Node = get_tree().root.get_node_or_null("PassiveSystem")
	if ps == null:
		pending("PassiveSystem autoload unavailable")
		return
	var c: Combatant = autofree(Combatant.new())
	c.combatant_name = "Rogue"
	c.is_alive = true
	c.equipped_passives.append("steal_boost")
	var mods: Dictionary = ps.get_passive_mods(c)
	assert_true(mods.has("steal_chance"),
		"get_passive_mods must carry steal_chance through — if it starts filtering to known keys, the steal read returns 0.0 and this passive is decoration again")
	assert_almost_eq(float(mods["steal_chance"]), 0.3, 0.001,
		"the composed value must be the authored 0.3")


## ── the consumer exists on the steal path ────────────────────────────

func test_steal_reads_the_passive_not_only_equipment() -> void:
	# Tick 462 wired equipment's steal_bonus and stopped there. This
	# asserts the passive is summed on the SAME expression, so the two
	# sources cannot drift apart again.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var at: int = src.find('"steal":')
	assert_gt(at, -1, "the steal arm must exist")
	var body: String = src.substr(at, 1400)
	assert_string_contains(body, "steal_chance",
		"the steal arm must read the passive's steal_chance — equipment alone was tick 462's scope, not the class")
	var rate_line: int = body.find("var effective_rate")
	assert_gt(rate_line, -1, "the success rate must still be computed in one place")
	var rate_expr: String = body.substr(rate_line, 160)
	assert_string_contains(rate_expr, "steal_bonus",
		"equipment's contribution must survive — this widens the rate, it does not replace it")
	assert_string_contains(rate_expr, "passive_steal",
		"the passive's contribution must be summed into the SAME rate, or the two sources drift")
	assert_string_contains(rate_expr, "clampf",
		"the sum must stay clamped — stacking sources must not push the rate past 1.0 and make the randf check always-true")
