extends GutTest

## Feature 2026-07-04: battle status pips now show remaining turns ("Poison 3")
## for both the party and enemy panels, reading Combatant.status_durations —
## which already existed but was never surfaced to the player. Permanent (-1) or
## absent durations render just the name. Helper: BattleUIManager._status_label.

const UIM := preload("res://src/battle/BattleUIManager.gd")

const DIM := "color=#bbbb77"  # the dimmed turn-count segment marker


func _label(setup: Callable, status: String) -> String:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Subject"
	setup.call(c)
	return UIM.new(null)._status_label(c, status)


func test_finite_duration_shows_turn_count() -> void:
	var label := _label(func(c): c.add_status("poison", 3), "poison")
	assert_string_contains(label, "Poison", "status name must render")
	assert_string_contains(label, "3", "remaining turns must render")
	assert_string_contains(label, DIM, "the turn count must be in the dimmed segment")


func test_permanent_status_shows_no_number() -> void:
	var label := _label(func(c): c.add_status("curse", -1), "curse")
	assert_string_contains(label, "Curse", "permanent status still shows its name")
	assert_false(label.contains(DIM), "permanent (-1) status must not render a turn count")
	assert_false(label.contains("-1"), "the raw -1 sentinel must never leak to the UI")


func test_absent_duration_is_name_only() -> void:
	# In status_effects but with no status_durations entry (defensive path).
	var label := _label(func(c): c.status_effects.append("dazed"), "dazed")
	assert_string_contains(label, "Dazed", "name still renders when duration is absent")
	assert_false(label.contains(DIM), "no dimmed turn segment when duration is unknown")


func test_both_panels_use_the_helper() -> void:
	# Pin that the party AND enemy status blocks route through _status_label,
	# so the two identical blocks can't drift apart again.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleUIManager.gd")
	assert_string_contains(src, "_status_label(member,", "party panel must use the helper")
	assert_string_contains(src, "_status_label(enemy,", "enemy panel must use the helper")
