extends GutTest

## An LLM villager's view of the party's supplies named each item by its id in words ("phoenix down x3"), while the
## item menu says "Resurgo Plume": 44 items show a name their id does not spell, and one of those ids is a Final
## Fantasy name the menu was renamed away from. Same defect as the Rule Composer's item list (.768), on the NPC path.
## Names are read from ItemSystem at runtime, never written here, so a rename moves with the data. The fix reuses
## ItemNameResolver (the shared reader; its own docstring forbids private copies), so these arms judge that path.

const DC := preload("res://src/llm/DynamicConversation.gd")

var _saved_party: Array = []


func before_each() -> void:
	_saved_party = GameState.player_party.duplicate(true)


func after_each() -> void:
	GameState.player_party.clear()
	for entry in _saved_party:
		GameState.player_party.append(entry)


func _items() -> Node:
	return get_tree().root.get_node("ItemSystem")


## An id whose menu name is not its id in words; derived, so the fixture survives any one rename.
func _renamed_id() -> String:
	for id in _items().items:
		var shown: String = str((_items().items[id] as Dictionary).get("name", "")).strip_edges()
		if shown != "" and shown.to_lower().replace("-", " ") != str(id).replace("_", " ").to_lower():
			return str(id)
	return ""


func test_the_party_supplies_use_the_menu_name() -> void:
	var id: String = _renamed_id()
	assert_ne(id, "", "CONTROL: items.json holds an item whose menu name its id does not spell")
	if id == "":
		return
	var shown: String = str(_items().get_item(id).get("name", ""))
	GameState.player_party.clear()
	GameState.player_party.append({"name": "Kai", "job_id": "fighter", "current_hp": 10, "max_hp": 10,
		"is_alive": true, "inventory": {id: 3}})
	var conv: Node = autofree(DC.new())
	add_child(conv)
	var notable: Array = conv._resolve_party_state().get("notable_items", [])
	assert_eq(notable, ["%s x3" % shown],
		"THE DEFECT: the villager must see '%s', the name on the player's menu, not '%s'" % [shown, id.replace("_", " ")])


func test_an_unknown_id_still_reads_as_words() -> void:
	GameState.player_party.clear()
	GameState.player_party.append({"name": "Kai", "job_id": "fighter", "current_hp": 10, "max_hp": 10,
		"is_alive": true, "inventory": {"not_an_item_anywhere": 1}})
	var conv: Node = autofree(DC.new())
	add_child(conv)
	assert_eq(conv._resolve_party_state().get("notable_items", []), ["Not An Item Anywhere"],
		"an id with no record keeps a readable fallback rather than going blank")
