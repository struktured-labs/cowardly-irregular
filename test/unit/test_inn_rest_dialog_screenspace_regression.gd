extends GutTest

## Regression test for the 2026-07-25 playtest report:
## "rest at inn still busted. it spawns a menu out of sight to right of the inn
##  and I cant even force it to accept."
##
## Bug: _make_inn_dialog built a plain Control and parented it to InnInterior,
## which `extends Node2D`. A Control's `position` under a Node2D parent is a
## WORLD coordinate, so the 2026-07-15 "center it on screen" fix —
## `Vector2((vp.x - size.x) / 2, vp.y * 0.35)` — placed the panel at world
## (~520, 252) instead of screen-center. In a small interior with a
## player-following camera that lands off-screen, exactly as reported.
##
## Note the shape: the earlier fix READ the viewport correctly and computed the
## right numbers. It was the coordinate SPACE that was wrong, so the code looked
## like a screen-centering fix and tested like one, while rendering in world
## space. Only a CanvasLayer makes Control coordinates mean screen coordinates.
##
## Second bug, same report ("I cant even force it to accept"): the prompt reads
## "[Talk again to confirm — step away to cancel]" but nothing ever cleared
## _rest_pending except a completed rest. Walking away left the request armed,
## so the next interact slept immediately instead of re-prompting.

const INN_PATH := "res://src/maps/interiors/InnInterior.gd"

var _inn: Node2D


func before_each() -> void:
	# Built but deliberately NOT added to the tree: _ready() generates the whole
	# procedural interior, and _make_inn_dialog needs none of it.
	_inn = load(INN_PATH).new()


func after_each() -> void:
	if is_instance_valid(_inn):
		_inn.free()


func test_rest_dialog_is_a_canvaslayer_not_a_worldspace_control() -> void:
	var dlg = _inn._make_inn_dialog("Rest at the inn?")
	assert_not_null(dlg, "_make_inn_dialog must return the dialog it created")
	assert_true(
		dlg is CanvasLayer,
		"the rest dialog MUST be a CanvasLayer — a Control parented to this Node2D "
		+ "interprets its position as a world coordinate and the camera leaves it behind"
	)


func test_rest_dialog_is_parented_into_the_canvaslayer() -> void:
	var dlg = _inn._make_inn_dialog("Rest at the inn?")
	# Every visual must live UNDER the layer; anything parented to the Node2D
	# directly is back in world space and reintroduces the bug.
	assert_gt(dlg.get_child_count(), 0, "dialog layer must contain its panel")
	var found_label := _find_label(dlg)
	assert_not_null(found_label, "dialog must contain a Label with the prompt text")
	assert_true(
		found_label.text.contains("Rest at the inn?"),
		"the prompt text must survive into the rendered label"
	)


func test_dialog_carries_no_worldspace_position_offsets() -> void:
	# A CanvasLayer at a non-zero offset would re-introduce a world-ish shift.
	var dlg = _inn._make_inn_dialog("Rest at the inn?")
	assert_eq(dlg.offset, Vector2.ZERO, "dialog layer must not be offset from the screen origin")


func test_rest_zone_exit_clears_the_pending_request() -> void:
	# "step away to cancel" is advertised in the prompt — it must actually work.
	_inn._rest_pending = true
	var player := CharacterBody2D.new()
	player.add_to_group("player")
	_inn._on_rest_zone_exited(player)
	assert_false(
		_inn._rest_pending,
		"leaving the rest zone must disarm the pending rest, or the next interact "
		+ "sleeps immediately instead of prompting"
	)
	player.free()


func test_rest_zone_exit_ignores_non_player_bodies() -> void:
	_inn._rest_pending = true
	var npc := CharacterBody2D.new()  # no "player" group, no set_can_move
	_inn._on_rest_zone_exited(npc)
	assert_true(
		_inn._rest_pending,
		"a wandering NPC crossing the rest zone must not cancel the player's prompt"
	)
	npc.free()


func test_source_no_longer_centers_via_raw_viewport_position() -> void:
	# Guards the specific dead pattern so it cannot be reintroduced by a revert.
	var src := FileAccess.get_file_as_string(INN_PATH)
	assert_false(
		src.contains("holder.position = Vector2((_vp.x"),
		"the world-space centering line must stay gone — it computes correct numbers "
		+ "in the wrong coordinate space, which is why it read as a working fix"
	)


func _find_label(n: Node) -> Label:
	if n is Label:
		return n as Label
	for c in n.get_children():
		var found := _find_label(c)
		if found != null:
			return found
	return null
