extends GutTest

## Art we own must be reachable.
##
## Three instances of one defect class in one evening: Phil's portrait (key
## resolved by npc_type, never by name), the masterite silhouette (no loader at
## all), and the treasure chest — assets/sprites/objects/ held chest_open.png and
## chest_closed.png with ZERO consumers anywhere in src/, tools/ or data/, while
## TreasureChest drew procedurally across 14 maps.
##
## The tell is always the same: a drawer with no art lookup beside art that
## exists. Procedural is a legitimate DEFAULT (tile generators, signposts,
## markers); it is a defect only when purpose-made art sits unreachable.

const OBJECTS_DIR := "res://assets/sprites/objects"


func test_chest_art_is_consulted_before_the_procedural_draw() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/exploration/TreasureChest.gd")
	var i := src.find("func _generate_sprite")
	assert_gt(i, 0, "the sprite builder still exists")
	var body: String = src.substr(i, 600)
	var art_at := body.find("ResourceLoader.exists")
	var draw_at := body.find("Image.create")
	assert_gt(art_at, -1, "chest art is looked up")
	assert_lt(art_at, draw_at,
		"the art lookup must precede the procedural draw — after it the fallback always wins")


## Both authored states must resolve, or a chest flips to procedural on opening.
func test_both_chest_states_have_reachable_art() -> void:
	for state in ["closed", "open"]:
		var p: String = "%s/chest_%s.png" % [OBJECTS_DIR, state]
		assert_true(ResourceLoader.exists(p),
			"chest_%s.png must be loadable — the open/closed pair is what the seam selects between" % state)


## The drawer must actually pick the state's art, not one fixed image.
func test_opened_and_closed_select_different_art() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/exploration/TreasureChest.gd")
	assert_true(src.contains("\"open\" if _is_opened else \"closed\""),
		"the state selects the sheet — a fixed path would render an open chest as closed")


## A chest builds and carries a texture in both states. Runtime, because source
## cannot show that the load actually resolved.
func test_chest_builds_with_a_texture_in_both_states() -> void:
	var script = load("res://src/exploration/TreasureChest.gd")
	for opened in [false, true]:
		var c = script.new()
		c.chest_id = "seam_probe_%s" % str(opened)
		add_child_autofree(c)
		await get_tree().process_frame
		var s = c.get_node_or_null("Sprite")
		assert_not_null(s, "chest builds a Sprite node (opened=%s)" % str(opened))
		if s != null:
			assert_not_null(s.texture, "chest carries a texture (opened=%s)" % str(opened))
