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


## BEHAVIOURAL, not a spelling pin. The first version asserted that
## ResourceLoader.exists appeared before Image.create inside _generate_sprite —
## which fails a correct refactor (extract the lookup into a helper) and passes a
## wrong one that keeps the text. cowir-cutscenes was failed by exactly that
## shape tonight: a pin on the expression they replaced, whose invariant their
## change preserved. Chest art exists on disk, so assert the outcome instead.
func test_a_closed_chest_renders_the_artist_sheet() -> void:
	var c = load("res://src/exploration/TreasureChest.gd").new()
	c.chest_id = "seam_closed_probe"
	add_child_autofree(c)
	await get_tree().process_frame
	var s = c.get_node_or_null("Sprite")
	assert_not_null(s, "chest built a sprite")
	assert_eq(s.texture.resource_path, "res://assets/sprites/objects/chest_closed.png",
		"a closed chest must render the artist sheet — a procedural ImageTexture has an EMPTY resource_path, so this fails the moment the lookup stops working")


## Both authored states must resolve, or a chest flips to procedural on opening.
func test_both_chest_states_have_reachable_art() -> void:
	for state in ["closed", "open"]:
		var p: String = "%s/chest_%s.png" % [OBJECTS_DIR, state]
		assert_true(ResourceLoader.exists(p),
			"chest_%s.png must be loadable — the open/closed pair is what the seam selects between" % state)


## The state must select the sheet. Driven, not read: an opened chest that still
## renders chest_closed.png is the defect, and no source pin can see it.
func test_an_opened_chest_renders_the_open_sheet() -> void:
	GameState.set_story_flag("chest_seam_open_probe", true)
	var c = load("res://src/exploration/TreasureChest.gd").new()
	c.chest_id = "seam_open_probe"
	add_child_autofree(c)
	await get_tree().process_frame
	var s = c.get_node_or_null("Sprite")
	assert_not_null(s, "chest built a sprite")
	assert_eq(s.texture.resource_path, "res://assets/sprites/objects/chest_open.png",
		"an opened chest must render the OPEN sheet — ignoring _is_opened renders it closed forever")
	GameState.set_story_flag("chest_seam_open_probe", false)


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
