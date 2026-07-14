extends GutTest

## Regression (web-smoke stage-3 find 2026-07-11): the quest tracker painted
## over the pause menu's PARTY header and the objective arrow crossed the
## Mage row — field-HUD widgets live on CanvasLayers ABOVE the menu's 50.
## Opening the overworld menu must hide them; closing must restore exactly
## what was hidden. The widgets are Node wrappers around a `_canvas`
## CanvasLayer, so a plain CanvasItem check silently misses all four
## (minimap / tracker / objective arrow / border indicator).

const GL_PATH := "res://src/GameLoop.gd"


func _src() -> String:
	return FileAccess.get_file_as_string(GL_PATH)


func test_menu_open_and_close_toggle_the_field_hud() -> void:
	var src := _src()
	var open_fn := src.substr(src.find("func _open_overworld_menu"),
		src.find("\nfunc ", src.find("func _open_overworld_menu") + 1) - src.find("func _open_overworld_menu"))
	assert_true("_set_field_hud_hidden(true)" in open_fn,
		"_open_overworld_menu must hide the field HUD")
	var close_fn := src.substr(src.find("func _on_overworld_menu_closed"),
		src.find("\nfunc ", src.find("func _on_overworld_menu_closed") + 1) - src.find("func _on_overworld_menu_closed"))
	assert_true("_set_field_hud_hidden(false)" in close_fn,
		"_on_overworld_menu_closed must restore the field HUD")


func test_hider_resolves_canvas_wrapper_widgets() -> void:
	# The four exploration HUD widgets extend Node and hold `_canvas` —
	# the hider must resolve through that or it hides nothing.
	var src := _src()
	var fn := src.substr(src.find("func _set_field_hud_hidden"))
	assert_true("\"_canvas\" in w" in fn and "w._canvas is CanvasLayer" in fn,
		"hider must resolve Node-wrapped _canvas CanvasLayers")
	for prop in ["_minimap", "_quest_tracker", "_objective_arrow", "_border_indicator"]:
		assert_true("\"%s\"" % prop in src.substr(src.find("_FIELD_HUD_PROPS")),
			"prop list must cover %s" % prop)


func test_restore_only_touches_what_was_hidden() -> void:
	# Restore path iterates the recorded list — NOT the prop list — so a
	# widget the player had disabled (settings) stays hidden after close.
	var src := _src()
	var fn := src.substr(src.find("func _set_field_hud_hidden"))
	var restore := fn.substr(0, fn.find("_menu_hidden_hud.clear()\n\t\treturn"))
	assert_true("for n in _menu_hidden_hud" in restore,
		"restore must replay the recorded hidden set, not the full prop list")
