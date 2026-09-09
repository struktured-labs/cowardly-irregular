extends GutTest

## Changing party formation was KEY_F only, in a game whose stated pillar is controller-first.
##
## MEASURED before building: `cycle_formation()` had exactly one caller — that key. FormationsMenu
## displays formations and cannot set one. Nothing else in src/ assigns current_formation. And every
## button in battle is already bound (Start opens the editor, Select toggles auto, shoulders are
## Defer/Advance, Y/X are speed/repeat, R3 is the help overlay), so this needs a MENU ROW, not a
## binding — the same conclusion the autogrind console reached.
##
## Formation is a STATIC var and persists across battles, so this is a real setting rather than a
## per-fight nicety.

const BCM := "res://src/battle/BattleCommandMenu.gd"
const BS := "res://src/battle/BattleScene.gd"


## The premise. If a second setter ever appears this file is guarding a gap that closed.
func test_the_key_was_the_only_route() -> void:
	var bs := FileAccess.get_file_as_string(BS)
	assert_true(bs.contains("static var current_formation"),
		"formation is static and persists — the thing being made reachable is a real setting")
	var menu := FileAccess.get_file_as_string("res://src/ui/FormationsMenu.gd")
	assert_false(menu.contains("cycle_formation"),
		"CONTROL: FormationsMenu is still read-only, so the command menu is the pad's only route")


## The row must exist AND dispatch. A row that renders and does nothing is this lane's recurring
## defect, so both halves are asserted separately.
func test_the_command_menu_offers_formation() -> void:
	var src := FileAccess.get_file_as_string(BCM)
	assert_true(src.contains('"id": "cycle_formation"'),
		"the battle command menu must offer a formation row — a pad had no route at all")
	var at := src.find('if item_id == "cycle_formation":')
	assert_gt(at, -1, "and the selection handler must have an arm for it, or the row does nothing")
	var body := src.substr(at, 300)
	assert_true(body.contains("cycle_formation()"),
		"the arm must call the SAME function KEY_F calls, so key and menu cannot drift")


## It must not eat the turn. KEY_F does not, and a formation change that costs a turn is a
## different feature from the one being made reachable.
func test_choosing_formation_reopens_the_menu() -> void:
	var src := FileAccess.get_file_as_string(BCM)
	var at := src.find('if item_id == "cycle_formation":')
	var body := src.substr(at, 300)
	assert_true(body.contains("show_win98_command_menu"),
		"formation costs no turn, so the menu must come back or the turn has no input surface")
	assert_true(body.contains("call_deferred"),
		"deferred, for the same re-entrancy reason as the Trust OFF path it copies")


## Behavioural: the label must read the LIVE formation, and the static must be reachable the way
## the row reads it. Static-through-instance is the part worth exercising rather than assuming.
func test_the_live_formation_is_readable_the_way_the_row_reads_it() -> void:
	var BSClass = load(BS)
	var names: Array = BSClass.FORMATION_NAMES
	assert_gt(names.size(), 1, "there must be several formations, else cycling is meaningless")
	var idx: int = BSClass.current_formation
	assert_true(idx >= 0 and idx < names.size(),
		"the live formation index must be in range — the row indexes FORMATION_NAMES with it")
	assert_ne(str(names[idx]), "", "and resolve to a printable name")
