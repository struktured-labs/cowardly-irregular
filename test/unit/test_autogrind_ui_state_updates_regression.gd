extends GutTest

## update_stats and set_grinding are called by GameLoop after every grind battle and neither
## was named by a test. update_stats reads each field as `.get(key, current)` — so a stats
## dict missing a key must PRESERVE the running total, not reset it to zero. That contract is
## invisible at the call site and is the whole reason a partial stats payload is survivable.

var _ui


func before_each() -> void:
	_ui = preload("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(_ui)


func test_update_stats_reads_every_field() -> void:
	_ui.update_stats({"battles_won": 12, "efficiency": 3.5, "corruption": 1.25, "total_exp": 900})
	assert_eq(int(_ui._battles_won), 12, "battles_won must be read from the payload")
	assert_almost_eq(float(_ui._efficiency), 3.5, 0.001, "efficiency must be read")
	assert_almost_eq(float(_ui._corruption), 1.25, 0.001, "corruption must be read")
	assert_eq(int(_ui._total_exp), 900, "total_exp must be read")


func test_a_missing_key_preserves_the_running_total() -> void:
	# The `.get(key, current)` contract: a partial payload must not zero the session.
	_ui.update_stats({"battles_won": 12, "efficiency": 3.5, "corruption": 1.25, "total_exp": 900})
	_ui.update_stats({"battles_won": 13})
	assert_eq(int(_ui._battles_won), 13, "the supplied key must still update")
	assert_eq(int(_ui._total_exp), 900,
		"a key absent from the payload must PRESERVE the previous value, not reset it")
	assert_almost_eq(float(_ui._efficiency), 3.5, 0.001, "efficiency must survive a partial payload")


func test_an_empty_payload_changes_nothing() -> void:
	# ARM+ for the sibling: proves preservation is the rule, not an artifact of one key.
	_ui.update_stats({"battles_won": 7, "total_exp": 500})
	_ui.update_stats({})
	assert_eq(int(_ui._battles_won), 7, "an empty payload must leave battles_won alone")
	assert_eq(int(_ui._total_exp), 500, "an empty payload must leave total_exp alone")


func test_set_grinding_tracks_the_flag() -> void:
	_ui.set_grinding(true)
	assert_true(_ui._is_grinding, "set_grinding(true) must arm the grinding flag")


func test_stopping_the_grind_restores_the_config_view() -> void:
	# On stop the player must get the config UI back — otherwise the panel is gone for good.
	_ui.set_grinding(true)
	## visible defaults TRUE on a Control, so asserting it without forcing false first is
	## HOLLOW — it passed with the restore line deleted (mutation, 2026-08-22).
	_ui.visible = false
	_ui.set_grinding(false)
	assert_false(_ui._is_grinding, "set_grinding(false) must clear the flag")
	assert_true(_ui.visible, "stopping a grind must make the config UI visible again")


func test_a_tier_change_tears_down_the_full_screen_monitor() -> void:
	## The monitor is the OLD full-screen view; every tier now renders elsewhere, so a tier
	## change must drop it or it hangs over the dashboard forever.
	var m = AutogrindMonitor.new()
	_ui.add_child(m)
	_ui._monitor = m
	_ui.on_tier_changed(0)
	assert_null(_ui._monitor, "a tier change must release the monitor reference")


func test_the_tier_VALUE_does_not_gate_the_teardown() -> void:
	# ARM+. The function ignores its argument by design; pin that, so a future `if tier == 0`
	# guard has to be a deliberate change rather than a silent one.
	var m = AutogrindMonitor.new()
	_ui.add_child(m)
	_ui._monitor = m
	_ui.on_tier_changed(1)
	assert_null(_ui._monitor, "tier 1 must tear the monitor down exactly as tier 0 does")


func _member(n: String) -> Combatant:
	var c = Combatant.new()
	c.initialize({"name": n, "max_hp": 100, "max_mp": 10,
		"attack": 10, "defense": 10, "magic": 5, "speed": 10})
	add_child_autofree(c)
	return c


func test_party_status_populates_rows_into_the_panel() -> void:
	## First draft of this test asserted `_status_panel is still null` after a no-panel call —
	## HOLLOW, since the function never writes that field. Assert the observable instead.
	var panel := Control.new()
	panel.size = Vector2(300, 200)
	_ui.add_child(panel)
	_ui._status_panel = panel
	_ui._party = [_member("A"), _member("B")]
	_ui.update_party_status()
	assert_gt(panel.get_child_count(), 0,
		"a party of 2 must produce status rows in the panel")


func test_party_rows_are_capped_at_the_strict_five() -> void:
	# The min(_party.size(), 5) cap: a 7-member party must not overflow the panel.
	var panel := Control.new()
	panel.size = Vector2(300, 200)
	_ui.add_child(panel)
	_ui._status_panel = panel
	var seven: Array = []
	for i in range(7):
		seven.append(_member("M%d" % i))
	_ui._party = seven
	_ui.update_party_status()
	assert_lte(panel.get_child_count(), 5,
		"the party display is capped at 5 rows regardless of party size")
