extends GutTest

## The grind console's title read "AUTOGRIND RULES - Steampunk Overworld": GameLoop dressed the raw map id up with capitalize(), while
## the area banner, the save slot and every other surface name the place from locations.json ("Cogsworth Junction"). All 41 locations
## read differently from their capitalized ids. Same class as cowir-ai's 23318 for NPC prompts. The expected name is read from the
## JSON HERE, not through the code's own lookup, so the guard cannot merely agree with it.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const GL_SRC := "res://src/GameLoop.gd"

var _ag: Dictionary


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true


func after_each() -> void:
	InputLockManager.pop_all()
	AutogrindState.restore(_ag)


## A map whose authored name differs from its capitalized id, read straight from the data.
func _renamed_map() -> Array:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/locations.json"))
	for k in d:
		var e: Dictionary = d[k]
		var mid := str(e.get("map_id", ""))
		var nm := str(e.get("name", ""))
		if mid != "" and nm != "" and nm != mid.replace("_", " ").capitalize():
			return [mid, nm]
	return []


func test_the_console_title_names_the_place_not_its_id() -> void:
	var pick := _renamed_map()
	assert_eq(pick.size(), 2, "CONTROL: locations.json holds a map whose name differs from its capitalized id")
	if pick.size() != 2:
		return
	var gl: Node = load(GL_SRC).new()
	add_child_autofree(gl)
	gl._exploration_scene = autofree(Node.new())
	gl._current_map_id = pick[0]
	var c := Combatant.new()
	autofree(c)
	c.initialize({"name": "Fighter", "max_hp": 100, "max_mp": 20})
	var members: Array[Combatant] = [c]
	gl.party = members
	gl._open_autogrind_ui()
	await wait_frames(3)
	var ui: Node = gl._autogrind_ui
	assert_not_null(ui, "CONTROL: the console opened")
	if ui == null:
		return
	var titles: Array = []
	for n in ui.find_children("*", "Label", true, false):
		if str((n as Label).text).begins_with("AUTOGRIND RULES"):
			titles.append((n as Label).text)
	assert_eq(titles.size(), 1, "CONTROL: one console title was built, got %s" % [titles])
	if titles.size() == 1:
		assert_eq(str(titles[0]), "AUTOGRIND RULES - %s" % pick[1], "the console names the place as the game does, not '%s'" % str(pick[0]).replace("_", " ").capitalize())
