extends GutTest

## The render smoke entered 14 maps and **thirteen of them were W1**, the fourteenth being one W6
## room (`vertex_apex`). Five shipped worlds had never had a frame taken of them by anything,
## human or automated — so "the render smoke is green" meant "W1 is green", and that was about to
## become a pre-fold gate step.
##
## 🔑 AND EVERY BATTLE IN IT WAS STARTED BY `_start_battle_async`, which bypasses
## `_on_exploration_battle_triggered` and the battle transition entirely. The roamer -> touch ->
## trigger -> transition chain had no pixel or integration coverage at all, and .654's rollback —
## a dismissed intro restarting a finished battle, 15k freed-instance errors — lived in exactly
## that region. A leg that enters a fight the way a player does is the cheap half of that.
##
## ⚠️ WHAT THIS DOES NOT COVER, said plainly rather than left for someone to discover: W4, W5 and
## W6's overworlds still have no leg. The smoke's budget is the wipe leg's and the publish chain's
## `timeout 300`; the W2+W3 legs plus the battle-entry leg measured **+22s on an 87s run (109s
## total, VERDICT PASS)**, and three more worlds would roughly double that addition for frames of
## maps a player reaches late. The gap is deliberate and this file is where to come when someone
## wants to close it.

const SMOKE_FILE := "res://src/GameLoop.gd"


func _smoke_body() -> String:
	var src := FileAccess.get_file_as_string(SMOKE_FILE)
	assert_ne(src, "", "CONTROL: GameLoop.gd must be readable or every arm here is vacuous")
	var at := src.find("func _maybe_run_battle_smoke")
	assert_gt(at, -1, "CONTROL: the render smoke entry point must exist")
	var end := src.find("\nfunc _smoke_", at + 10)
	assert_gt(end, at, "CONTROL: the smoke body ends before its helpers")
	return src.substr(at, end - at)


## ⛔ TWO SHAPES, because my first version found 8 of 14 and the CONTROL below caught it. Six maps
## are entered through a LOOP VARIABLE — `for _vid in [...]: await _smoke_enter_map(_vid)` — so a
## scan for `_smoke_enter_map("literal")` misses every village and interior in those two loops. Same
## class as the cutscene count CLAUDE.md records: an id can be a literal, a loop variable or a const,
## and a derivation that knows one shape reports a confident fraction.
func _entered_maps() -> Array:
	var body := _smoke_body()
	var out: Array = []
	var direct := RegEx.create_from_string('_smoke_enter_map\\("([a-z0-9_]+)"\\)')
	for m in direct.search_all(body):
		if not out.has(m.get_string(1)):
			out.append(m.get_string(1))
	var loops := RegEx.create_from_string('for (\\w+) in \\[([^\\]]*)\\]:')
	var lit := RegEx.create_from_string('"([a-z0-9_]+)"')
	for loop in loops.search_all(body):
		var tail: String = body.substr(loop.get_end())
		if not tail.contains("_smoke_enter_map(%s)" % loop.get_string(1)):
			continue
		for m in lit.search_all(loop.get_string(2)):
			if not out.has(m.get_string(1)):
				out.append(m.get_string(1))
	out.sort()
	return out


func test_the_itinerary_is_derived_and_not_empty() -> void:
	var maps := _entered_maps()
	assert_gt(maps.size(), 10,
		"CONTROL: derived only %d entered maps — the scan is broken and every arm below is free: %s" % [maps.size(), str(maps)])
	gut.p("  smoke itinerary (%d): %s" % [maps.size(), ", ".join(maps)])


## The four legs this change added. Pinned by id because the smoke's own point is the PIXELS of
## these specific maps; a world-count ratchet would go green on any four maps at all.
func test_the_smoke_enters_world_two_and_world_three() -> void:
	var maps := _entered_maps()
	var missing: Array = []
	for required in ["suburban_overworld", "maple_heights_village", "steampunk_overworld", "brasston_village"]:
		if not maps.has(required):
			missing.append(required)
	assert_eq(missing, [],
		"the smoke no longer enters these, so those worlds have no rendered frame again: %s" % ", ".join(missing))


## W1 is still covered — adding worlds must not come at the cost of the world that had the coverage.
func test_world_one_coverage_is_not_traded_away() -> void:
	var maps := _entered_maps()
	for required in ["overworld", "harmonia_village", "whispering_cave"]:
		assert_true(maps.has(required), "W1's '%s' leg is gone" % required)


## The arm that makes the battle-entry leg worth having. A leg that called `_start_battle_async`
## would cover nothing the goblin leg does not already cover; the whole value is that the BATTLE
## ARRIVES BY ITSELF after a physics touch.
func test_the_battle_entry_leg_uses_the_player_path() -> void:
	var src := FileAccess.get_file_as_string(SMOKE_FILE)
	var at := src.find("func _smoke_player_path_battle")
	assert_gt(at, -1, "the player-path battle leg must exist")
	var end := src.find("\nfunc ", at + 10)
	assert_gt(end, at, "CONTROL: the helper ends before the next function")
	var leg := src.substr(at, end - at)

	assert_false(leg.contains("_start_battle_async"),
		"the leg must NOT start the battle itself — then it measures the same path as the goblin leg")
	assert_true(leg.contains("battle_triggered"),
		"it must observe the SCENE's own signal, which is what proves the chain ran")
	assert_true(leg.contains("global_position = roamer.global_position"),
		"the touch must be a real physics overlap, not a handler call")
	assert_true(leg.contains("set_enabled(true)"),
		"the spawner must be re-armed: _smoke_enter_map despawns every roamer, so without this the leg measures an empty map")
	assert_true(leg.contains("_smoke_failed = true"),
		"and a broken player path must FAIL the smoke rather than being reported in prose")


## It must actually be CALLED. A helper that exists and is never reached is the shape that let 44
## cutscenes read as wired when nothing dispatched them.
func test_the_battle_entry_leg_is_reached() -> void:
	var body := _smoke_body()
	assert_true(body.contains("await _smoke_player_path_battle()"),
		"the leg is defined but the smoke never awaits it, so it covers nothing")
