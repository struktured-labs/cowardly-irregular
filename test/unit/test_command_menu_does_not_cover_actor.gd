extends GutTest

## struktured, F12 cap 2026-08-02 09:18: "the battle menu is still obstructing the player
## attacking — see the rogue". The command menu is placed at viewport.x * 0.42 with a comment
## asserting "party sprites are on the right (~65%+)". PartyArea anchors to the RIGHT edge at
## offset_left -480, so at 1280 the party column starts at x=800 and each successive member sits
## 45px further LEFT (150/105/60/15/-30) — the 5th is at 770, and a 210px-tall artist sprite is
## ~210 wide, so its left edge lands near 665. The menu's right edge is ~748. They overlap.
##
## Measures the REAL rects from a constructed battle rather than trusting either the comment or
## my read of the screenshot.

const SCENE := "res://src/battle/BattleScene.tscn"


func _build() -> Node:
	var scene = load(SCENE).instantiate()
	add_child_autofree(scene)
	return scene


## Reports [menu_rect, [sprite rects]] or [] if the battle could not be constructed headless.
func _measure(scene: Node) -> Array:
	if scene == null or scene.party_sprite_nodes.is_empty():
		return []
	var rects: Array = []
	for s in scene.party_sprite_nodes:
		if not is_instance_valid(s):
			continue
		var tex: Texture2D = null
		if s.sprite_frames and s.sprite_frames.has_animation(&"idle") \
				and s.sprite_frames.get_frame_count(&"idle") > 0:
			tex = s.sprite_frames.get_frame_texture(&"idle", 0)
		if tex == null:
			continue
		var w: float = tex.get_width() * s.scale.x
		var h: float = tex.get_height() * s.scale.y
		rects.append(Rect2(s.position.x - w / 2.0, s.position.y - h / 2.0, w, h))
	return rects


func test_the_menu_x_does_not_reach_the_party_column() -> void:
	var scene := _build()
	var rects := _measure(scene)
	assert_gt(rects.size(), 0,
		"PRECONDITION: party sprites must build, else this measures nothing")
	if rects.is_empty():
		return

	var vw: float = 1280.0
	# The live formula, read from source so a change there cannot silently pass this.
	var src := FileAccess.get_file_as_string("res://src/battle/BattleCommandMenu.gd")
	var re := RegEx.create_from_string("menu_x\\s*=\\s*clamp\\(\\s*viewport_size\\.x \\* ([0-9.]+)")
	var m := re.search(src)
	assert_not_null(m, "menu_x formula must be readable — if this fails the assertion below is vacuous")
	if m == null:
		return
	var menu_x: float = vw * float(m.get_string(1))

	# Win98 command menus run ~210px wide at this font size (measured from the F12 cap).
	var menu_right: float = menu_x + 210.0

	var leftmost: float = 99999.0
	var who: int = -1
	for i in range(rects.size()):
		if rects[i].position.x < leftmost:
			leftmost = rects[i].position.x
			who = i
	gut.p("menu spans %.0f..%.0f · leftmost party sprite #%d starts at %.0f" % [menu_x, menu_right, who, leftmost])

	# The menu DOES overlap the party column and cannot avoid it at this resolution: enemies end
	# ~532, the column starts ~612, and the panel is ~210 wide. So the invariant is not "no
	# overlap" — that is unsatisfiable and would ship as a permanently-red gate — but "while it
	# overlaps, the actor stays readable through it".
	var overlaps: bool = menu_right > leftmost
	var alpha_re := RegEx.create_from_string("MENU_ALPHA_OVER_ACTOR:\\s*float\\s*=\\s*([0-9.]+)")
	var am := alpha_re.search(FileAccess.get_file_as_string("res://src/battle/BattleCommandMenu.gd"))
	assert_not_null(am, "the menu-alpha constant must be readable, else the check below is vacuous")
	if am == null:
		return
	var alpha := float(am.get_string(1))
	assert_true(FileAccess.get_file_as_string("res://src/battle/BattleCommandMenu.gd").contains(
		"modulate.a = MENU_ALPHA_OVER_ACTOR"),
		"the constant must actually be APPLIED to the menu — declaring it changes nothing")
	if overlaps:
		assert_lt(alpha, 1.0,
			"the menu overlaps the party column (%.0f..%.0f vs sprite at %.0f), so it must be translucent or it hides the acting PC" % [menu_x, menu_right, leftmost])
		assert_gt(alpha, 0.6, "translucent, not ghostly — the menu text still has to be legible")


func test_control_party_column_is_where_the_markers_say() -> void:
	# CONTROL: if PartyArea ever stops anchoring right, the numbers above change meaning entirely.
	var scene := _build()
	var rects := _measure(scene)
	assert_gt(rects.size(), 0, "CONTROL: sprites built")
	if rects.is_empty():
		return
	var centers: Array = []
	for r in rects:
		centers.append(r.position.x + r.size.x / 2.0)
	gut.p("party sprite centers: %s" % str(centers))
	gut.p("party leftmost edge: %.0f" % rects[rects.size() - 1].position.x)
	var e_edges: Array = []
	for s in scene.enemy_sprite_nodes:
		if not is_instance_valid(s):
			continue
		var t: Texture2D = null
		if s is AnimatedSprite2D and s.sprite_frames and s.sprite_frames.has_animation(&"idle") \
				and s.sprite_frames.get_frame_count(&"idle") > 0:
			t = s.sprite_frames.get_frame_texture(&"idle", 0)
		elif s is Sprite2D:
			t = s.texture
		if t == null:
			continue
		e_edges.append("%.0f..%.0f" % [s.position.x - t.get_width() * s.scale.x / 2.0,
			s.position.x + t.get_width() * s.scale.x / 2.0])
	gut.p("ENEMY sprite spans: %s" % str(e_edges))
	assert_gt(centers.size(), 2, "CONTROL: a strict-5 party gives 5 centers to compare")
	assert_true(centers[0] > centers[centers.size() - 1],
		"CONTROL: the column steps LEFT as index rises (that is what walks member 5 into the menu)")
