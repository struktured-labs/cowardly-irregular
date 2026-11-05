extends GutTest

## cowir-main 22171: the render smoke's player-path leg was RANDOM. Its touch can pull alerted roamers into a CHAIN,
## and the leg's hand-back victory then started the next link: a real fight (.772 try1: spiteful_crow x2) that the
## smoke plays by tapping accept and can lose. DEFEAT -> "exploration never came back" -> every later leg failed as
## SETUP. Across 16 recent smokes every FAIL had chain=1. The leg covers the battle ENTRY, so it drops the chain
## before the hand-back; the victory path continues a chain only while _chain_links is non-empty.


func _game_loop() -> Node:
	var gl: Node = load("res://src/GameLoop.gd").new()
	autofree(gl)
	return gl


func test_the_drop_ends_a_live_chain() -> void:
	var gl := _game_loop()
	gl._chain_links = [[["spiteful_crow", "spiteful_crow"]], [["bat"]]]
	gl._chain_total = 3
	gl._chain_index = 1
	gl._chain_engaged = 1
	assert_false(gl._chain_links.is_empty(), "CONTROL: a two-link chain is pending, so the victory WOULD continue it")
	assert_eq(gl._smoke_drop_chain(), 2, "the drop reports the two links it removed")
	assert_true(gl._chain_links.is_empty(), "and nothing is left for the victory path to continue")
	assert_eq(gl._chain_total, 0, "and the chain's banner count is cleared with it")


func test_no_chain_drops_nothing() -> void:
	assert_eq(_game_loop()._smoke_drop_chain(), 0, "a touch that pulled no joiners drops 0, so the leg prints nothing")


## The drop must come BEFORE the hand-back: after end_battle(true) the victory screen is already deciding.
func test_the_leg_drops_the_chain_before_it_hands_the_battle_back() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var i := src.find("func _smoke_player_path_battle")
	assert_gt(i, -1, "CONTROL: the player-path leg exists")
	var body := src.substr(i, src.find("\nfunc ", i + 1) - i)
	var hand_back := body.find("BattleManager.end_battle(true)")
	assert_gt(hand_back, -1, "CONTROL: the leg hands the battle back")
	var drop := body.find("_smoke_drop_chain()")
	assert_gt(drop, -1, "the leg drops the chain")
	assert_lt(drop, hand_back, "before it hands the battle back")
