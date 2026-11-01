extends GutTest

## struktured 2026-11-01: "the fountains in the villages look like crap ... any of that old school procgenylooking art needs
## to go". The seam: manifest prop_art "<kind>_<world>" then "<kind>" draws the prop; no entry keeps the painted one.

const VILLAGES := "res://src/maps/villages"
const HARMONIA := "res://src/maps/villages/HarmoniaVillage.gd"
const MAPLE := "res://src/maps/villages/MapleHeightsVillage.gd"
## Any committed PNG serves as a planted drawing; its size is what the arms look for.
const PLANT := "res://assets/sprites/buildings/medieval/harmonia_library.png"
const WORLDS := ["medieval", "suburban", "steampunk", "industrial", "futuristic", "abstract"]


func after_each() -> void:
	VillageProp.prop_art_override = null


func _village(path: String) -> Node:
	var v = load(path).new()
	add_child_autofree(v)
	return v


func _props(v: Node, kind: int) -> Array:
	var out: Array = []
	for c in v.props.get_children():
		if c is VillageProp and c.kind == kind:
			out.append(c)
	return out


func _tex_size(p: Node) -> Vector2i:
	var spr := p.get_node("Sprite") as Sprite2D
	return Vector2i(spr.texture.get_width(), spr.texture.get_height())


func _plant_size() -> Vector2i:
	var t := load(PLANT) as Texture2D
	return Vector2i(t.get_width(), t.get_height())


func test_a_kind_with_art_draws_it_and_one_without_stays_painted() -> void:
	VillageProp.prop_art_override = {"barrel_medieval": {"path": PLANT, "tier": "T1"}}
	var v := _village(HARMONIA)
	var barrels := _props(v, VillageProp.Kind.BARREL)
	var crates := _props(v, VillageProp.Kind.CRATE)
	assert_gt(barrels.size(), 0, "CONTROL: Harmonia places barrels")
	assert_gt(crates.size(), 0, "CONTROL: Harmonia places crates")
	for b in barrels:
		assert_eq(_tex_size(b), _plant_size(), "%s did not draw its art" % b.name)
	for c in crates:
		assert_eq(_tex_size(c), VillageProp.SIZES[VillageProp.Kind.CRATE] * VillageProp.TILE, "%s lost its painted look with no art of its own" % c.name)


func test_a_world_specific_drawing_outranks_the_generic_one() -> void:
	VillageProp.prop_art_override = {"planter": {"path": PLANT}, "planter_suburban": {"path": "res://assets/sprites/buildings/medieval/harmonia_arms.png"}}
	assert_eq(VillageProp.prop_art_path("planter", "medieval"), PLANT, "the generic drawing did not serve a world without its own")
	assert_eq(VillageProp.prop_art_path("planter", "suburban"), "res://assets/sprites/buildings/medieval/harmonia_arms.png", "the world's own drawing lost to the generic one")
	assert_eq(VillageProp.prop_art_path("crate", "medieval"), "", "a kind with no entry found art")


func test_an_entry_whose_file_is_missing_keeps_the_painted_prop() -> void:
	## Planted entries REPLACE the manifest's, so a shipped barrel drawing cannot make this arm pass for the wrong reason.
	VillageProp.prop_art_override = {"barrel": {"path": "res://assets/sprites/props/no_such_barrel.png"}}
	assert_eq(VillageProp.prop_art_path("barrel", "medieval"), "", "a missing file was handed out as art, which would draw nothing")
	var v := _village(HARMONIA)
	for b in _props(v, VillageProp.Kind.BARREL):
		assert_eq(_tex_size(b), VillageProp.SIZES[VillageProp.Kind.BARREL] * VillageProp.TILE, "%s went blank" % b.name)


func test_drawn_art_stands_on_the_base_row_centred_over_its_footprint() -> void:
	VillageProp.prop_art_override = {"stall": {"path": PLANT}}
	var v := _village(HARMONIA)
	var stalls := _props(v, VillageProp.Kind.STALL)
	assert_gt(stalls.size(), 0, "CONTROL: Harmonia places stalls")
	for st in stalls:
		var spr := st.get_node("Sprite") as Sprite2D
		var r: Rect2 = spr.get_rect()
		r.position += spr.position
		var foot_w: float = VillageProp.SIZES[VillageProp.Kind.STALL].x * VillageProp.TILE
		assert_almost_eq(r.end.y, 0.0, 0.5, "%s's art does not stand on its base row" % st.name)
		assert_almost_eq(r.get_center().x, -VillageProp.TILE / 2.0 + foot_w / 2.0, 0.5, "%s's art is not centred over its footprint" % st.name)


func _fountain(v: Node) -> Node:
	for b in v.buildings.get_children():
		if b is VillageFountain:
			return b
	return null


func test_the_fountain_draws_its_art_on_the_same_base() -> void:
	VillageProp.prop_art_override = {}  ## no art, whatever the manifest ships: the control is the painted fountain
	var painted := _fountain(_village(HARMONIA))
	assert_not_null(painted, "CONTROL: Harmonia has its fountain")
	assert_eq(painted._sprite_frames.size(), 4, "CONTROL: with no art the fountain is the painted 4-frame one")
	var painted_base: float = painted.sprite.position.y + painted.sprite.offset.y + painted.sprite.texture.get_height() / 2.0
	VillageProp.prop_art_override = {"fountain_medieval": {"path": PLANT, "frames": 2}}
	var drawn := _fountain(_village(HARMONIA))
	assert_eq(drawn._sprite_frames.size(), 2, "the fountain did not cut its drawn strip into frames")
	assert_eq(drawn.sprite.texture.get_width(), _plant_size().x / 2, "a frame is not one cell of the strip")
	var drawn_base: float = drawn.sprite.position.y + drawn.sprite.offset.y + drawn.sprite.texture.get_height() / 2.0
	assert_almost_eq(drawn_base, painted_base, 0.5, "the drawn fountain does not stand where the painted one did")


func test_every_shipped_entry_names_a_real_prop_world_and_file() -> void:
	VillageProp.prop_art_override = null
	VillageProp._prop_art_cache = null
	var sec := VillageProp._prop_art_section()
	var kinds: Array = ["fountain", "chest_closed", "chest_open"]
	for k in VillageProp.Kind.keys():
		if k != "HOUSE":
			kinds.append(str(k).to_lower())
	for key in sec:
		var e: Dictionary = sec[key]
		assert_true(ResourceLoader.exists(str(e.get("path", ""))), "prop_art '%s' has no file: %s" % [key, e.get("path", "")])
		assert_ne(str(e.get("tier", "")), "", "prop_art '%s' does not say its tier" % key)
		var ok: bool = false
		for k in kinds:
			if key == k or (str(key).begins_with(k + "_") and str(key).trim_prefix(k + "_") in WORLDS + _village_keys()):
				ok = true
		assert_true(ok, "prop_art '%s' is not <kind> or <kind>_<world> or <kind>_<village>, so nothing will ever read it" % key)
	assert_true(sec is Dictionary, "prop_art did not parse as a section")


func test_the_inventory_the_art_is_asked_for() -> void:
	## Derived, not pinned: every painted (kind, world) a village places, so the art lane works from the live list.
	var placed := {}
	for f in DirAccess.get_files_at(VILLAGES):
		if not f.ends_with(".gd") or f == "BaseVillage.gd":
			continue
		var v = load(VILLAGES + "/" + f).new()
		add_child_autofree(v)
		if not ("props" in v) or v.props == null:
			continue
		for c in v.props.get_children():
			if c is VillageProp and c.kind != VillageProp.Kind.HOUSE:
				var key := "%s_%s" % [str(VillageProp.Kind.keys()[c.kind]).to_lower(), c.sheet_key]
				placed[key] = int(placed.get(key, 0)) + 1
		if _fountain(v) != null:
			placed["fountain_" + _fountain(v).art_world] = int(placed.get("fountain_" + _fountain(v).art_world, 0)) + 1
	var keys := placed.keys()
	keys.sort()
	gut.p("painted props by kind_world: %s" % str(keys.map(func(k): return "%s x%d" % [k, placed[k]])))
	assert_gt(keys.size(), 10, "the inventory found almost nothing to draw")
	assert_true(placed.has("fountain_medieval"), "Harmonia's fountain is missing from the inventory")
	assert_true(placed.has("lamp_post_steampunk"), "CONTROL: Brasston's lamp posts are in the inventory")


func _chests(v: Node) -> Array:
	var out: Array = []
	for b in v.treasures.get_children():
		if b.has_method("_chest_art"):
			out.append(b)
	return out


func test_a_chest_takes_its_worlds_drawing_and_keeps_the_shared_pair_otherwise() -> void:
	VillageProp.prop_art_override = {}
	var v := _village(HARMONIA)
	var chests := _chests(v)
	assert_gt(chests.size(), 0, "CONTROL: Harmonia has a treasure chest")
	assert_eq(chests[0]._world(), "medieval", "a chest could not tell which world it stands in")
	assert_eq(chests[0]._chest_art("closed"), "res://assets/sprites/objects/chest_closed.png", "with no prop_art the chest lost the shared pair")
	VillageProp.prop_art_override = {"chest_closed_medieval": {"path": PLANT}, "chest_open": {"path": "res://assets/sprites/buildings/medieval/harmonia_arms.png"}}
	assert_eq(chests[0]._chest_art("closed"), PLANT, "the world's chest drawing was not used")
	assert_eq(chests[0]._chest_art("open"), "res://assets/sprites/buildings/medieval/harmonia_arms.png", "a generic open-chest drawing was not used")
	var drawn := _chests(_village(HARMONIA))
	var closed: Array = drawn.filter(func(c): return not c._is_opened)
	if not closed.is_empty():
		assert_eq(Vector2i(closed[0].sprite.texture.get_width(), closed[0].sprite.texture.get_height()), _plant_size(), "a closed chest did not draw its world's art")


## Every village's prop_art name, derived from the _get_area_id each village script declares.
func _village_keys() -> Array:
	var out: Array = []
	var rx := RegEx.create_from_string('func _get_area_id\\(\\)[^\\n]*\\n\\s*return "([a-z_]+)"')
	for f in DirAccess.get_files_at(VILLAGES):
		if f.ends_with(".gd") and f != "BaseVillage.gd":
			var m := rx.search(FileAccess.get_file_as_string(VILLAGES + "/" + f))
			if m != null:
				out.append(VillageProp.village_art_key(m.get_string(1)))
	return out


func test_a_village_drawing_outranks_its_worlds() -> void:
	assert_true("frosthold" in _village_keys(), "CONTROL: the village names derive (got %s)" % str(_village_keys()))
	VillageProp.prop_art_override = {"tree_frosthold": {"path": PLANT}, "tree_medieval": {"path": "res://assets/sprites/buildings/medieval/harmonia_arms.png"}}
	assert_eq(VillageProp.prop_art_path("tree", "medieval", "frosthold"), PLANT, "Frosthold's own tree lost to the world's")
	assert_eq(VillageProp.prop_art_path("tree", "medieval", "harmonia"), "res://assets/sprites/buildings/medieval/harmonia_arms.png", "a village without its own tree did not fall back to the world's")
	var v := _village("res://src/maps/villages/FrostholdVillage.gd")
	var trees := _props(v, VillageProp.Kind.TREE)
	assert_gt(trees.size(), 0, "CONTROL: Frosthold places a tree")
	for t in trees:
		assert_eq(_tex_size(t), _plant_size(), "%s did not take Frosthold's drawing" % t.name)
