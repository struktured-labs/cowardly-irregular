extends GutTest

## A room's music must follow the MAP it is in, not the bed that happened to be
## playing when the player arrived.
##
## An `interior_*` key with no authored bed inherits whatever is already playing
## (SoundManager:4910) — correct walking in from the village, which is where the
## behaviour was designed and where it stays. Wrong on a teleport: TeleportMenu
## lists `scriptura_guild` and `scriptura_bookshop` as direct destinations, so
## arriving from the World 4 overworld left `overworld_industrial.ogg` playing
## inside a World 1 guild. Measured 2026-09-12 before the fix:
##
##     play_area_music("overworld_industrial")  -> overworld_industrial.ogg
##     play_area_music("interior_scriptorium")  -> overworld_industrial.ogg   ⛔
##
## 🔑 THIS IS THE AUDIO HALF OF A TWO-PART FIX and it is independent by design.
## cowir-adhoc's `_map_id_declares_its_world` repairs GameState.current_world, which
## was ALSO reporting 4 in that room. SoundManager reads none of that — its suffix
## cache has one writer, play_area_music, which is why the audio symptom survived
## their fix. So this file asserts the audio FOLLOWS the declared world and sets
## that world itself; their guard asserts the declared world is right. Composed, the
## player hears World 1. Neither test depends on the other's branch.
##
## The world→suffix vocabulary is WeatherSystem.WORLD_IDS, reused rather than
## re-derived — SoundManager's own header exists to stop a fourth copy of it.

## ⚠️ THE AREA KEY, NOT THE MAP ID. Every overworld scene passes the legacy
## `overworld_<world>` form; the canonical `<world>_overworld` map id has no arm in
## _start_area_music_deferred and plays overworld_medieval (the 8-of-13 class named at
## GameLoop:5616, translated there by _derive_current_scene_music_key). I wrote the
## canonical form into this file's first draft and its own control caught it.
const ROOM := "interior_scriptorium"
var _saved_world: int = 1


func before_each() -> void:
	_saved_world = int(GameState.current_world)
	SoundManager.stop_music()


func after_each() -> void:
	GameState.current_world = _saved_world
	SoundManager.stop_music()


func _stream() -> String:
	var s: AudioStream = SoundManager._music_player.stream
	return s.resource_path if s != null else "<none>"


func test_control_the_world_four_leg_really_plays_world_four() -> void:
	## Without this the arm below could pass because the first leg never started.
	GameState.current_world = 4
	SoundManager.play_area_music("overworld_industrial")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_stream(), "res://assets/audio/music/overworld_industrial.ogg",
		"PREMISE FAILED: the W4 overworld leg played %s" % _stream())


func test_a_teleport_into_a_world_one_room_leaves_world_four_behind() -> void:
	GameState.current_world = 4
	SoundManager.play_area_music("overworld_industrial")
	await get_tree().process_frame
	await get_tree().process_frame

	## What the teleport does: the map id declares World 1 before the room's _ready
	## asks for music.
	GameState.current_world = 1
	SoundManager.play_area_music(ROOM)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_ne(_stream(), "res://assets/audio/music/overworld_industrial.ogg",
		"a World 1 room is still playing World 4's overworld bed after a teleport")
	assert_eq(SoundManager._current_world_suffix, "medieval",
		"the room reports world suffix '%s', so a battle there would use the wrong world's bed too" % SoundManager._current_world_suffix)


func test_the_same_room_entered_from_its_own_village_still_inherits() -> void:
	## The behaviour that was always right, and the one a fix could easily break:
	## a room with no authored bed keeps the village's music rather than restarting
	## it or dropping to a generic world bed.
	GameState.current_world = 1
	SoundManager.play_area_music("scriptura_village")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_stream(), "res://assets/audio/music/village_scriptura.ogg",
		"PREMISE FAILED: the village leg played %s" % _stream())

	SoundManager.play_area_music(ROOM)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_stream(), "res://assets/audio/music/village_scriptura.ogg",
		"the guild stopped inheriting Scriptura's bed — an unauthored room should keep its village's music, not restart or swap it")


func test_an_unknowable_world_keeps_the_older_inherit_behaviour() -> void:
	## The fix must not GUESS. With no usable world the room inherits as before,
	## which is the same reasoning three lanes applied to pad glyphs tonight: a
	## default that looks like an answer is worse than declining to answer.
	GameState.current_world = 1
	SoundManager.play_area_music("scriptura_village")
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.current_world = 0
	SoundManager.play_area_music(ROOM)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_stream(), "res://assets/audio/music/village_scriptura.ogg",
		"with an out-of-range world the room should inherit as it always did, not fall to a guessed bed")

func test_an_unauthored_room_inherits_even_when_the_suffix_cache_has_lagged() -> void:
	## ⛔ REGRESSION, and it was mine. The same-world check first compared the room's
	## world to the raw `_current_world_suffix` CACHE, which has one writer and can name
	## a world the player already left. So inheriting depended on ambient state:
	## test_interior_music_routing::test_inherit_on_missing_keeps_current_area passed
	## alone and FAILED inside a 58-file batch (@cowir-adhoc, 2026-09-12), because an
	## earlier test had left the cache on another world. Measured with the setup that
	## test uses plus the state it does not set:
	##
	##     cache "industrial", GameState 1  ->  _current_area became the ROOM   ⛔
	##     cache "medieval",   GameState 1  ->  stayed "village"                ✅
	##
	## An intermittent red is the symptom; the defect is that an unauthored room would
	## cut the village bed and restart it whenever the cache lagged. Comparing against
	## _get_current_world_suffix() reads the area actually being left and falls back to
	## the cache only when that area has no arm.
	SoundManager._current_area = "village"
	SoundManager._music_playing = true
	SoundManager._current_world_suffix = "industrial"
	GameState.current_world = 1

	SoundManager.play_area_music("interior_zz_unauthored_room")

	assert_eq(SoundManager._current_area, "village",
		"an unauthored room stopped inheriting because the suffix CACHE named another world — the bed the player is hearing belongs to _current_area, which is what the comparison must resolve")
