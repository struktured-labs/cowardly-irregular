extends GutTest

## Walking into a shop must not change which WORLD you are in.
##
## `GameState.current_world` is synced in `_set_current_map_id` from
## `_get_world_for_map(id)`, which is prefix-matching: "suburban_" -> W2,
## "brasston" -> W3, and everything unrecognised -> W1. That works for
## overworlds, the five named villages and every dungeon.
##
## It cannot work for interiors. `INTERIOR_MAP_IDS` holds ids the const's own
## comment describes as "generic village-scene interiors reused across all 11
## villages" — `inn_interior`, `shop_interior_item`, `shop_interior_blacksmith`
## and the rest. One id, eleven villages, six worlds: no prefix can carry the
## world, so every one of them resolved to W1.
##
## Measured before the fix: entering the inn in Brasston (W3) set current_world
## to 1 and leaving set it back to 3. That was survivable while current_world
## only fed the game-over title and LLM context. It stops being survivable the
## moment per-world party sheets read it — the party changes out of their
## steampunk clothes to buy a potion and changes back on the way out, while the
## music stays steampunk, because SoundManager's fallback arm returns the CACHED
## suffix and so carries the village's world into the room correctly.
##
## Two resolvers, one question, and in a room neither can name, persistence was
## right and a default was wrong.
##
## The fix derives the world from `_village_origin_id` — the origin GameLoop
## already captures so interior exits can route back. This asserts the
## RELATIONSHIP (inside an interior you are in the world you came from), never a
## coordinate: it stays correct when villages are renamed or worlds are added.

var _gl: Node = null
var _saved_world: int = 1
var _saved_map_id = null

## Each must derive a DISTINCT world, so a renamed village fails loudly here
## rather than silently testing world 1 six times over.
const ORIGINS := {
	"harmonia_village": 1,
	"maple_heights_village": 2,
	"brasston_village": 3,
	"rivet_row_village": 4,
	"node_prime_village": 5,
	"vertex_village": 6,
}


func before_each() -> void:
	_gl = load("res://src/GameLoop.gd").new()
	_saved_world = int(GameState.current_world) if GameState else 1
	_saved_map_id = MapSystem.current_map_id if MapSystem and "current_map_id" in MapSystem else null


func after_each() -> void:
	if _gl != null:
		_gl.free()
		_gl = null
	if GameState:
		GameState.current_world = _saved_world
	if MapSystem and "current_map_id" in MapSystem and _saved_map_id != null:
		MapSystem.current_map_id = _saved_map_id


## The premise. If prefix matching ever learns about interiors on its own this
## goes red, and the fix below becomes redundant rather than silently duplicated.
func test_the_raw_derivation_really_is_world_blind_for_shared_interiors() -> void:
	var blind: Array = []
	for id in _gl.INTERIOR_MAP_IDS:
		if _gl._get_world_for_map(str(id)) == 1:
			blind.append(str(id))
	assert_gt(blind.size(), 0,
		"no interior id resolves to W1 by prefix — the hole this file guards is gone, and every assertion below is now vacuous")
	assert_true("inn_interior" in blind,
		"inn_interior is the canonical shared room (one id, all 11 villages); if it is no longer world-blind the premise changed")


## The control the fix cannot supply for itself: the origin set must actually
## span worlds, or "the world came out right" means nothing.
func test_the_origin_villages_span_six_distinct_worlds() -> void:
	var seen := {}
	for v in ORIGINS:
		var w: int = _gl._get_world_for_map(v)
		assert_eq(w, int(ORIGINS[v]),
			"%s derives W%d, expected W%d — a renamed village would otherwise make every case below test world 1" % [v, w, int(ORIGINS[v])])
		seen[w] = true
	assert_eq(seen.size(), 6, "the six origins cover six distinct worlds")


## The invariant: inside an interior you are in the world you entered from.
func test_entering_any_interior_preserves_the_villages_world() -> void:
	var interiors: PackedStringArray = _gl.INTERIOR_MAP_IDS
	assert_gt(interiors.size(), 0, "interior corpus is non-empty — zero would pass this for free")

	var checked := 0
	var offenders: Array = []
	for village in ORIGINS:
		var expected: int = int(ORIGINS[village])
		for raw in interiors:
			var interior := str(raw)
			_gl._village_origin_id = village
			_gl._set_current_map_id(interior)
			checked += 1
			var got: int = int(GameState.current_world)
			if got != expected:
				offenders.append("%s -> %s gave W%d, expected W%d" % [village, interior, got, expected])

	assert_eq(checked, ORIGINS.size() * interiors.size(),
		"drove every origin x interior pair — a short count means the loop died partway and the rest were never tested")
	assert_true(offenders.is_empty(),
		"%d of %d interior entries reported the wrong world:\n  %s" % [
			offenders.size(), checked, "\n  ".join(offenders)])


## Leaving restores the village's own world, and the origin is not consumed —
## a player who visits the inn twice must not end up in world 1 the second time.
func test_leaving_and_re_entering_is_stable() -> void:
	_gl._village_origin_id = "brasston_village"
	_gl._set_current_map_id("inn_interior")
	assert_eq(int(GameState.current_world), 3, "inside the Brasston inn, still W3")
	_gl._set_current_map_id("brasston_village")
	assert_eq(int(GameState.current_world), 3, "back outside, still W3")
	_gl._set_current_map_id("inn_interior")
	assert_eq(int(GameState.current_world), 3, "second visit is W3 too — the origin was not consumed")


## With no origin recorded there is nothing to derive from, so the id-based
## answer stands. Pinned so the fallback is a decision rather than an accident.
func test_no_recorded_origin_falls_back_to_the_id_derivation() -> void:
	_gl._village_origin_id = ""
	_gl._set_current_map_id("inn_interior")
	assert_eq(int(GameState.current_world), 1,
		"no origin captured — the shared id carries no world, so W1 is the only available answer")
