extends GutTest

## Regression: the 'autobattle_intro' tutorial hint exists in the catalog but
## was never fired from any call site. GameLoop._toggle_autobattle_editor now
## triggers it once per save the first time the player opens the editor.


const GAMELOOP_PATH := "res://src/GameLoop.gd"


func test_autobattle_intro_hint_in_catalog() -> void:
	assert_true(TutorialHints.HINTS.has("autobattle_intro"),
		"catalog must declare autobattle_intro for the fire site to consume")


func test_autobattle_editor_fires_intro_hint() -> void:
	var file = FileAccess.open(GAMELOOP_PATH, FileAccess.READ)
	var text = file.get_as_text()
	file.close()
	assert_true(text.find("TutorialHints.show(self, \"autobattle_intro\")") > -1,
		"GameLoop must call TutorialHints.show(..., 'autobattle_intro') on first editor open")
	assert_true(text.find("_autobattle_editor_ever_opened") > -1,
		"GameLoop must latch the first-open via _autobattle_editor_ever_opened")
