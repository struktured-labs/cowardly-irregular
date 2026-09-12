extends GutTest

## Stopping autogrind in eight dungeons played W1's peaceful overworld theme.
##
## Two vocabularies name the same places and they are not the same list:
##
##     MAP ids     MapSystem.DUNGEON_MAP_IDS   null_chamber · root_process · …
##     AREA ids    _start_area_music_deferred  abstract_dungeon · digital_dungeon · …
##
## A dungeon scene passes the AREA id on entry (`_get_music_area_id()`), so
## walking in is correct. `_stop_autogrind` passed `_current_map_id` — the MAP
## id — and 8 of the 13 have no match arm, so they reached `_:`, which is
## `_start_overworld_music()`, which is a hardcoded `overworld_medieval`. Not
## the world's overworld bed: World 1's, inside a World 6 dungeon.
##
## 🔑 IT WAS INVISIBLE BECAUSE THE ENTRY PATH IS CORRECT. Every normal way into
## these rooms plays the right music, so the bed is right until the moment a
## grind ends — a state nothing routine revisits. The fix is to ask the scene
## what it wants, which is what the pause-menu teardown already did through
## `_derive_current_scene_music_key()`; two callers wanted the same answer and
## only one of them asked the authority.
##
## ⚠️ SEVERITY DOWNGRADED 2026-09-12, exactly as the arm below asked to be re-read.
## The fall-through IS world-aware now: the dispatcher's `_:` arm composes the
## current world's overworld bed instead of calling `_start_overworld_music`
## directly. So these eight land on the wrong ROOM in the right WORLD — an
## overworld bed inside a dungeon — rather than on World 1's bed inside World 6.
## Still worth guarding, and for the original reason: the entry path is correct, so
## nothing routine revisits the state where it goes wrong. `_start_overworld_music`
## remains a hardcoded `overworld_medieval` and is still the floor when a world has
## no bed of its own; it simply is no longer what the default reaches first.

const GAMELOOP := "res://src/GameLoop.gd"
const SOUNDMANAGER := "res://src/audio/SoundManager.gd"
const MAPSYSTEM := "res://src/maps/MapSystem.gd"


func _src(path: String) -> String:
	var s: String = FileAccess.get_file_as_string(path)
	assert_gt(s.length(), 2000, "SCOPE control: %s read back %d chars" % [path, s.length()])
	return s


## Area ids that _start_area_music_deferred actually matches.
func _area_arms() -> Dictionary:
	var sm: String = _src(SOUNDMANAGER)
	var start: int = sm.find("func _start_area_music_deferred")
	assert_gt(start, 0, "SCOPE control: _start_area_music_deferred not found — it was renamed")
	var end: int = sm.find("\nfunc ", start + 10)
	var block: String = sm.substr(start, end - start)
	var out: Dictionary = {}
	var re := RegEx.new()
	re.compile("\"([a-z0-9_]+)\"")
	for m in re.search_all(block):
		out[m.get_string(1)] = true
	return out


func _dungeon_map_ids() -> Array[String]:
	var ms: String = _src(MAPSYSTEM)
	var start: int = ms.find("DUNGEON_MAP_IDS")
	assert_gt(start, 0, "SCOPE control: DUNGEON_MAP_IDS not found")
	var open_b: int = ms.find("[", start)
	var close_b: int = ms.find("]", open_b)
	var block: String = ms.substr(open_b, close_b - open_b)
	var out: Array[String] = []
	var re := RegEx.new()
	re.compile("\"([a-z0-9_]+)\"")
	for m in re.search_all(block):
		out.append(m.get_string(1))
	return out


func test_control_both_vocabularies_parse() -> void:
	## Every arm below is vacuous if either list comes back empty, and an empty
	## map-id list would read as "no dungeon falls through".
	var arms: Dictionary = _area_arms()
	var ids: Array[String] = _dungeon_map_ids()
	assert_gt(arms.size(), 15, "SCOPE control: parsed %d area arms" % arms.size())
	assert_gt(ids.size(), 8, "SCOPE control: parsed %d dungeon map ids" % ids.size())
	assert_true(arms.has("abstract_dungeon"),
		"CONTROL FAILED: abstract_dungeon is a real arm but was not parsed — the arm reader has drifted")
	assert_true(ids.has("null_chamber"),
		"CONTROL FAILED: null_chamber is in DUNGEON_MAP_IDS but was not parsed")


func test_the_two_vocabularies_still_disagree() -> void:
	## The PREMISE. If someone gives every dungeon map id its own arm, passing
	## the map id becomes harmless and this whole fix can be retired — but that
	## should be a decision, not a silent drift. Fails when the gap closes.
	var arms: Dictionary = _area_arms()
	var without: Array[String] = []
	for id in _dungeon_map_ids():
		if not arms.has(id):
			without.append(id)
	assert_gt(without.size(), 0,
		"every dungeon map id now has a match arm — the map/area vocabulary gap is closed, so _stop_autogrind could pass _current_map_id safely again; retire this guard deliberately rather than leaving it defending nothing")


func test_stop_autogrind_asks_the_scene_not_the_map_id() -> void:
	var gl: String = _src(GAMELOOP)
	var start: int = gl.find("func _stop_autogrind")
	assert_gt(start, 0, "SCOPE control: _stop_autogrind not found")
	var end: int = gl.find("\nfunc ", start + 10)
	var body: String = gl.substr(start, end - start)

	assert_gt(body.find("play_area_music"), 0,
		"SCOPE control: _stop_autogrind no longer restores area music at all — if that moved, re-point this guard rather than deleting it")
	assert_gt(body.find("_derive_current_scene_music_key"), 0,
		"_stop_autogrind does not ask the scene for its music key — passing _current_map_id sends a MAP id to a matcher keyed on AREA ids, and the 8 dungeons without an arm fall through to _start_overworld_music(), which is a hardcoded overworld_medieval")
	assert_eq(body.find("play_area_music(_current_map_id)"), -1,
		"_stop_autogrind passes the raw map id again — this is the exact regression: walking into the dungeon plays the right bed, ending a grind there plays World 1's overworld theme")


## Everything above reads source. This one drives the real SoundManager, because
## a source-shaped guard cannot tell you the two ids SOUND different — and that
## is the whole claim.
var _saved_area: String = ""
var _saved_music: String = ""


func before_each() -> void:
	_saved_area = SoundManager._current_area
	_saved_music = SoundManager._current_music


func after_each() -> void:
	## SoundManager is an autoload shared by the whole suite; leaving it pointed
	## at a dungeon bed would follow later tests around.
	SoundManager.stop_music()
	SoundManager._current_area = _saved_area
	SoundManager._current_music = _saved_music


## ⚠️ `_current_music` IS THE WRONG OBSERVABLE HERE and reading it cost a run:
## play_area_music deliberately CLEARS it (SoundManager:1901 — "play_area_music
## sets _current_area, CLEARS _current_music"), so the probe returned "" for
## both ids and reported them identical. The stream on the player is what the
## player actually hears.
func _resolve(area_id: String) -> String:
	SoundManager._current_area = ""
	SoundManager._current_music = ""
	SoundManager._music_player.stream = null
	SoundManager.play_area_music(area_id)
	await get_tree().process_frame
	await get_tree().process_frame
	var s: Variant = SoundManager._music_player.stream
	if s == null:
		return ""
	return str(s.resource_path).get_file().get_basename()


func test_the_map_id_and_the_area_id_really_do_sound_different() -> void:
	## null_chamber is W6's dungeon. Entering it passes "abstract_dungeon";
	## _stop_autogrind used to pass "null_chamber".
	var by_area: String = await _resolve("abstract_dungeon")
	var by_map: String = await _resolve("null_chamber")

	assert_ne(by_area, "",
		"SCOPE control: the AREA id resolved to no track at all — the probe is not reaching the manifest, so a difference below would be meaningless")
	assert_eq(by_area, "dungeon_abstract",
		"entering Null Chamber should resolve to dungeon_abstract, got '%s'" % by_area)
	assert_eq(by_map, "overworld_abstract",
		"the MAP id should fall through to THIS WORLD's overworld bed, got '%s'. It was overworld_medieval until the default arm became world-aware (2026-09-12); if it is medieval again the default regressed, and if it is dungeon_abstract the arm was added and this guard can retire" % by_map)
	assert_ne(by_area, by_map,
		"the two vocabularies now resolve to the same track, so passing either is safe and this guard can be retired")


func test_the_fallthrough_degrades_by_world_and_the_medieval_floor_remains() -> void:
	## ⛔ THIS ARM USED TO READ `_start_overworld_music` AND WAS ABOUT TO LIE. Its two
	## asserts stayed TRUE after the default became world-aware — that function is
	## untouched and still names overworld_medieval — while its subject, "the
	## fall-through is not world-aware", had become false. Green and misleading,
	## because it pinned the wrong function: the one that plays a bed rather than the
	## one that DECIDES which. Asserting the deciding site instead.
	var sm: String = _src(SOUNDMANAGER)
	var at: int = sm.find("func _start_area_music_deferred")
	assert_gt(at, 0, "SCOPE control: the dispatcher is not there to read")
	var dispatch: String = sm.substr(at, sm.find("\nfunc ", at + 10) - at)
	assert_gt(dispatch.find("_get_current_world_suffix"), 0,
		"the dispatcher's default no longer consults the world suffix — an unrouted key is back to playing World 1's bed in every world, which is the severity this file measures")

	var start: int = sm.find("func _start_overworld_music")
	assert_gt(start, 0, "SCOPE control: _start_overworld_music not found")
	var body: String = sm.substr(start, sm.find("\nfunc ", start + 10) - start)
	assert_gt(body.find("overworld_medieval"), 0,
		"_start_overworld_music no longer names overworld_medieval — it is the floor the world-aware default falls back to when a world has no bed, and without it that floor is gone")
