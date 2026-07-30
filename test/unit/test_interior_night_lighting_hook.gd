extends GutTest

## Interior night-lighting hook (struktured directive msg 2643).
## Companion to the overworld encounter multiplier (PR #151) — same
## ack-gated forward-compat shape. BaseInterior._maybe_apply_night_modulation
## reads GameState.game_constants["day_night_interior_lighting"] and
## GameState.is_night(); when both are truthy, adds a subtle cool
## CanvasModulate child. Ships as a live no-op until struktured flips
## the toggle AND cowir-main's canonical is_night() API lands.

const BaseInteriorScript := preload("res://src/maps/interiors/BaseInterior.gd")


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_helper_called_from_ready() -> void:
	# The hook must fire after all the concrete setup runs so the
	# CanvasModulate is a sibling of any subclass ambient tint, not a
	# child that would be missed by scene walks.
	var src := _read("res://src/maps/interiors/BaseInterior.gd")
	assert_true(src.contains("_maybe_apply_night_modulation()"),
		"BaseInterior._ready must call the night-modulation hook")


func test_ack_gate_defaults_off_so_ship_is_no_op() -> void:
	var src := _read("res://src/maps/interiors/BaseInterior.gd")
	assert_true(src.contains("game_constants.get(\"day_night_interior_lighting\", false)"),
		"reads the ack toggle with default=false so the ship is a no-op")


func test_forward_compat_with_pending_is_night_api() -> void:
	# has_method guard means my code is inert until cowir-main lands
	# the canonical GameState.is_night() surface (msg 2659).
	var src := _read("res://src/maps/interiors/BaseInterior.gd")
	assert_true(src.contains("has_method(\"is_night\")"),
		"night check is has_method-guarded (forward-compat)")


func test_suggested_night_tint_flagged_ack_pending() -> void:
	var src := _read("res://src/maps/interiors/BaseInterior.gd")
	assert_true(src.contains("NIGHT_INTERIOR_TINT"),
		"tint declared as a named constant so it's flip-editable")
	assert_true(src.contains("struktured-ack-pending") or src.contains("struktured's ruling"),
		"suggested-defaults comment names the ack requirement")


## Runtime probe: with the ack gate off, an interior instance must NOT
## grow a NightTint child (belt-and-suspenders over the source-level
## pins).
func test_no_night_tint_added_when_ack_off() -> void:
	var interior := BaseInteriorScript.new()
	add_child_autofree(interior)
	await get_tree().process_frame

	var gs := get_node_or_null("/root/GameState")
	assert_not_null(gs, "GameState autoload present")
	if gs == null:
		return
	var prior = gs.game_constants.get("day_night_interior_lighting", null)
	gs.game_constants["day_night_interior_lighting"] = false
	interior._maybe_apply_night_modulation()
	assert_null(interior.get_node_or_null("NightTint"),
		"ack off → no NightTint child created")
	# Restore
	if prior == null:
		gs.game_constants.erase("day_night_interior_lighting")
	else:
		gs.game_constants["day_night_interior_lighting"] = prior


## The forward-compat probe that lived here waited for GameState.is_night() and
## skipped itself once it landed — scoring [Risky] (asserted nothing) in every run
## since. is_night() IS on main (GameState.gd), so it was permanently dead, and its
## own comment said a real runtime probe should take its place. This is that probe.
##
## Drives GameState.day_phase, which is what get_time_of_day_name() reads, so it
## exercises the real branch rather than pinning source text. The three tests above
## are source pins and cannot see an operator change; these can.
##
## day_phase and the ack toggle are GLOBAL autoload state and GUT is one process —
## both are saved and restored unconditionally.
func _with_night_state(ack: bool, phase: float, body: Callable) -> void:
	var gs := get_node_or_null("/root/GameState")
	assert_not_null(gs, "GameState autoload present")
	if gs == null:
		return
	var prior_ack = gs.game_constants.get("day_night_interior_lighting", null)
	var prior_phase: float = gs.day_phase
	gs.game_constants["day_night_interior_lighting"] = ack
	gs.day_phase = phase
	body.call(gs)
	gs.day_phase = prior_phase
	if prior_ack == null:
		gs.game_constants.erase("day_night_interior_lighting")
	else:
		gs.game_constants["day_night_interior_lighting"] = prior_ack


func test_night_tint_appears_when_ack_on_and_it_is_night() -> void:
	var interior := BaseInteriorScript.new()
	add_child_autofree(interior)
	await get_tree().process_frame
	_with_night_state(true, 0.8, func(gs):
		assert_true(gs.is_night(), "phase 0.8 must read as night, else this proves nothing")
		interior._maybe_apply_night_modulation()
		assert_not_null(interior.get_node_or_null("NightTint"),
			"ack on + night must add the tint — this is the branch nothing covered"))


func test_no_night_tint_during_the_day_even_with_ack_on() -> void:
	var interior := BaseInteriorScript.new()
	add_child_autofree(interior)
	await get_tree().process_frame
	_with_night_state(true, 0.3, func(gs):
		assert_false(gs.is_night(), "phase 0.3 must read as day, else the negative case is vacuous")
		interior._maybe_apply_night_modulation()
		assert_null(interior.get_node_or_null("NightTint"),
			"daytime must not tint, or interiors go dim at noon"))


func test_ack_gate_still_wins_at_night() -> void:
	var interior := BaseInteriorScript.new()
	add_child_autofree(interior)
	await get_tree().process_frame
	_with_night_state(false, 0.8, func(gs):
		assert_true(gs.is_night(), "must actually be night for this to test the ack gate")
		interior._maybe_apply_night_modulation()
		assert_null(interior.get_node_or_null("NightTint"),
			"the ack gate must still suppress the tint at night — the feature has no "
			+ "enabling path in game yet (nothing writes day_night_interior_lighting), "
			+ "so shipping is a no-op BY DESIGN until struktured flips it"))
