class_name CastleFloor
extends RefCounted
## Build Castle Harmonia ON A NAMED FLOOR, and put GameState back afterwards.
##
## ⛔ WITHOUT THIS, A CASTLE ARM MEASURES WHATEVER FLOOR AN EARLIER TEST LEFT BEHIND.
## `DragonCave._ready` restores `current_floor` from `GameState.game_constants["<cave_id>_floor"]`,
## so the floor is cross-test state. Measured on the examine guard: floor 1 run alone, floor 2
## inside the full sweep. Two consequences, and the second is the expensive one:
##
##   · floor 4 is authored BARE, so a leak to 4 reds a control instead of the subject
##   · an arm that measures ONE floor is SILENT about a loss on any other — measured, EC=0 7/7,
##     with a floor-3 NPC's placement deleted outright
##
## ⚠️ `boss_defeated` is reset too, because `DragonCave` forces floor 1 once the boss is dead —
## a sweep that beats Mordaine would otherwise pin every call here to floor 1 and look correct.
##
## 🔑 Shared rather than copied: the whole value is that the restore is right, and two copies of a
## state-restoring fixture is two chances to leak GameState into tests that never named a floor.

const FLOOR_KEY := "castle_harmonia_floor"
const BOSS_FLAG := "world1_mordaine_defeated"
const CASTLE := "res://src/maps/dungeons/CastleHarmonia.gd"


static func _gs() -> Node:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null("GameState")


## Call in before_each; hand the result back to restore() in after_each.
static func snapshot() -> Dictionary:
	var gs := _gs()
	if gs == null:
		return {"absent": true}
	var flags: Dictionary = gs.game_constants.get("dungeon_flags", {})
	return {
		"absent": false,
		"had_floor": gs.game_constants.has(FLOOR_KEY),
		"floor": int(gs.game_constants.get(FLOOR_KEY, 0)),
		"had_flag": flags.has(BOSS_FLAG),
		"flag": flags.get(BOSS_FLAG, null),
	}


static func restore(snap: Dictionary) -> void:
	if bool(snap.get("absent", true)):
		return
	var gs := _gs()
	if gs == null:
		return
	if bool(snap.get("had_floor", false)):
		gs.game_constants[FLOOR_KEY] = int(snap.get("floor", 1))
	else:
		gs.game_constants.erase(FLOOR_KEY)
	var flags: Dictionary = gs.game_constants.get("dungeon_flags", {})
	if bool(snap.get("had_flag", false)):
		flags[BOSS_FLAG] = snap.get("flag", false)
	else:
		flags.erase(BOSS_FLAG)


## `t` is the calling GutTest, so the viewport is freed with its test rather than at exit.
static func build(t, floor_num: int) -> Node:
	var gs := _gs()
	if gs != null:
		gs.game_constants[FLOOR_KEY] = floor_num
		var flags: Dictionary = gs.game_constants.get("dungeon_flags", {})
		flags[BOSS_FLAG] = false
		gs.game_constants["dungeon_flags"] = flags
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.world_2d = World2D.new()
	t.add_child_autofree(vp)
	var castle = load(CASTLE).new()
	vp.add_child(castle)
	var tree := Engine.get_main_loop() as SceneTree
	await tree.physics_frame
	await tree.physics_frame
	return castle
