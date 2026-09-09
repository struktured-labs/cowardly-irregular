extends GutTest

## Regression: two player-facing sources taught a pad route to the Autobattle Editor that does
## not exist. The "autobattle_intro" hint said "L+R together" — no L+R chord opens the editor
## anywhere in src/ (the only L+R handler cycles autogrind tier). Milo said "F5 or START" —
## true only mid-battle; in the field Start opens Settings and the editor lives under
## Menu → Auto Rules. Both now describe the routes the code actually has, and this pins the
## copy to the code so the next binding move fails here instead of on the couch.

const TH = preload("res://src/ui/TutorialHints.gd")
const OM = preload("res://src/ui/OverworldMenu.gd")

const MILO_SOURCES := [
	"res://src/maps/villages/HarmoniaVillage.gd",
	"res://data/cutscenes/npc_showcase_personas.json",
]


func _hint_body() -> String:
	return str((TH.HINTS["autobattle_intro"] as Dictionary).get("body", ""))


func test_hint_no_longer_teaches_the_phantom_chord() -> void:
	assert_eq(_hint_body().find("L+R"), -1, "no L+R chord opens the editor; the hint must not name one")
	assert_true(_hint_body().contains("{menu}"), "the battle route (Start) must be named via the {menu} token")
	assert_true(_hint_body().contains("Auto Rules"), "the field route (Menu → Auto Rules) must be named")
	assert_true(_hint_body().contains("F5"), "the keyboard route must survive")


func test_the_field_route_the_hint_names_exists() -> void:
	## ARM+: naming "Auto Rules" is only true while OverworldMenu carries that row.
	var found := false
	for opt in OM.BASE_MENU_OPTIONS:
		if str((opt as Dictionary).get("id", "")) == "autobattle":
			found = str((opt as Dictionary).get("label", "")) == "Auto Rules"
	assert_true(found, "OverworldMenu must offer an 'autobattle' row labelled 'Auto Rules'")


func test_the_battle_route_the_hint_names_exists() -> void:
	## ARM+: the ui_menu branch in GameLoop's BATTLE state must still reach the editor.
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_false(src.is_empty())
	var menu_at := src.find("if event.is_action_pressed(\"ui_menu\"):")
	assert_true(menu_at >= 0, "GameLoop must still branch on ui_menu")
	var editor_at := src.find("_toggle_autobattle_editor()", menu_at)
	assert_true(editor_at >= 0 and editor_at - menu_at < 2500,
		"the ui_menu branch must reach _toggle_autobattle_editor within its battle arm")


func test_no_lr_chord_opens_the_editor_anywhere() -> void:
	## If someone adds the chord for real, this fails and the copy should be updated deliberately.
	for path in ["res://src/GameLoop.gd", "res://src/battle/BattleScene.gd", "res://src/ui/OverworldMenu.gd"]:
		var src := FileAccess.get_file_as_string(path)
		var i := 0
		while true:
			i = src.find("JOY_BUTTON_LEFT_SHOULDER", i)
			if i < 0:
				break
			# The handler's own block only — it ends at the next blank line, not at the next handler.
			var block_end := src.find("\n\n", i)
			var window := src.substr(i, (block_end - i) if block_end > i else 600)
			assert_eq(window.find("_toggle_autobattle_editor"), -1,
				"%s: an L+R editor chord appeared — update the autobattle_intro hint copy" % path)
			i += 1


func test_milo_names_the_real_pad_routes_in_both_sources() -> void:
	for path in MILO_SOURCES:
		var src := FileAccess.get_file_as_string(path)
		assert_false(src.is_empty(), "%s must be readable" % path)
		assert_eq(src.find("or START to open"), -1, "%s: the unconditional START claim came back" % path)
		assert_true(src.contains("Start does it mid-battle"), "%s: the battle-only Start route must be named" % path)
		assert_true(src.contains("Auto Rules"), "%s: the field route must be named" % path)
