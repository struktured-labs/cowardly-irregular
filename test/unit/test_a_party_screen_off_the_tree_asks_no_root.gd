extends GutTest

## PartyStatusScreen's three name resolvers asked `/root/<System>` with no tree check, so a screen
## built detached (test_party_status_screen_titlecase does, for its fallback arms) logged
## "Can't use get_node() with absolute paths from outside the active scene tree" and got null anyway.
## Gated like ShopInterior and InnInterior: off the tree they skip the lookup and fall back as before;
## in the tree they still read the designer-set name.

const SCREEN := "res://src/ui/PartyStatusScreen.gd"


func test_every_root_lookup_is_gated_on_the_tree() -> void:
	var src: String = FileAccess.get_file_as_string(SCREEN)
	assert_ne(src, "", "FLOOR: the screen's source must be readable")
	for system in ["JobSystem", "PassiveSystem", "EquipmentSystem"]:
		var call: String = 'get_node_or_null("/root/%s")' % system
		assert_eq(src.count(call), 1, "CONTROL: %s is looked up exactly once" % system)
		assert_eq(src.count(call + " if is_inside_tree() else null"), 1,
			"the %s lookup must be gated on is_inside_tree()" % system)


func test_a_detached_screen_still_falls_back_to_a_title_cased_id() -> void:
	var s = load(SCREEN).new()
	autofree(s)
	assert_false(s.is_inside_tree(), "CONTROL: the screen is detached")
	assert_eq(s._resolve_ability_name("cure"), "Cure", "detached, the id is title-cased as before")
	assert_eq(s._resolve_passive_name("iron_will"), "Iron Will", "the passive fallback too")
	assert_eq(str(s._resolve_equipment("bronze_sword").get("name", "")), "Bronze Sword", "and the equipment fallback")


func test_a_screen_in_the_tree_still_reads_the_designer_name() -> void:
	var s = load(SCREEN).new()
	add_child_autofree(s)
	await get_tree().process_frame
	assert_true(s.is_inside_tree(), "CONTROL: the screen is in the tree")
	## data/abilities.json names "cure" Sanatio, which the fallback could never produce.
	assert_eq(s._resolve_ability_name("cure"), "Sanatio",
		"in the tree the gate must still reach JobSystem and return the authored name")
