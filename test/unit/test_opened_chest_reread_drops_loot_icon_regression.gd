extends GutTest

## Opening an item or equipment chest pins that loot's icon beside the "Found" line
## and slides the label over to make room. A second confirm — the press a player uses
## to answer a popup — took the empty-chest path, which only rewrites the words.
## The icon stayed, so "The chest is empty." still showed the thing you just received,
## and the found line was gone before it could be read.

const CHEST_ID := "opened_reread_probe"
const FLAG := "chest_" + CHEST_ID


func before_each() -> void:
	if GameState:
		GameState.story_flags.erase(FLAG)


func after_each() -> void:
	if GameState:
		GameState.story_flags.erase(FLAG)


## chest_id and contents are set before add_child: _ready reads the id for the opened flag.
func _opened_item_chest() -> TreasureChest:
	var chest := TreasureChest.new()
	chest.chest_id = CHEST_ID
	chest.contents_type = "item"
	chest.contents_id = "potion"
	chest.contents_amount = 2
	add_child_autofree(chest)
	var player := Node2D.new()
	add_child_autofree(player)
	chest._open_chest(player)
	assert_eq(chest.dialogue_label.text, "Found Potion x2!",
		"the open must announce the potion before a second press can be judged")
	assert_not_null(chest.dialogue_box.get_node_or_null("LootIcon"),
		"the open must show the loot icon this regression is about")
	return chest


func test_a_second_press_keeps_the_found_line() -> void:
	var chest := _opened_item_chest()
	chest.interact(Node2D.new())
	assert_eq(chest.dialogue_label.text, "Found Potion x2!",
		"confirming while the found line is up must not replace it with the empty-chest line")
	var icon := chest.dialogue_box.get_node_or_null("LootIcon")
	assert_true(icon != null and not icon.is_queued_for_deletion(),
		"the loot icon stays with the found line until that line finishes")


func test_rereading_an_opened_chest_drops_the_loot_icon() -> void:
	var chest := _opened_item_chest()
	# The found line holds the screen for 2s. After it dismisses, a later press is the empty reread.
	await get_tree().create_timer(2.2).timeout
	chest.interact(Node2D.new())
	assert_eq(chest.dialogue_label.text, "The chest is empty.")
	var icon := chest.dialogue_box.get_node_or_null("LootIcon")
	assert_true(icon == null or icon.is_queued_for_deletion(),
		"the empty line must not keep the icon of the item already taken")
	assert_eq(chest.dialogue_label.position, Vector2(-112, -102),
		"the empty line uses the full centered label, not the slot left of the loot icon")
	assert_eq(chest.dialogue_label.size, Vector2(224, 44))
	assert_eq(chest.dialogue_label.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER)
