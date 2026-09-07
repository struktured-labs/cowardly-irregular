extends GutTest

## Regression: PartyStatusScreen surfaces party gold in the title bar.
## Without this the player has to leave the menu and find a shop or the
## battle results screen to see their balance. Pinned: label exists,
## name=GoldLabel, formatted as "Gold: N G", live-read from GameState.

const PARTY_STATUS_PATH := "res://src/ui/PartyStatusScreen.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _build_combatant(name_str: String):
	var script = load(COMBATANT_PATH)
	var c = script.new()
	c.initialize({"name": name_str, "max_hp": 100, "max_mp": 100,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	c.job = {"id": "fighter", "name": "Fighter"}
	return c


func _stand_up_screen(party: Array) -> Node:
	var script = load(PARTY_STATUS_PATH)
	var s = script.new()
	add_child_autofree(s)
	s.party = party
	s.focused_index = 0
	s._build_ui()
	return s


func _find_node_recursive(root: Node, target_name: String) -> Node:
	if root.name == target_name:
		return root
	for child in root.get_children():
		var found = _find_node_recursive(child, target_name)
		if found:
			return found
	return null


func test_gold_label_renders_with_current_balance() -> void:
	var prev_gold: int = 0
	if GameState and "party_gold" in GameState:
		prev_gold = GameState.party_gold
		GameState.party_gold = 1234

	var c = _build_combatant("TestHero")
	var screen = _stand_up_screen([c])
	var label = _find_node_recursive(screen, "GoldLabel") as Label
	assert_not_null(label, "PartyStatusScreen must render a GoldLabel")
	if label:
		assert_eq(label.text, "Gold: 1234 G",
			"Gold label must format as 'Gold: <amount> G' and read GameState.party_gold live")

	if GameState and "party_gold" in GameState:
		GameState.party_gold = prev_gold
	c.free()


func test_gold_label_reflects_zero_balance() -> void:
	var prev_gold: int = 0
	if GameState and "party_gold" in GameState:
		prev_gold = GameState.party_gold
		GameState.party_gold = 0

	var c = _build_combatant("BrokeHero")
	var screen = _stand_up_screen([c])
	var label = _find_node_recursive(screen, "GoldLabel") as Label
	assert_not_null(label, "GoldLabel must render even when balance is 0")
	if label:
		assert_eq(label.text, "Gold: 0 G",
			"Zero balance must display literally as 'Gold: 0 G', not blank / N/A")

	if GameState and "party_gold" in GameState:
		GameState.party_gold = prev_gold
	c.free()


func test_gold_label_is_right_aligned_in_title_bar() -> void:
	# Layout invariant: the label sits in the right portion of the title
	# bar row so it doesn't overlap the centered "PARTY STATUS" text.
	var c = _build_combatant("LayoutTest")
	var screen = _stand_up_screen([c])
	var label = _find_node_recursive(screen, "GoldLabel") as Label
	assert_not_null(label, "GoldLabel must exist for layout assertion")
	if label:
		assert_eq(label.horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT,
			"GoldLabel must be right-aligned within its container")
		# Position.x should be in the right half of the viewport
		var vp_x = screen.get_viewport_rect().size.x
		if vp_x <= 0:
			vp_x = 1280.0
		assert_true(label.position.x > vp_x * 0.5,
			"GoldLabel must sit in the right half of the screen (pos.x=%d, vp.x=%d)" % [
				label.position.x, vp_x])
	c.free()
