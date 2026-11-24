extends GutTest

## cowir-sprites 2026-11-24: six of nine catalog recipes revealed an EMPTY art window (no icon_<id>), and nothing else reds on that.

const ACTOR := "fighter"


## Every catalog recipe, as the reveal receives it: [id, reveal_dict].
func _dicts() -> Array:
	var ledger := RecipeLedger.new()
	var out: Array = []
	for id in RecipeCatalog.ids():
		out.append([id, ledger.reveal_dict(ACTOR, id)])
	return out


func test_every_catalog_recipe_has_a_registered_icon_the_reveal_can_load() -> void:
	var section := RecipeReveal.manifest_section()
	assert_false(section.is_empty(), "the reveal must read its recipe_cards section")
	var judged: Array = []
	var missing: Array = []
	for pair in _dicts():
		var id: String = pair[0]
		var d: Dictionary = pair[1]
		judged.append(id)
		var key: String = str(d.get("icon_key", ""))
		var tex := RecipeReveal._texture(RecipeReveal.card_entry(section, key))
		if key == "" or tex == null:
			missing.append("%s (icon_key '%s')" % [id, key])
	assert_true(judged.has("heal_ally_under_50"), "the scan must reach Triage, whose icon shipped first")
	assert_gt(judged.size(), 1, "the scan must judge the catalog, not one sample")
	assert_eq(missing, [], "a catalog recipe would reveal an EMPTY art window: %s" % [missing])


func test_every_icon_fits_its_card_window_at_least_twice_over() -> void:
	var section := RecipeReveal.manifest_section()
	var judged := 0
	var small: Array = []
	for pair in _dicts():
		var d: Dictionary = pair[1]
		var tex := RecipeReveal._texture(RecipeReveal.card_entry(section, str(d.get("icon_key", ""))))
		if tex == null:
			continue
		var card := RecipeReveal.card_entry(section, "card_" + str(d.get("rarity", "common")))
		var art: Rect2 = RecipeReveal._rect_from(card.get("art_window"), RecipeReveal.ART_WINDOW)
		var sz := tex.get_size()
		var k := floorf(minf(art.size.x / sz.x, art.size.y / sz.y))
		judged += 1
		if k < 2.0:
			small.append("%s is %dx%d, draws at %dx in a %dx%d window" % [pair[0], sz.x, sz.y, k, art.size.x, art.size.y])
	assert_gt(judged, 1, "the fit arm must judge loaded icons, not none")
	assert_eq(small, [], "an icon too big for a 2x integer fit draws at 1x or not at all: %s" % [small])


func test_control_an_unregistered_icon_reads_as_missing() -> void:
	var section := RecipeReveal.manifest_section()
	assert_false(section.is_empty(), "the reveal must read its recipe_cards section")
	assert_null(RecipeReveal._texture(RecipeReveal.card_entry(section, "icon_no_such_recipe")),
		"a key nobody registered must load nothing, or the coverage arm could never red")
