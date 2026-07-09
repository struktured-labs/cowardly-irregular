extends GutTest

## Village-identity fix (2026-07-09): every inn in all 6 worlds was staffed by
## the same Mira with medieval sheets jokes (and Tilly praised "Harmonian
## weave" in the digital world). The TRAVELERS recurring is diegetic — Fen
## lampshades the recursion, Kael/Brix carry the autobattle thesis — but the
## innkeeper is LOCAL: per-world identity via GameState.current_world.

const InnScript := preload("res://src/maps/interiors/InnInterior.gd")


func test_all_six_worlds_have_distinct_innkeepers() -> void:
	var names := {}
	for w in range(1, 7):
		var k: Dictionary = InnScript.INNKEEPERS.get(w, {})
		assert_false(k.is_empty(), "world %d has an innkeeper entry" % w)
		assert_true(k.has("name") and k.has("weave") and k.has("lines"), "world %d entry is complete" % w)
		assert_gt((k["lines"] as Array).size(), 2, "world %d innkeeper has real dialogue" % w)
		names[k["name"]] = true
		# The rest hint must survive every rewrite — the innkeeper is the rest UX anchor.
		var last := str((k["lines"] as Array)[-1]).to_lower()
		assert_true("rest" in last, "world %d innkeeper's last line points at resting" % w)
	assert_eq(names.size(), 6, "all six innkeepers are distinct people")


func test_innkeeper_follows_current_world() -> void:
	var prev: int = GameState.current_world
	var inn = InnScript.new()
	autofree(inn)
	GameState.current_world = 5
	assert_eq(inn._innkeeper()["name"], "HOST-3SS", "W5 gets the hostess unit")
	GameState.current_world = 1
	assert_eq(inn._innkeeper()["name"], "Mira", "W1 keeps Mira")
	GameState.current_world = 99
	assert_eq(inn._innkeeper()["name"], "The Concierge", "out-of-range clamps to W6")
	GameState.current_world = prev


func test_travelers_stay_universal_and_weave_localized() -> void:
	var src := FileAccess.get_file_as_string("res://src/maps/interiors/InnInterior.gd")
	for traveler in ["Scholar Fen", "Kael", "Brix", "Dorian", "Tilly"]:
		assert_true(traveler in src, "%s still haunts every inn (diegetic recursion)" % traveler)
	assert_true("keeper[\"weave\"]" in src,
		"Tilly's carpet provenance must follow the world, not hardcode Harmonian")
	assert_true("You feel like a recursion" in src, "Fen's lampshade survives")
