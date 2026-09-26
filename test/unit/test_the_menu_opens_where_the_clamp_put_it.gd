extends GutTest

## The bottom party slot (the Bard, in the default party) opened its command menu cut off at the
## bottom of the screen. BattleCommandMenu anchors the root menu at `viewport.y - 180`, which
## assumes a menu no taller than 180px. Win98Menu._build_menu corrects overflow with
## _clamp_to_screen, but only AFTER `await process_frame`. By then _animate_menu_open has already
## recorded the unclamped position as its rest point and tweens back to it for 0.12s, overwriting
## the clamp. So the menu came to rest past the bottom edge.
##
## These arms read the position at the moment setup() returns, because that is what the open
## animation records as the rest point.

const WIN98 := preload("res://src/ui/Win98Menu.gd")


func _rows(n: int) -> Array:
	var out: Array = []
	for i in range(n):
		out.append({"id": "row_%d" % i, "label": "Row %d" % i})
	return out


func _open_at_bottom(rows: int) -> Control:
	var menu = WIN98.new()
	menu.is_root_menu = true
	menu.battle_mode = true
	add_child_autofree(menu)
	var vp: Vector2 = menu.get_viewport_rect().size
	## Same anchor BattleCommandMenu computes for a PC low on the screen.
	menu.setup("Bard", _rows(rows), Vector2(vp.x * 0.42, vp.y - 180), "bard")
	return menu


func test_a_tall_menu_needs_the_clamp_at_all() -> void:
	var menu := _open_at_bottom(8)
	var vp: Vector2 = menu.get_viewport_rect().size
	assert_gt(menu.size.y, 180.0,
		"CONTROL: an 8-row root menu must be taller than the 180px the anchor budgets for, or "
		+ "the arm below cannot overflow and passes whatever setup() does (size %s, viewport %s)"
		% [str(menu.size), str(vp)])


func test_the_rest_point_the_animation_records_is_on_screen() -> void:
	var menu := _open_at_bottom(8)
	var vp: Vector2 = menu.get_viewport_rect().size
	assert_lte(menu.position.y + menu.size.y, vp.y,
		("when setup() returns, the menu's position is what _animate_menu_open tweens back to. "
		+ "Bottom edge %.0f against a %.0f viewport means the open animation rests the menu off "
		+ "screen and undoes the deferred clamp") % [menu.position.y + menu.size.y, vp.y])


## No arm drives the tween itself. Headless, the first frame's delta exceeds the 0.12s open tween,
## so the tween finishes before the deferred clamp and the clamp wins. That arm passed on the broken
## code. In play, 16ms frames let the tween win. The rest-point arm above is timing-independent.
