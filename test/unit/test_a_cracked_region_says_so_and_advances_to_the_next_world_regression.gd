extends GutTest

## Two defects on the autogrind region-advance path.
## 1. The console sets current_region_id to a DISPLAY name ("Suburban Overworld"). get_current_world_index compared it raw
##    to WORLD_REGIONS ids, fell through to World 1, and a W2 grinder's "next world" was W2 again under the id spelling:
##    the warp played, the region's crack penalty reset, and the grind never reached W3.
## 2. With Auto-Advance ON (the default) and no next world, as in every W1 grind before W2 unlocks, a crack was only
##    printed. Rewards dropped 15% then 30% with no toast; the Auto-Advance OFF path already announced it.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

var _ag: Dictionary
var _saved_worlds: int
var _ctrl
var _in_place: Array = []
var _advanced: Array = []


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	_saved_worlds = int(GameState.worlds_unlocked)
	_in_place.clear()
	_advanced.clear()
	_ctrl = preload("res://src/autogrind/AutogrindController.gd").new()
	add_child_autofree(_ctrl)
	_ctrl.region_cracked_in_place.connect(func(r, l, p): _in_place.append([r, l, p]))
	_ctrl.region_advanced.connect(func(f, t, w): _advanced.append([f, t, w]))


func after_each() -> void:
	GameState.worlds_unlocked = _saved_worlds
	AutogrindState.restore(_ag)


func test_a_display_name_finds_its_own_world() -> void:
	GameState.worlds_unlocked = 3
	AutogrindSystem.current_region_id = "suburban_overworld"
	assert_eq(str(AutogrindSystem.get_next_region().get("region", "")), "steampunk_overworld", "CONTROL: from the W2 id the next world is W3")
	AutogrindSystem.current_region_id = "Suburban Overworld"
	assert_eq(str(AutogrindSystem.get_next_region().get("region", "")), "steampunk_overworld",
		"from the console's display name the next world must be W3, not W2 again")


func test_a_crack_with_nowhere_to_go_is_announced() -> void:
	GameState.worlds_unlocked = 1
	AutogrindSystem.current_region_id = "Overworld"
	_ctrl._auto_advance_regions = true
	_ctrl._on_region_cracked("Overworld", 1)
	assert_eq(_advanced.size(), 0, "CONTROL: with W2 locked there is nowhere to advance to")
	assert_eq(_in_place.size(), 1, "the crack must be announced when Auto-Advance cannot move the grind")


func test_a_crack_that_can_advance_still_advances() -> void:
	GameState.worlds_unlocked = 2
	AutogrindSystem.current_region_id = "Overworld"
	_ctrl._auto_advance_regions = true
	_ctrl._on_region_cracked("Overworld", 1)
	assert_eq(_advanced.size(), 1, "CONTROL: an open next world must still be advanced to")
	assert_eq(str(_advanced[0][1]) if _advanced.size() > 0 else "", "suburban_overworld", "and it must be W2")
	assert_eq(_in_place.size(), 0, "an advance is not a crack in place")
