extends GutTest

## The Mode 7 shader warps every pixel drawn in world space, and the exit prompt was drawn there.
##
## FOUND 2026-09-10 on a rendered frame of the W3 back portal: "Return to the Mundane Sprawl" came
## out horizontally squashed and vertically stretched -- "Return" reads as "Recurn" -- in brown on
## brown, because the shader had also fogged and tinted its white text into the terrain. The HUD
## objective arrow sat crisp six pixels below it in the same frame, which is the whole comparison.
##
## The player sprite already dodges this: Mode7Overlay redraws it upright on its own CanvasLayer at
## a fixed screen position. The prompt never got the same treatment, so it is the one piece of text
## in the game that the perspective is allowed to chew.
##
## In Mode 7 the prompt now speaks only for the zone the player is standing in. A floating label
## legible from across the map is not what a warped one was delivering anyway.
##
## Flat maps -- villages, interiors, dungeons -- keep the world-space label they always had, so the
## z-order fix landed the same day still applies there unchanged.

const AreaTransitionScript = preload("res://src/exploration/AreaTransition.gd")
## Mode7Overlay draws warped ground on layer 1 and the upright player on 2; the prompt must clear both.
const PLAYER_OVERLAY_LAYER := 2
## The authored world-space offset flat maps have always used.
const FLAT_OFFSET := Vector2(-40, -72)


func after_each() -> void:
	## Leaking a true here rotates village movement and re-scales every interact zone in the suite.
	Mode7Overlay.is_active = false


func _live_transition() -> AreaTransition:
	var t: AreaTransition = AreaTransitionScript.new()
	t.target_map = "suburban_overworld"
	t.indicator_text = "Return to the Mundane Sprawl"
	add_child_autofree(t)
	await get_tree().process_frame
	await get_tree().process_frame
	return t


func _label_of(t: AreaTransition) -> Label:
	return t.find_child("Indicator", true, false) as Label


func test_a_mode7_prompt_is_drawn_on_a_layer_the_shader_cannot_reach() -> void:
	Mode7Overlay.is_active = true
	var t: AreaTransition = await _live_transition()
	var lbl := _label_of(t)
	assert_not_null(lbl, "CONTROL: the transition must build an Indicator label at all")
	if lbl == null:
		return
	var host = lbl.get_parent()
	assert_true(host is CanvasLayer,
		"the prompt is still parented to world space, where the Mode 7 shader warps it: %s" % [host])
	if host is CanvasLayer:
		assert_gt((host as CanvasLayer).layer, PLAYER_OVERLAY_LAYER,
			"the prompt draws under Mode7Overlay's own player layer")


func test_a_flat_map_keeps_the_world_space_prompt_it_always_had() -> void:
	Mode7Overlay.is_active = false
	var t: AreaTransition = await _live_transition()
	var lbl := _label_of(t)
	assert_not_null(lbl, "CONTROL: the transition must build an Indicator label at all")
	if lbl == null:
		return
	assert_eq(lbl.get_parent(), t, "a flat map moved its prompt off the trigger")
	assert_eq(lbl.position, FLAT_OFFSET, "a flat map moved its prompt off its authored offset")
	assert_true(lbl.visible, "CONTROL: show_gate_visual keeps a flat prompt on screen")


func test_the_mode7_prompt_stays_quiet_until_you_are_standing_in_the_zone() -> void:
	Mode7Overlay.is_active = true
	var t: AreaTransition = await _live_transition()
	var lbl := _label_of(t)
	assert_not_null(lbl, "CONTROL: the transition must build an Indicator label at all")
	if lbl == null:
		return
	assert_true(t.show_gate_visual, "CONTROL: this is the always-on gate label, the case that used to float")
	assert_false(lbl.visible, "a prompt for a portal the player is nowhere near is on screen")


func test_leaving_mode7_puts_the_prompt_back_where_flat_maps_expect_it() -> void:
	Mode7Overlay.is_active = true
	var t: AreaTransition = await _live_transition()
	var lbl := _label_of(t)
	assert_not_null(lbl, "CONTROL: the transition must build an Indicator label at all")
	if lbl == null:
		return
	assert_true(lbl.get_parent() is CanvasLayer, "CONTROL: the prompt must have left world space first")

	Mode7Overlay.is_active = false
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(lbl.get_parent(), t, "the prompt never came back from its screen layer")
	assert_eq(lbl.position, FLAT_OFFSET, "the prompt came back to the wrong offset")
	assert_true(lbl.visible, "the prompt came back invisible")
