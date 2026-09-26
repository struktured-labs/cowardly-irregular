extends GutTest

## Walking back through a return portal left "YOU ARE HERE" on a world the player had left.
##
## WorldMapMenu._detect_current_world scanned prologue flags from W6 downward and
## stopped at the furthest world whose prologue was complete. That matched the
## map only while the player never went backwards. The W2 return portal
## ("Return to Overworld") is a normal door: after the W2 prologue, stepping
## through it puts you on the medieval overworld (GameState.current_world = 1)
## while cutscene_flag_world2_prologue_complete stays set. Opening the world
## map then stamped YOU ARE HERE on The Mundane Sprawl and the footer read
## "Current: World 2" over a World 1 map.
##
## The control arm is the case the old scan got right (standing in the furthest
## prologue world), so a green there only proves the marker is findable.


var _saved_world: int = 1
var _had_w2_prologue: bool = false
var _saved_w2_prologue: bool = false


func before_each() -> void:
	_saved_world = int(GameState.current_world)
	_had_w2_prologue = GameState.game_constants.has("cutscene_flag_world2_prologue_complete")
	_saved_w2_prologue = bool(GameState.game_constants.get("cutscene_flag_world2_prologue_complete", false))


func after_each() -> void:
	GameState.current_world = _saved_world
	if _had_w2_prologue:
		GameState.game_constants["cutscene_flag_world2_prologue_complete"] = _saved_w2_prologue
	else:
		GameState.game_constants.erase("cutscene_flag_world2_prologue_complete")


func test_you_are_here_stays_on_the_world_you_walked_back_to() -> void:
	GameState.current_world = 1
	GameState.game_constants["cutscene_flag_world2_prologue_complete"] = true
	var menu := WorldMapMenu.new()
	add_child_autofree(menu)
	assert_eq(_world_marked_here(menu), 1,
		"returned to World 1 after the W2 prologue, but YOU ARE HERE is on world %d — the marker follows the furthest prologue, not the map you are standing on" % _world_marked_here(menu))
	assert_eq(_footer_world(menu), 1,
		"footer says Current: World %d after walking back to World 1" % _footer_world(menu))


func test_you_are_here_still_marks_the_world_you_are_in() -> void:
	# Control: standing in the furthest reached world. The old scan and the
	# map agree, so this arm stays green across the fix and proves the marker
	# is actually drawn.
	GameState.current_world = 2
	GameState.game_constants["cutscene_flag_world2_prologue_complete"] = true
	var menu := WorldMapMenu.new()
	add_child_autofree(menu)
	assert_eq(_world_marked_here(menu), 2,
		"SCOPE control: standing in World 2 with its prologue done should mark world 2, got %d — the probe cannot see YOU ARE HERE" % _world_marked_here(menu))
	assert_eq(_footer_world(menu), 2,
		"SCOPE control: footer should say World 2, got %d" % _footer_world(menu))


func _world_marked_here(menu: WorldMapMenu) -> int:
	for i in menu._world_cards.size():
		if _label_text(menu._world_cards[i], "YOU ARE HERE"):
			return i + 1
	return -1


func _footer_world(menu: WorldMapMenu) -> int:
	var line := _find_label_prefix(menu, "Current:")
	if line == "":
		return -1
	var at := line.find("World ")
	if at < 0:
		return -1
	var rest := line.substr(at + 6)
	var digits := ""
	for i in rest.length():
		var ch := rest.substr(i, 1)
		if ch >= "0" and ch <= "9":
			digits += ch
		else:
			break
	if digits == "":
		return -1
	return int(digits)


func _label_text(node: Node, text: String) -> bool:
	if node is Label and (node as Label).text == text:
		return true
	for child in node.get_children():
		if _label_text(child, text):
			return true
	return false


func _find_label_prefix(node: Node, prefix: String) -> String:
	if node is Label and str((node as Label).text).begins_with(prefix):
		return (node as Label).text
	for child in node.get_children():
		var found := _find_label_prefix(child, prefix)
		if found != "":
			return found
	return ""
