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


## Runtime probe: ack ON but is_night API not landed (has_method false)
## → still no child. Mirrors PR #151's forward-compat guarantee.
func test_no_night_tint_added_when_is_night_api_missing() -> void:
	var interior := BaseInteriorScript.new()
	add_child_autofree(interior)
	await get_tree().process_frame

	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	# Only run this probe when the API hasn't landed yet — once cowir-main
	# ships is_night(), a different runtime probe would take its place.
	if gs.has_method("is_night"):
		gut.p("is_night() present — skipping forward-compat probe")
		return
	var prior = gs.game_constants.get("day_night_interior_lighting", null)
	gs.game_constants["day_night_interior_lighting"] = true
	interior._maybe_apply_night_modulation()
	assert_null(interior.get_node_or_null("NightTint"),
		"has_method-guard keeps this a no-op until is_night() lands")
	if prior == null:
		gs.game_constants.erase("day_night_interior_lighting")
	else:
		gs.game_constants["day_night_interior_lighting"] = prior
