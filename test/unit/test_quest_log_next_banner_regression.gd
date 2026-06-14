extends GutTest

## Regression: Quest Log "Next:" banner surfaces the active objective at the
## top of the screen so players don't have to scan past completed chapters
## to figure out what to do next. Addresses recurring user feedback:
## "I can't figure out what the hell to actually do."

const QUEST_LOG_PATH := "res://src/ui/QuestLog.gd"

# Story flags we touch so we can restore state cleanly between tests.
# These are the EXACT flags QuestLog.CHAPTERS objectives gate on. The W2-W5
# portal objectives now read the REAL written flags (w2_dungeon_cleared ..
# w5_dungeon_cleared, set by SuburbanUnderground / SteampunkMechanism /
# AssemblyCore / RootProcess on dungeon clear), NOT the old phantom
# w2_boss_defeated .. w5_boss_defeated flags that were never written.
const _TOUCHED_FLAGS := [
	"prologue_complete",
	"chapter1_complete",
	"chapter2_complete",
	"chapter3_complete",
	"rat_king_defeated",
	"w1_boss_defeated",
	"w2_entered",
	"w2_dungeon_cleared",
	"w3_entered",
	"w3_dungeon_cleared",
	"w4_entered",
	"w4_dungeon_cleared",
	"w5_entered",
	"w5_dungeon_cleared",
	"w6_entered",
]

var _saved_flags: Dictionary = {}


func before_each() -> void:
	_saved_flags.clear()
	if GameState:
		for flag in _TOUCHED_FLAGS:
			_saved_flags[flag] = GameState.get_story_flag(flag)
			GameState.set_story_flag(flag, false)


func after_each() -> void:
	if GameState:
		for flag in _TOUCHED_FLAGS:
			GameState.set_story_flag(flag, _saved_flags.get(flag, false))


func _stand_up_quest_log() -> Node:
	var script = load(QUEST_LOG_PATH)
	var ql = script.new()
	add_child_autofree(ql)
	ql._build_ui()
	return ql


func _find_node_recursive(root: Node, target_name: String) -> Node:
	if root.name == target_name:
		return root
	for child in root.get_children():
		var found = _find_node_recursive(child, target_name)
		if found:
			return found
	return null


func test_next_banner_appears_at_game_start() -> void:
	# Fresh game — no flags set. First real objective should be "Speak with
	# Elder Theron in Harmonia" (the first non-empty-flag objective in Ch1).
	var ql = _stand_up_quest_log()
	var banner = _find_node_recursive(ql, "NextBanner") as Label
	assert_not_null(banner, "Quest Log must render NextBanner for active objective")
	if banner:
		assert_true(banner.text.find("Speak with Elder Theron") > -1,
			"Banner should point to first incomplete Ch1 objective, got: '%s'" % banner.text)
		assert_true(banner.text.find("Next:") > -1,
			"Banner should be prefixed with 'Next:' so the player knows it's actionable")


func test_next_banner_advances_as_flags_complete() -> void:
	# Player has finished prologue + chapter1 + chapter2. Next objective
	# should be "Descend deeper into the Whispering Cave".
	GameState.set_story_flag("prologue_complete", true)
	GameState.set_story_flag("chapter1_complete", true)
	var ql = _stand_up_quest_log()
	var banner = _find_node_recursive(ql, "NextBanner") as Label
	assert_not_null(banner, "Quest Log must render NextBanner after progress")
	if banner:
		assert_true(banner.text.find("Descend deeper into the Whispering Cave") > -1,
			"Banner must reflect the FIRST INCOMPLETE objective, got: '%s'" % banner.text)


func test_next_banner_jumps_into_unlocked_chapter() -> void:
	# Player has completed all of Ch1 and unlocked w2. Banner should point
	# to the Ch2 first objective.
	for flag in ["prologue_complete", "chapter1_complete", "chapter2_complete",
		"chapter3_complete", "rat_king_defeated", "w1_boss_defeated", "w2_entered"]:
		GameState.set_story_flag(flag, true)
	var ql = _stand_up_quest_log()
	var banner = _find_node_recursive(ql, "NextBanner") as Label
	assert_not_null(banner, "Banner must appear when Ch2 is unlocked")
	if banner:
		# Ch2's first objective is "Explore the suburban neighborhood" but its
		# flag (w2_entered) is already set, so the next incomplete one is
		# "Find the portal to the Clockwork Dominion" (w2_dungeon_cleared).
		assert_true(banner.text.find("Clockwork Dominion") > -1,
			"Banner must skip already-complete Ch2 objectives, got: '%s'" % banner.text)


func test_next_banner_hidden_when_all_complete() -> void:
	# Set every flag the quest log knows about. Banner must NOT render.
	for flag in _TOUCHED_FLAGS:
		GameState.set_story_flag(flag, true)
	var ql = _stand_up_quest_log()
	var banner = _find_node_recursive(ql, "NextBanner")
	assert_null(banner,
		"NextBanner must be absent when no incomplete objectives remain")
