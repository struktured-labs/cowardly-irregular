extends GutTest

## A player can backspace a name to nothing and confirm. cowir-battle traced the chain end to end
## and handed it to this lane; every link was unguarded:
##
##   CharacterCreationScreen  DEL branch        substr(0, len-1)   guarded only by `len > 0`
##                          ui_cancel branch  same deletion, same guard
##                          _close_name_grid()                   no minimum length
##                          _confirm_creation()                  emits with NO validation
##   GameLoop._create_party_from_customizations   "name": custom.name — straight through
##   AutobattleSystem._get_character_id          combatant_name.to_lower()  ->  ""
##
## ⛔ CITED BY SYMBOL, NOT BY LINE, BECAUSE MY OWN COMMIT INVALIDATED THE LINE NUMBERS. The first
## version of this header cited :897 :911 :902 :994 — and the fix inserted 12 lines above them, so
## every one was off by 8 before the commit landed. A line number is a pointer into a file that the
## same diff is editing; a symbol survives its own patch.
##
## ⛔ EVERY EMPTY-NAMED PC SHARES THE ONE AUTOBATTLE ID `""`. The defaults are fine — the factory
## builds "Hero" and friends — which is why this is invisible until a player EDITS.
##
## 🔑 The floor is at _close_name_grid rather than at _confirm_creation, because that is where the
## player can still see what happened: clearing the field and confirming restores the name the grid
## opened with. A floor at the emit would silently rename a field the player is looking at.

const CreationScript = preload("res://src/ui/CharacterCreationScreen.gd")


func _screen() -> Node:
	var s: Node = CreationScript.new()
	add_child_autofree(s)
	return s


func test_clearing_a_name_and_confirming_restores_it() -> void:
	var s := _screen()
	assert_gt(s.party_customizations.size(), 0,
		"LIVENESS: the factory must build a party, or every assertion below is about an empty list")
	var who = s.party_customizations[0]
	var original: String = str(who.name)
	assert_ne(original, "", "the factory must give a non-empty default, or this guard has no baseline")

	s.current_character_index = 0
	s._start_name_editing()
	who.name = ""
	s._close_name_grid()
	assert_eq(str(who.name), original,
		"a name backspaced to nothing must come back as what the grid opened with — a nameless PC "
		+ "takes autobattle id \"\" and collides with every other nameless PC")


func test_a_real_edit_is_kept() -> void:
	var s := _screen()
	var who = s.party_customizations[0]
	s.current_character_index = 0
	s._start_name_editing()
	who.name = "Zelia"
	s._close_name_grid()
	assert_eq(str(who.name), "Zelia",
		"CONTROL: the floor must not eat a real rename — if it does, the guard is worse than the bug")


## Whitespace is the same defect wearing a space: strip_edges() is what the floor tests.
func test_a_whitespace_only_name_is_also_refused() -> void:
	var s := _screen()
	var who = s.party_customizations[0]
	var original: String = str(who.name)
	s.current_character_index = 0
	s._start_name_editing()
	who.name = "   "
	s._close_name_grid()
	assert_eq(str(who.name), original,
		"a name of spaces reaches the same empty id after to_lower().replace(\" \", \"_\")")


## The last-resort floor: if even the prior name was empty (a customization authored before this
## guard), the screen must still not emit a nameless PC.
func test_an_already_empty_prior_name_falls_back_to_the_default() -> void:
	var s := _screen()
	var who = s.party_customizations[0]
	s.current_character_index = 0
	who.name = ""
	s._start_name_editing()      # records "" as the prior name
	s._close_name_grid()
	assert_ne(str(who.name), "",
		"with no prior name to restore, the floor must still produce a name rather than passing "
		+ "the empty one through")
	assert_eq(str(who.name), CreationScript.DEFAULT_NAME,
		"and it must be the declared default, not an accident of some other field")
