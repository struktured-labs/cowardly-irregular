extends GutTest

## struktured via main 23419-23421: menus covered the monster he was targeting, the Ability list covered the command
## menu's own rows ("uto: this turn"), and the tooltip ran under its parent. BattleMenuPlacer is the one solver that
## places them: these arms drive it with rects, the shape of his .788 screen at 1280x720.

const VP := Vector2(1280, 720)
const ENEMIES := {"id": "ENEMIES", "rect": Rect2(226, 60, 200, 220)}
const LOG := {"id": "LOG", "rect": Rect2(226, 290, 200, 190)}
const TURNS := {"id": "TURN ORDER", "rect": Rect2(226, 490, 200, 180)}
const PARTY := {"id": "PARTY", "rect": Rect2(1300, 40, 196, 660)}
const HINT := {"id": "hint bar", "rect": Rect2(560, 686, 600, 28)}
const ACTOR := Rect2(860, 290, 90, 150)


func _hud() -> Array:
	return [ENEMIES, LOG, TURNS, {"id": "PARTY", "rect": Rect2(1100, 40, 180, 660)}, HINT]


func _slime() -> Dictionary:
	return {"id": "Slime", "rect": Rect2(820, 450, 160, 170)}


func test_a_sparse_battle_never_covers_the_target() -> void:
	var req := {"kind": "root", "size": Vector2(240, 300), "vp": VP, "actor": ACTOR, "target": _slime(), "hud": _hud()}
	var got := BattleMenuPlacer.solve(req)
	assert_eq(int(got["relaxed"]), 0, "CONTROL: a sparse screen has a clear slot (%s)" % got["why"])
	var r: Rect2 = got["rect"]
	assert_false(r.intersects(_slime()["rect"]), "the menu must not cover the monster under the cursor: %s" % str(r))
	for h in _hud():
		assert_false(r.intersects(h["rect"]), "nor a HUD panel (%s)" % h["id"])
	assert_string_contains(got["why"], "Slime clear", "and it says why")


func test_a_list_never_covers_its_parents_rows() -> void:
	var parent := Rect2(610, 300, 240, 260)
	var req := {"kind": "submenu", "size": Vector2(210, 190), "vp": VP, "actor": ACTOR, "parent": parent,
		"ancestors": [parent], "hud": _hud()}
	var got := BattleMenuPlacer.solve(req)
	assert_false((got["rect"] as Rect2).intersects(parent), "his 'uto: this turn': the Ability list sat on the command menu (%s)" % got["why"])


func test_the_tooltip_stays_flush_with_its_menu() -> void:
	var menu := Rect2(430, 240, 210, 190)
	var got := BattleMenuPlacer.solve({"kind": "tooltip", "size": Vector2(200, 24), "vp": VP, "parent": menu,
		"ancestors": [Rect2(610, 300, 240, 260)], "hud": _hud()})
	assert_true((got["rect"] as Rect2).grow(BattleMenuPlacer.FLUSH).intersects(menu), "a tooltip never detaches from its menu (%s)" % got["why"])
	assert_false((got["rect"] as Rect2).intersects(Rect2(610, 300, 240, 260)), "nor runs under the parent menu")


func test_the_zoom_chip_sits_inside_its_list() -> void:
	var list := Rect2(430, 240, 210, 190)
	var got := BattleMenuPlacer.solve({"kind": "chip", "size": Vector2(70, 18), "vp": VP, "parent": list})
	assert_true(list.encloses(got["rect"]), "the chip is inside the list, not on its border (%s)" % str(got["rect"]))


func test_a_packed_screen_takes_the_least_cover_and_says_so() -> void:
	var wall := {"id": "wall", "rect": Rect2(0, 0, 1280, 720)}
	var hole := Rect2(500, 200, 400, 400)
	var hud: Array = [{"id": "top", "rect": Rect2(0, 0, 1280, hole.position.y)}, {"id": "bottom", "rect": Rect2(0, hole.end.y, 1280, 720 - hole.end.y)},
		{"id": "left", "rect": Rect2(0, hole.position.y, hole.position.x, hole.size.y)}, {"id": "right", "rect": Rect2(hole.end.x, hole.position.y, 1280 - hole.end.x, hole.size.y)}]
	var target := {"id": "Goblin", "rect": Rect2(560, 260, 280, 280)}
	var got := BattleMenuPlacer.solve({"kind": "root", "size": Vector2(240, 300), "vp": VP, "actor": Rect2(640, 400, 10, 10), "target": target, "hud": hud})
	assert_eq(int(got["relaxed"]), 2, "CONTROL: nothing clears the target, so covering it is allowed (%s)" % got["why"])
	assert_string_contains(got["why"], "packed", "and the why line says it was forced")
	var full := Rect2(560, 260, 240, 300).intersection(target["rect"])
	assert_lt(_area(got["rect"], target["rect"]), full.size.x * full.size.y, "it covers less of the target than sitting dead on it would")
	assert_true(hole.encloses(got["rect"]), "and still stays off every panel")
	assert_true(wall["rect"].encloses(got["rect"]), "and on screen")


func test_a_cursor_sweep_does_not_hop() -> void:
	var foes: Array = [{"id": "A", "rect": Rect2(560, 120, 120, 120)}, {"id": "B", "rect": Rect2(600, 300, 120, 120)}, {"id": "C", "rect": Rect2(560, 480, 120, 120)}]
	var last := Rect2()
	var hops := 0
	for f in foes:
		var got := BattleMenuPlacer.solve({"kind": "submenu", "size": Vector2(210, 150), "vp": VP, "actor": ACTOR,
			"parent": Rect2(900, 300, 180, 200), "ancestors": [Rect2(900, 300, 180, 200)], "target": f, "target_list": foes, "hud": _hud(), "last": last})
		if last.has_area() and got["rect"] != last:
			hops += 1
		last = got["rect"]
	assert_lte(hops, 1, "moving the cursor over three foes must not move the list on every step (hopped %d)" % hops)


func _area(a: Rect2, b: Rect2) -> float:
	var i := a.intersection(b)
	return i.size.x * i.size.y if i.size.x > 0.0 and i.size.y > 0.0 else 0.0
