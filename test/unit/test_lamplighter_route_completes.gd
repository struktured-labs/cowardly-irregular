extends GutTest

## world3_lamplighters_logic step 2 was STARTABLE AND UNFINISHABLE on main: a custom objective
## advances only via notify_flag, and nothing emitted route_documented anywhere in src/. Clem is
## placed, so a player could accept the quest and never complete it.
##
## The fix is 5 QuestExaminePoints in group mode on Brasston's own `f` gas-lamp tiles. This drives
## the real points rather than pinning their existence: examining 4 must NOT advance the quest, and
## the 5th must. A count-of-points test would pass against a group that fires on the first click.

const BRASSTON := "res://src/maps/villages/BrasstonVillage.gd"
const QUEST := "world3_lamplighters_logic"
const FLAG := "quest_world3_lamplighters_logic_route_documented"

var _saved_quests: Dictionary = {}
var _saved_flags: Dictionary = {}


func before_each() -> void:
	_saved_quests = GameState.quests.duplicate(true)
	_saved_flags = GameState.story_flags.duplicate(true)


func after_each() -> void:
	GameState.quests = _saved_quests
	GameState.story_flags = _saved_flags


func _route_points() -> Array:
	var village = load(BRASSTON).new()
	add_child_autofree(village)
	var out: Array = []
	for n in village.find_children("*", "", true, false):
		if n is QuestExaminePoint and n.flag == FLAG:
			out.append(n)
	return out


func test_five_route_points_exist_and_are_a_group() -> void:
	var pts := _route_points()
	assert_eq(pts.size(), 5, "Clem's route places 5 documentable lamps in Brasston")
	var indices: Array = []
	for p in pts:
		indices.append(p.member_index)
		assert_eq(p.group_size, 5, "every point must know the full group size or the count never completes")
		assert_eq(p.quest_id, QUEST, "points must bind to the lamplighter quest")
	indices.sort()
	assert_eq(indices, [1, 2, 3, 4, 5],
		"member indices must be the exact 1..5 set — a duplicate index makes the group uncompletable: %s" % str(indices))


## The load-bearing one. Group mode must require ALL five; the defect it replaces was a step that
## could never advance, and the obvious wrong fix is one that advances on the first click.
func test_four_lamps_do_not_advance_and_the_fifth_does() -> void:
	var qs := get_node_or_null("/root/QuestSystem")
	assert_not_null(qs, "PRECONDITION: QuestSystem autoload — without it nothing below is real")
	if qs == null:
		return
	for i in range(1, 6):
		GameState.story_flags.erase("%s_%d" % [FLAG, i])
	GameState.story_flags.erase(FLAG)

	var pts := _route_points()
	assert_eq(pts.size(), 5, "PRECONDITION: 5 points to walk")
	if pts.size() != 5:
		return

	# Mark the first four exactly as _examine() does. The RETURN VALUE is what gates notify_flag,
	# so assert on it — an earlier draft asserted the quest flag was unset, which nothing in this
	# path ever sets, so it read as the load-bearing check while being incapable of failing.
	for i in range(4):
		assert_false(pts[i]._group_complete_after_marking(),
			"lamp %d of 5 must NOT report the group complete" % (i + 1))
	assert_eq(pts[0]._group_done(), 4, "four documented lamps must count as four")

	assert_true(pts[4]._group_complete_after_marking(),
		"the fifth lamp completes the group")
	assert_eq(pts[4]._group_done(), 5, "all five count once the last is documented")


func test_control_group_mode_is_off_for_ordinary_examine_points() -> void:
	# CONTROL: the group fields are opt-in. If they defaulted on, every single-point objective in
	# the game would become uncompletable — a far worse bug than the one being fixed.
	var village = load(BRASSTON).new()
	add_child_autofree(village)
	var singles: int = 0
	for n in village.find_children("*", "", true, false):
		if n is QuestExaminePoint and n.flag != FLAG:
			singles += 1
			assert_eq(n.group_size, 0,
				"%s is a single-point objective and must not be in group mode" % n.flag)
	assert_gt(singles, 0, "CONTROL: Brasston has non-route examine points, else this asserts nothing")
