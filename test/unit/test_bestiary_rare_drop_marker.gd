extends GutTest

## tick 256: rare-drop ★ marker in BestiaryMenu._format_drops.
##
## UX: previously the bestiary listed drops as "bone 75%, scale 5%"
## with no visual emphasis on rare items. A player scanning the menu
## for "what should I farm" had to mentally compute the rarity for
## each row. Adding ★ next to sub-10%-chance drops gives instant
## scan-ability and matches the threshold used by the rare_drop_found
## event flag (tick 250) — consistent "rare" semantics across
## features.
##
## Threshold: < 0.10 (10%) base chance. Pre-multiplier so a 5% base
## drop is "rare" regardless of any temporary drop_rate_multiplier.

const BESTIARY_MENU := "res://src/ui/BestiaryMenu.gd"


func _menu() -> Object:
	# BestiaryMenu extends Control; we just need access to _format_drops.
	var script: GDScript = load(BESTIARY_MENU)
	var instance: Object = script.new()
	add_child_autofree(instance)
	return instance


# ── Rare drop gets ★ marker ────────────────────────────────────────

func test_rare_drop_gets_star_marker() -> void:
	var menu: Object = _menu()
	var drops: Array = [{"item": "dragon_scale", "chance": 0.05}]
	var s: String = menu._format_drops(drops, null)
	assert_true(s.contains("★"),
		"a 5%% drop must be marked with ★ in the drops string (got: %s)" % s)


# ── Just-rare boundary (9%) → marker ───────────────────────────────

func test_boundary_below_10_percent_gets_marker() -> void:
	var menu: Object = _menu()
	var drops: Array = [{"item": "scale", "chance": 0.09}]
	var s: String = menu._format_drops(drops, null)
	assert_true(s.contains("★"),
		"a 9%% drop must be marked with ★ (just under the 10%% boundary)")


# ── Not-rare (10% exactly) → no marker ─────────────────────────────

func test_exactly_10_percent_no_marker() -> void:
	var menu: Object = _menu()
	var drops: Array = [{"item": "scale", "chance": 0.10}]
	var s: String = menu._format_drops(drops, null)
	assert_false(s.contains("★"),
		"a 10%% drop must NOT be marked rare — strict < 10%% threshold")


# ── Common drops never marked ─────────────────────────────────────

func test_common_drops_no_marker() -> void:
	var menu: Object = _menu()
	var drops: Array = [{"item": "bone", "chance": 0.75}]
	var s: String = menu._format_drops(drops, null)
	assert_false(s.contains("★"),
		"a 75%% drop must not be marked rare")
	assert_false(s.contains("(★ = rare)"),
		"legend must NOT appear when no drops qualify as rare")


# ── Mixed: legend only when at least one rare ─────────────────────

func test_legend_appears_when_any_rare_drop_present() -> void:
	var menu: Object = _menu()
	var drops: Array = [
		{"item": "bone", "chance": 0.75},
		{"item": "dragon_scale", "chance": 0.03},
	]
	var s: String = menu._format_drops(drops, null)
	assert_true(s.contains("(★ = rare)"),
		"legend '(★ = rare)' must appear when ≥1 drop qualifies as rare")


# ── No drops: still says "—" (regression check) ────────────────────

func test_empty_drops_still_dash() -> void:
	var menu: Object = _menu()
	var s: String = menu._format_drops([], null)
	assert_true(s.contains("—"),
		"empty drops table must still render '—' (regression check)")
	assert_false(s.contains("★"),
		"empty drops table must not show the ★ marker or legend")


# ── one_shot_reward still appended ────────────────────────────────

func test_one_shot_reward_still_renders_alongside_rare_marker() -> void:
	# Cross-pin: the ★ logic doesn't break the existing one-shot suffix.
	var menu: Object = _menu()
	var drops: Array = [{"item": "scale", "chance": 0.05}]
	var s: String = menu._format_drops(drops, "elixir")
	assert_true(s.contains("★"), "rare marker still applies")
	assert_true(s.contains("One-shot:"),
		"one-shot reward suffix must still render alongside rare-marker logic")


# ── Tick 250 threshold consistency ────────────────────────────────

func test_threshold_matches_rare_drop_event_flag() -> void:
	# The bestiary's "rare" threshold MUST match BattleManager's
	# rare_drop_found event flag threshold (< 0.10 base chance).
	# If they diverge, the player would see ★ in the bestiary but
	# the chat never unlocks (or vice versa) — confusing.
	var bm_content: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	# BattleManager line should still reference < 0.10
	assert_true(bm_content.contains("drop.get(\"chance\", 0.0) < 0.10"),
		"BattleManager rare-drop threshold must still be < 0.10 — bestiary's ★ threshold matches this")
