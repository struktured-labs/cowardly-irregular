extends GutTest

## The Calibrant's arena opens only once a trial has been passed, and gating it must never strand
## the player. Those are two claims and the second is the one with no loud direction of its own:
## "the Apex door is absent" looks identical whether the gate fired or the world built no doors at
## all, so every absence arm here is paired with a presence arm from the same fixture.
##
## The gate is a plain absence rather than a locked door BECAUSE the Antechamber is the signpost:
## at world6_chapter3 it is the only way forward, and the Apex appears beside it after the trial.
## If the Antechamber door could ever be missing while the Apex one is gated, the game's ending
## would be unreachable with nothing on screen saying why — which is what test_no_dead_end pins.

const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const WORLD := preload("res://src/exploration/AbstractOverworld.gd")
const ANTE := preload("res://src/maps/dungeons/VertexAntechamber.gd")

## ⛔ EVERY ARM HERE TURNS A FLAG **OFF**, and set_story_flag writes story_flags ONLY while
## is_story_flag_set unions FOUR namespaces. So a leaked cutscene_flag_* or bare constant from any
## earlier test makes an off-arm red — a flake, not a false pass, but one whose cause reads as my
## gate rather than as somebody else's teardown. These save and clear all four per flag.
const GATED_FLAGS := ["world6_chapter3_complete", "w6_trial_passed", "vertex_antechamber_cleared"]

var _priors: Dictionary = {}


func before_each() -> void:
	_priors = {}
	for f in GATED_FLAGS:
		_priors[f] = _snapshot(str(f))
		_force_off(str(f))


func after_each() -> void:
	for f in GATED_FLAGS:
		_restore(str(f), _priors.get(f, {}))
	SoundState.restore()


func _dungeon_flags() -> Dictionary:
	if not GameState.game_constants.has("dungeon_flags"):
		GameState.game_constants["dungeon_flags"] = {}
	return GameState.game_constants["dungeon_flags"]


## null means "the key was absent", which restore must reproduce — writing `false` back would leave
## a key the tree never had, and the next reader cannot tell an authored false from a planted one.
func _snapshot(flag: String) -> Dictionary:
	return {
		"story": GameState.story_flags.get(flag, null),
		"cutscene": GameState.game_constants.get("cutscene_flag_" + flag, null),
		"bare": GameState.game_constants.get(flag, null),
		"dungeon": _dungeon_flags().get(flag, null),
	}


func _force_off(flag: String) -> void:
	GameState.story_flags[flag] = false
	GameState.game_constants.erase("cutscene_flag_" + flag)
	GameState.game_constants.erase(flag)
	_dungeon_flags().erase(flag)


func _restore(flag: String, prior: Dictionary) -> void:
	_put(GameState.story_flags, flag, prior.get("story", null))
	_put(GameState.game_constants, "cutscene_flag_" + flag, prior.get("cutscene", null))
	_put(GameState.game_constants, flag, prior.get("bare", null))
	_put(_dungeon_flags(), flag, prior.get("dungeon", null))


func _put(store: Dictionary, key: String, value: Variant) -> void:
	if value == null:
		store.erase(key)
	else:
		store[key] = value


func _set_dungeon_flag(on: bool) -> void:
	_dungeon_flags()["vertex_antechamber_cleared"] = on


## The flag the Antechamber itself declares, read off the room rather than retyped. A rename on
## either side then reds instead of silently ungating the Apex.
func _declared_trial_flag() -> String:
	var ante = ANTE.new()
	var flag: String = str(ante.unlock_story_flag)
	ante.free()
	return flag


func _world() -> Node:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child_autofree(vp)
	var world = WORLD.new()
	vp.add_child(world)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return world


func _door(world: Node, map_id: String) -> Node:
	var transitions: Node = world.get_node_or_null("Transitions")
	if transitions == null:
		return null
	for child in transitions.get_children():
		if child is AreaTransition and str(child.target_map) == map_id:
			return child
	return null


func _door_count(world: Node) -> int:
	var transitions: Node = world.get_node_or_null("Transitions")
	return 0 if transitions == null else transitions.get_child_count()


## ONE victory writes TWO DIFFERENT NAMES — unlock_story_flag into story_flags and boss_flag_key
## into dungeon_flags — so is_story_flag_set's union cannot make either answer for the other. Both
## names are therefore pinned to the room that declares them, or the gate reads a flag nothing sets.
func test_the_antechamber_declares_both_flags_this_gate_reads() -> void:
	var ante = ANTE.new()
	var story_name: String = str(ante.unlock_story_flag)
	var dungeon_name: String = str(ante.boss_flag_key)
	ante.free()
	assert_eq(story_name, "w6_trial_passed",
		("AbstractOverworld gates the Apex on a literal 'w6_trial_passed'; this is the " +
		 "unlock_story_flag that writes it. Disagreement means the Apex is gated on a flag " +
		 "nothing sets, and the game's ending is unreachable"))
	assert_eq(dungeon_name, "vertex_antechamber_cleared",
		("the gate's second accepted name. These are DIFFERENT names, not one name in two " +
		 "namespaces, which is why the gate ORs them rather than relying on the union read"))
	assert_ne(story_name, dungeon_name,
		"CONTROL: if these ever became the same string, the OR above would stop being a second route")


func test_an_untested_party_cannot_reach_the_apex() -> void:
	GameState.set_story_flag("world6_chapter3_complete", true)
	var world = await _world()
	assert_gt(_door_count(world), 1,
		"ANTI-VACUITY: the overworld built %d doors — an empty Transitions node makes every absence below free" % _door_count(world))
	assert_null(_door(world, "vertex_apex"),
		"with the Question asked but no trial passed, the Apex door must not exist")


## ⛔ THE ARM THE FEATURE IS FOR. An absence is only a gate if something else is still open.
func test_no_dead_end_while_the_apex_is_gated() -> void:
	GameState.set_story_flag("world6_chapter3_complete", true)
	var world = await _world()
	assert_null(_door(world, "vertex_apex"),
		"CONTROL: the Apex must be gated in this state, or this arm is not about a gated world")
	assert_not_null(_door(world, "vertex_antechamber"),
		("the Apex is gated and the Antechamber is the only way to open it, so its door MUST be " +
		 "present here. Absent, the endgame is unreachable with nothing on screen explaining why"))


func test_passing_the_trial_opens_the_apex() -> void:
	GameState.set_story_flag("world6_chapter3_complete", true)
	GameState.set_story_flag(_declared_trial_flag(), true)
	var world = await _world()
	assert_not_null(_door(world, "vertex_apex"),
		"with the Question asked and the trial passed, the Apex door must exist")
	assert_not_null(_door(world, "vertex_antechamber"),
		"the Antechamber stays reachable after the trial — nothing in its gate is one-shot")


## The arm above opens the Apex with the STORY name. This one uses only the DUNGEON name — the other
## half of the same victory spec — and is the arm that fails if the gate reads one route and not both.
func test_either_half_of_one_victory_opens_the_apex() -> void:
	GameState.set_story_flag("world6_chapter3_complete", true)
	_set_dungeon_flag(true)
	assert_false(bool(GameState.story_flags.get("vertex_antechamber_cleared", false)),
		"CONTROL: this arm must set the dungeon_flags namespace ONLY, or it re-tests the story flag")
	var world = await _world()
	assert_not_null(_door(world, "vertex_antechamber"),
		"CONTROL: the Antechamber door is the signpost and must be present whatever the trial state")
	assert_not_null(_door(world, "vertex_apex"),
		("vertex_antechamber_cleared is set in game_constants['dungeon_flags'] — the namespace " +
		 "DragonCave:1128 writes — and the Apex stayed shut. The two flag NAMES differ, so no " +
		 "union read makes w6_trial_passed answer for this one: the gate has to accept both, or a " +
		 "save carrying only this half has no door to the ending and nothing explaining why"))


## before_each leaves world6_chapter3_complete off in all four namespaces, so this arm only has to
## turn the trial flag ON — the state a save could reach by a debug toggle or a migration.
func test_the_question_still_gates_both_rooms() -> void:
	GameState.set_story_flag(_declared_trial_flag(), true)
	var world = await _world()
	assert_gt(_door_count(world), 0,
		"ANTI-VACUITY: no doors at all means this arm cannot tell a gate from an empty world")
	assert_null(_door(world, "vertex_apex"),
		"the trial flag must not bypass world6_chapter3 — the Apex needs BOTH")
	assert_null(_door(world, "vertex_antechamber"),
		"the Antechamber is gated on the Question too, so a stray trial flag cannot reveal it early")
