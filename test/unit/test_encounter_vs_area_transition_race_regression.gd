extends GutTest

## Playtest 2026-07-14: struktured — "I got it to freeze from being attacked
## while entering a village? Some sort of race condition." Root cause:
## OverworldPlayer.moved fires INSIDE _physics_process (from move_and_slide),
## so `_check_encounter → battle_triggered` can emit on the same physics
## frame that AreaTransition.body_entered later fires `transition_triggered`.
## Both scene changes race through GameLoop; whichever loses the interleave
## strands the player mid-load.
##
## Fix: mutual-exclusion mutex between GameLoop._on_area_transition and
## GameLoop._on_exploration_battle_triggered. Whichever handler runs first
## wins; the other bails at its top guard with a diagnostic warning.


func test_battle_handler_bails_when_area_transition_in_flight() -> void:
	# The pre-existing area-transition guard was one-sided (protected against
	# reentrant area transitions only). Add a check on the battle-trigger side.
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var i := src.find("func _on_exploration_battle_triggered")
	assert_gt(i, -1)
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 2000)
	assert_true("_transition_in_progress" in body,
		"_on_exploration_battle_triggered must consult _transition_in_progress — otherwise an encounter fires atop an in-flight area load")
	assert_true("BLOCKED — area transition in flight" in body,
		"the drop must be diagnosable in logs — silent-suppression makes future races invisible")


func test_area_transition_bails_when_battle_transition_starting() -> void:
	# Reciprocal guard — battle transition's async fade-out window is exactly
	# when a stray AreaTransition body_entered would slip through if unguarded.
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var i := src.find("func _on_area_transition")
	assert_gt(i, -1)
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 3000)
	assert_true("_battle_transition_starting" in body,
		"_on_area_transition must consult _battle_transition_starting — reciprocal mutex")
	assert_true("suppressed" in body.to_lower(),
		"the drop must surface in logs — silent-suppression is the anti-pattern this fix removes")


func test_mutex_flag_declared_and_toggled_at_state_boundaries() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true("var _battle_transition_starting: bool = false" in src,
		"mutex flag must exist on GameLoop")
	# Set at battle-trigger entry.
	assert_true("_battle_transition_starting = true" in src,
		"battle-trigger handler must set the mutex before awaiting the transition")
	# Cleared once state=BATTLE takes over ownership.
	var i := src.find("func _start_battle_async")
	assert_gt(i, -1)
	var body := src.substr(i, 400)
	assert_true("_battle_transition_starting = false" in body,
		"_start_battle_async must clear the mutex — state=BATTLE now owns exclusion")
	# Safety pop on return to exploration — leak proof.
	var j := src.find("func _start_exploration")
	assert_gt(j, -1)
	var body2 := src.substr(j, 500)
	assert_true("_battle_transition_starting = false" in body2,
		"_start_exploration must clear the mutex — leak-proof against a mid-transition bail")
