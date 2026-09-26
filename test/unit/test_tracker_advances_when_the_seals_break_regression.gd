extends GutTest

## The floating objective stayed on "Break the four dragon seals" after every seal
## was already broken. The quest log and the minimap both move on — the log's next
## line is the Warden, and the marker walks to the castle — but the banner is
## last-match-wins over a list that jumped from rat_king_defeated straight to
## Mordaine. Beating the four dragons (normal play; the castle will not open
## without them) left the player being told to do the thing they had just done.
## The Warden had the same hole: nothing in the list named castle_warden_defeated,
## so winning that fight still said "break the seals" until Mordaine fell.

const TrackerScript = preload("res://src/exploration/QuestTracker.gd")

const _DRAGONS: Array[String] = [
	"fire_dragon_defeated", "ice_dragon_defeated",
	"lightning_dragon_defeated", "shadow_dragon_defeated",
]

const _LATER: Array[String] = [
	"castle_warden_defeated", "world1_mordaine_defeated",
	"w2_entered", "world2_complete", "w3_entered", "world3_complete",
	"w4_entered", "world4_complete", "w5_entered", "world5_complete", "w6_entered",
]

var _saved_story: Dictionary = {}
var _saved_constants: Dictionary = {}


func before_each() -> void:
	_saved_story = GameState.story_flags.duplicate(true)
	_saved_constants = GameState.game_constants.duplicate(true)


func after_each() -> void:
	GameState.story_flags = _saved_story
	GameState.game_constants = _saved_constants


func _clear_flag(story: Dictionary, flag: String) -> void:
	story[flag] = false
	GameState.game_constants.erase("cutscene_flag_" + flag)
	if GameState.game_constants.get(flag, null) is bool:
		GameState.game_constants.erase(flag)


func _banner(dragon_count: int, warden: bool, mordaine: bool) -> String:
	var story: Dictionary = _saved_story.duplicate(true)
	for flag in _DRAGONS:
		_clear_flag(story, flag)
	for flag in _LATER:
		_clear_flag(story, flag)
	story["rat_king_defeated"] = true
	story["castle_warden_defeated"] = warden
	story["world1_mordaine_defeated"] = mordaine
	GameState.story_flags = story
	var dflags: Dictionary = {}
	for i in mini(dragon_count, _DRAGONS.size()):
		# Dragons land in dungeon_flags, not story_flags. A story-flag-only read stays on the seals line.
		dflags[_DRAGONS[i]] = true
	GameState.game_constants["dungeon_flags"] = dflags
	var host := Node.new()
	add_child_autofree(host)
	var tracker: Node = TrackerScript.new()
	host.add_child(tracker)
	tracker.setup(host)
	return str(tracker._label.text)


func test_rat_king_alone_still_names_the_seals() -> void:
	assert_eq(_banner(0, false, false), "> Break the four dragon seals to open Castle Harmonia",
		"post-Rat-King, before the dragons, the banner must still name the seals")


func test_three_dragons_still_names_the_seals() -> void:
	assert_eq(_banner(3, false, false), "> Break the four dragon seals to open Castle Harmonia",
		"a castle that is still sealed must not announce the Warden")


func test_four_dragons_advances_to_the_warden() -> void:
	assert_eq(_banner(4, false, false), "> Defeat the Chancellor's Warden",
		"all four seals broken opens the castle — the banner must leave the seals line, matching the quest log")


func test_warden_advances_to_mordaine() -> void:
	assert_eq(_banner(4, true, false), "> Confront Chancellor Mordaine in Castle Harmonia",
		"the Warden's defeat is a real flag; the banner must not keep asking for a fight that is over")


func test_mordaine_still_names_the_portal() -> void:
	assert_eq(_banner(4, true, true), "> Enter the portal to the Mundane Sprawl",
		"Mordaine still outranks the castle lines — the portal is the goal only after he falls")
