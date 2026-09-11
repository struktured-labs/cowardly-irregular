extends GutTest

## 29 keeper names are authored across 11 villages. NONE of them reached the room the keeper
## stands in, and neither did a single shop's name.
##
## Found 2026-09-11. `VillageShop` carries `shop_name` / `keeper_name` — "Suburban Mart", "Donna" —
## but interacting with it emits a transition to a map id SHARED by every item shop in the game
## (`shop_interior_item`). GameLoop rebuilt that interior from the shop TYPE alone, so the player
## walked out of a suburban cul-de-sac and into "Mystic Remedies", greeted by "Shopkeeper".
## In Maple Heights. In Node Prime. In Rivet Row. All 29 of them.
##
## 🔑 THE AUTHORED VOICE WAS ALREADY THERE AND ALREADY CORRECT — `data/shopkeeper_dialogue.json`
## holds per-village prose for all 11, keyed off `get_village_origin_id()`, and it renders. So the
## defect was never "nobody wrote it": Donna says the suburban lines, under a medieval sign, with
## someone else's name on her. The two halves of one character arrived by different routes and only
## one route existed. GameLoop:5174 said so out loud — "outdoor shop instances can pass their own
## via a future override hook, but for now generic names work everywhere."
##
## The fix crosses the door: VillageShop hands its identity to GameLoop immediately before asking
## for the interior, and the factory CONSUMES it. Consume, not read — so arriving any other way
## (teleport, save load, the render smoke) still gets the generic name rather than the last shop
## the player happened to visit, which is the staleness a plain field would have introduced.

const GameLoopScript := preload("res://src/GameLoop.gd")
const ShopInteriorScript := preload("res://src/maps/interiors/ShopInterior.gd")
const VillageShopScript := preload("res://src/exploration/VillageShop.gd")
const MapScripts := preload("res://test/unit/helpers/map_scripts.gd")

const VILLAGE_DIR := "res://src/maps/villages"

var _fake_gl: Node = null


## free() immediately, not queue_free(): a deferred free leaves a second /root/GameLoop in the tree
## and the next test's get_node_or_null picks the stale one.
func after_each() -> void:
	if _fake_gl and is_instance_valid(_fake_gl):
		_fake_gl.free()
	_fake_gl = null


## GameLoop is the main scene, not an autoload, so it is absent under test. Never added to the
## tree here — _ready would build the whole game — and _create_shop_interior needs neither.
func _loose_gameloop() -> Node:
	var gl = GameLoopScript.new()
	autofree(gl)
	return gl


func test_the_interior_becomes_the_shop_the_player_walked_up_to() -> void:
	var gl := _loose_gameloop()
	gl.set_pending_shop_identity("Suburban Mart", "Donna")
	var scene = gl._create_shop_interior(0)
	autofree(scene)

	assert_eq(scene.shop_name, "Suburban Mart", "the sign still reads a name nobody authored")
	assert_eq(scene.keeper_name, "Donna", "the keeper still has no name of her own")
	assert_eq(scene.shop_type, 0, "CONTROL: the type must still decide the room's theme")


## The half that makes it a hand-off rather than a global: the identity is spent on arrival.
func test_a_shop_entered_any_other_way_does_not_inherit_the_last_one() -> void:
	var gl := _loose_gameloop()
	gl.set_pending_shop_identity("Suburban Mart", "Donna")
	var walked_in = gl._create_shop_interior(0)
	autofree(walked_in)
	assert_eq(walked_in.shop_name, "Suburban Mart", "CONTROL: the hand-off must have landed first")

	# No door this time — a teleport, a save load, the deploy render smoke.
	var arrived = gl._create_shop_interior(0)
	autofree(arrived)
	assert_eq(arrived.shop_name, "Mystic Remedies",
		"the generic fallback is gone, so a teleport now shows whichever shop was last entered")
	assert_eq(arrived.keeper_name, "Shopkeeper",
		"the keeper name persisted past its one use — Donna is now standing in every shop")


func test_every_shop_type_still_has_a_name_when_nobody_walked_through_a_door() -> void:
	var gl := _loose_gameloop()
	var blanks: Array = []
	for t in range(4):
		var scene = gl._create_shop_interior(t)
		autofree(scene)
		if str(scene.shop_name).is_empty() or str(scene.shop_name) == "Shop":
			blanks.append(t)
	assert_eq(blanks, [], "shop types left with no fallback name: %s" % str(blanks))


## The export being set is not the same as the player seeing it: one is a field, one is a Label and
## an NPC. This builds the real room and reads both back.
func test_the_name_reaches_the_sign_and_the_keeper_reaches_the_counter() -> void:
	var interior = ShopInteriorScript.new()
	interior.shop_type = 0
	interior.shop_name = "Suburban Mart"
	interior.keeper_name = "Donna"
	add_child_autofree(interior)
	await get_tree().process_frame
	await get_tree().process_frame

	var sign_texts: Array = []
	_labels(interior, sign_texts)
	assert_true("Suburban Mart" in sign_texts,
		"the sign over the counter does not carry the shop's name; labels found: %s" % str(sign_texts))

	var keeper_names: Array = []
	_npc_names(interior, keeper_names)
	assert_true("Donna" in keeper_names,
		"no NPC in the room answers to the authored keeper; NPCs found: %s" % str(keeper_names))
	assert_gt(keeper_names.size(), 1,
		"CONTROL: the room builds customers too — a single name means the walk found only the keeper by luck")


func _labels(n: Node, acc: Array) -> void:
	for c in n.get_children():
		if c is Label:
			acc.append(str((c as Label).text))
		_labels(c, acc)


func _npc_names(n: Node, acc: Array) -> void:
	for c in n.get_children():
		var who = c.get("npc_name")
		if who != null and str(who) != "":
			acc.append(str(who))
		_npc_names(c, acc)


## Now that the room takes its identity from the shop, an unnamed shop is a visible regression
## rather than a harmless default. This walks the real villages for shops that would hand over
## nothing.
##
## ⚠️ COLD BUILD: a shop created behind a story flag is not in this population, so the counts are
## LOWER BOUNDS and the controls below name members instead of trusting a total.
func test_no_village_hands_the_door_an_unnamed_shop() -> void:
	var anonymous: Array = []
	var shops_seen := 0
	var names_seen: Array = []
	var villages_built := 0

	for path in MapScripts.maps_in(VILLAGE_DIR):
		var vp := SubViewport.new()
		vp.size = Vector2i(64, 64)
		vp.world_2d = World2D.new()
		add_child_autofree(vp)
		var village = load(path).new()
		vp.add_child(village)
		await get_tree().physics_frame
		await get_tree().process_frame
		villages_built += 1

		var shops: Array = []
		_shops(village, shops)
		for shop in shops:
			shops_seen += 1
			names_seen.append(str(shop.shop_name))
			var keeper := str(shop.keeper_name)
			var shop_name := str(shop.shop_name)
			if keeper.is_empty() or keeper == "Shopkeeper" or shop_name.is_empty() or shop_name == "Shop":
				anonymous.append("%s: '%s' kept by '%s'" % [path.get_file(), shop_name, keeper])

	assert_gt(villages_built, 8, "CONTROL: only %d villages built — the sweep is broken" % villages_built)
	assert_true("Suburban Mart" in names_seen,
		"CONTROL: the walk never reached Maple Heights' item shop, so the zero below is free")
	assert_gt(shops_seen, 20, "CONTROL: only %d shops found across the villages" % shops_seen)
	assert_eq(anonymous, [],
		("shops that hand the interior nothing, so the player meets 'Shopkeeper' in a generic room: %s\n" +
		"Name it on the VillageShop — that is the only place the name is authored.") % str(anonymous))


func _shops(n: Node, acc: Array) -> void:
	for c in n.get_children():
		if c.get_script() == VillageShopScript:
			acc.append(c)
		_shops(c, acc)


## The producer half. VillageShop reaches GameLoop by node path, so a rename of the main scene's
## root node silently reverts this whole fix — this test is what notices.
func test_walking_up_to_a_shop_hands_its_identity_over_before_the_transition() -> void:
	var gs := GDScript.new()
	gs.source_code = """extends Node
var got_shop: String = ""
var got_keeper: String = ""
func set_pending_shop_identity(shop: String, keeper: String) -> void:
	got_shop = shop
	got_keeper = keeper
"""
	gs.reload()
	_fake_gl = Node.new()
	_fake_gl.set_script(gs)
	_fake_gl.name = "GameLoop"
	get_tree().root.add_child(_fake_gl)

	var shop = VillageShopScript.new()
	shop.shop_name = "Suburban Mart"
	shop.keeper_name = "Donna"
	shop.use_interior = true
	add_child_autofree(shop)
	await get_tree().process_frame

	var asked: Array = []
	shop.transition_triggered.connect(func(map_id, _spawn): asked.append(str(map_id)))
	shop.interact(null)

	assert_eq(asked, ["shop_interior_item"], "CONTROL: the interact must still ask for the interior")
	assert_eq(_fake_gl.got_shop, "Suburban Mart", "the shop's name never left the village")
	assert_eq(_fake_gl.got_keeper, "Donna", "the keeper's name never left the village")


## Carrying the real name to the sign only helps if the sign can hold it. The label was anchored AT
## the board's centre-line and drawn left-to-right, so every sign in the game overran its right edge
## — "Mystic Remedies" by 25px, and it is the SHORTEST name the room ever held.
##
## ⚠️ THE SHRINK IS NOT WHAT FIXES THAT, AND THIS TEST SAYS SO. Measured across all 29 authored
## names at font 11: the widest, "Boilerman's Apothecary", is 127px of 128. Nothing shrinks today,
## so stubbing fit_font_size to a constant leaves the sweep below GREEN — which is correct, and is
## why the direct assert on the function is here too. The sweep defends the constraint; the assert
## defends the mechanism that will be needed by the 23rd character somebody authors.
## Measured with the font the Label actually resolves, not with an assumed pixels-per-character.
func test_every_authored_shop_name_fits_on_its_own_sign() -> void:
	var interior = ShopInteriorScript.new()
	interior.shop_type = 0
	interior.shop_name = "Mystic Remedies"
	add_child_autofree(interior)
	await get_tree().process_frame

	var sign_label: Label = _find_label(interior, "Mystic Remedies")
	assert_not_null(sign_label, "CONTROL: no sign label to measure — the rest of this test is free")
	if sign_label == null:
		return
	var font: Font = sign_label.get_theme_font("font")
	assert_not_null(font, "CONTROL: the label resolved no font, so every width below would be zero")
	if font == null:
		return
	## Measured against the BOARD SPRITE, not against arithmetic on TILE_SIZE: the board is a
	## Sprite2D and Sprite2D is centred by default, so a future `centered = false` would move the
	## wood out from under a label that still passes every constant-based assert.
	var board: Sprite2D = _find_sign_board(interior)
	assert_not_null(board, "CONTROL: no sign board found, so there is nothing to be centred on")
	if board == null:
		return
	var board_px: float = float(board.texture.get_width())
	var board_left: float = board.position.x - (board_px / 2.0 if board.centered else 0.0)
	assert_eq(sign_label.size.x, board_px, "the label no longer spans its board, so centring is a lie")
	assert_almost_eq(sign_label.position.x, board_left, 0.5,
		"the name's box does not start where the wood starts")
	assert_almost_eq(sign_label.position.x + sign_label.size.x, board_left + board_px, 0.5,
		"the name's box does not end where the wood ends")
	assert_eq(sign_label.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER,
		"the name is drawn from the board's centre-line rightwards again, not centred on it")

	var overruns: Array = []
	var names := await _authored_shop_names()
	assert_gt(names.size(), 20, "CONTROL: only %d shop names collected" % names.size())
	for name in names:
		var w: float = font.get_string_size(
			name, HORIZONTAL_ALIGNMENT_CENTER, -1,
			ShopInteriorScript.fit_font_size(name, font, board_px)).x
		if w > board_px:
			overruns.append("%s (%.0fpx of %.0f)" % [name, w, board_px])
	assert_eq(overruns, [], "shop names that run off their own sign board: %s" % str(overruns))

	## The same measurement must be able to say NO, or the empty list above proves nothing.
	var absurd := "The Exceedingly Long Name Of A Shop Nobody Would Author"
	var absurd_w: float = font.get_string_size(
		absurd, HORIZONTAL_ALIGNMENT_CENTER, -1,
		ShopInteriorScript.fit_font_size(absurd, font, board_px)).x
	assert_gt(absurd_w, board_px, "CONTROL: the width check cannot report an overrun at all")

	## The shrink itself, on a name no authored one reaches: nothing above exercises it.
	var long_name := "Boilerman's Apothecary and Sundries"
	var chosen: int = ShopInteriorScript.fit_font_size(long_name, font, board_px)
	assert_lt(chosen, ShopInteriorScript.SIGN_FONT_MAX,
		"a name too wide at full size was not shrunk at all")
	assert_lte(font.get_string_size(long_name, HORIZONTAL_ALIGNMENT_CENTER, -1, chosen).x, board_px,
		"the size it shrank to still does not fit the board")
	assert_gt(font.get_string_size(long_name, HORIZONTAL_ALIGNMENT_CENTER, -1,
		ShopInteriorScript.SIGN_FONT_MAX).x, board_px,
		"CONTROL: this name already fits at full size, so the shrink assert above is free")


## The hanging board: the only sign-shaped sprite in the room, 4 tiles by 1.
func _find_sign_board(n: Node) -> Sprite2D:
	for c in n.get_children():
		if c is Sprite2D:
			var tex: Texture2D = (c as Sprite2D).texture
			if tex != null and tex.get_width() == 4 * ShopInteriorScript.TILE_SIZE \
					and tex.get_height() == ShopInteriorScript.TILE_SIZE:
				return c
		var deeper: Sprite2D = _find_sign_board(c)
		if deeper != null:
			return deeper
	return null


func _find_label(n: Node, text: String) -> Label:
	for c in n.get_children():
		if c is Label and str((c as Label).text) == text:
			return c
		var deeper: Label = _find_label(c, text)
		if deeper != null:
			return deeper
	return null


## Every shop name a cold build of the villages produces. Same population as the sweep below.
func _authored_shop_names() -> Array:
	var names: Array = []
	for path in MapScripts.maps_in(VILLAGE_DIR):
		var vp := SubViewport.new()
		vp.size = Vector2i(64, 64)
		vp.world_2d = World2D.new()
		add_child_autofree(vp)
		var village = load(path).new()
		vp.add_child(village)
		await get_tree().physics_frame
		await get_tree().process_frame
		var shops: Array = []
		_shops(village, shops)
		for shop in shops:
			names.append(str(shop.shop_name))
	return names
