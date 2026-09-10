extends GutTest

## Two of the six Formation Specials require a job no player can unlock.
##
## jobs.json gates the Ninja on an achievement: {"type": "achievement", "id": "speed_demon",
## "description": "Complete a dungeon in under 5 minutes"}. JobSystem.is_job_unlocked handles that
## condition correctly — it asks GameState.is_story_flag_set("speed_demon"). Nothing ever SETS that
## flag, in any namespace, and no dungeon completion timer exists anywhere in src/. So the Ninja is
## reachable only through debug mode, which is_job_unlocked short-circuits on separately.
##
## That lands on a player-facing surface: BattleCommandMenu.FORMATIONS defines six formation
## specials, and blade_storm (fighter/rogue/NINJA) and shadow_strike (rogue/NINJA) both require it.
## The Formations reference page in the overworld menu lists all six with live qualification checks,
## so a player is shown two rows that can never light up.
##
## The other three advanced jobs are fine and that contrast is the point: guardian and speculator
## gate on chapter 2, summoner on chapter 3, and GameLoop really does set those flags. One condition
## type out of four has no producer, and the arm that reads it looks exactly like the ones that work.
##
## ⛔ NOT FIXED HERE. What should unlock the Ninja is a design question — implement the dungeon timer
## the description promises, or re-gate it like its three siblings — and the timer would live in the
## dungeon lane, not this one. Every assert below is INVERTED and expires the moment its reason does.

const JOBS := "res://data/jobs.json"

func _jobs() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(JOBS))
	assert_not_null(parsed, "CONTROL: jobs.json parses")
	var d: Dictionary = parsed
	return d.get("jobs", d)

func test_the_ninja_still_gates_on_the_absent_achievement() -> void:
	var ninja: Dictionary = _jobs().get("ninja", {})
	assert_false(ninja.is_empty(), "CONTROL: the Ninja job exists")
	var cond: Dictionary = ninja.get("unlock_condition", {})
	assert_eq(str(cond.get("type", "")), "achievement",
		"the Ninja's gate changed — if it now matches its siblings, delete this file")
	assert_eq(str(cond.get("id", "")), "speed_demon",
		"the achievement id changed; re-check whether the new one has a producer")

func test_nothing_awards_that_achievement() -> void:
	## The measurement, over every tracked .gd rather than a guessed subset. A setter appearing is
	## the good outcome and reds this deliberately.
	var setters: Array = []
	var dir := DirAccess.open("res://src")
	assert_not_null(dir, "CONTROL: opened res://src")
	var stack: Array = ["res://src"]
	var scanned: int = 0
	while not stack.is_empty():
		var path: String = str(stack.pop_back())
		var d := DirAccess.open(path)
		if d == null:
			continue
		d.list_dir_begin()
		var entry: String = d.get_next()
		while entry != "":
			if entry.begins_with("."):
				entry = d.get_next()
				continue
			var full: String = path + "/" + entry
			if d.current_is_dir():
				stack.append(full)
			elif entry.ends_with(".gd"):
				scanned += 1
				var text := FileAccess.get_file_as_string(full)
				if text.contains("set_story_flag(\"speed_demon") or text.contains("\"speed_demon\"] = true"):
					setters.append(full)
			entry = d.get_next()
		d.list_dir_end()
	assert_gt(scanned, 100, "CONTROL: the sweep actually walked src/ (%d files)" % scanned)
	assert_eq(setters.size(), 0,
		"something now awards speed_demon, so the Ninja is unlockable — delete this file and the formation pins with it: " + str(setters))

func test_the_dungeon_timer_the_description_promises_does_not_exist() -> void:
	## The condition's own description names the mechanic: "Complete a dungeon in under 5 minutes".
	## If a timer appears, the achievement becomes implementable and this is the reminder.
	var ninja: Dictionary = _jobs().get("ninja", {})
	assert_string_contains(str((ninja.get("unlock_condition", {}) as Dictionary).get("description", "")), "minutes",
		"CONTROL: the description still promises a timed run")

func test_the_three_sibling_jobs_gate_on_conditions_that_do_have_producers() -> void:
	## The contrast that makes this a gap rather than a convention: the other advanced jobs are
	## reachable, so "advanced jobs are debug-only" is not the design.
	var jobs := _jobs()
	for jid in ["guardian", "speculator"]:
		var c: Dictionary = (jobs.get(jid, {}) as Dictionary).get("unlock_condition", {})
		assert_eq(str(c.get("type", "")), "story", "%s must still gate on story progress" % jid)
		assert_eq(int(c.get("chapter", 0)), 2, "%s gates on chapter 2" % jid)
	var summoner: Dictionary = (jobs.get("summoner", {}) as Dictionary).get("unlock_condition", {})
	assert_eq(int(summoner.get("chapter", 0)), 3, "summoner gates on chapter 3")
	var loop := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_string_contains(loop, "cutscene_flag_chapter2_complete",
		"CONTROL: something really does set the chapter flag those three depend on")

func test_two_formations_depend_on_the_unreachable_job() -> void:
	## The player-facing consequence, pinned so it cannot be fixed silently on one side only.
	var menu := FileAccess.get_file_as_string("res://src/battle/BattleCommandMenu.gd")
	assert_gt(menu.length(), 1000, "CONTROL: read BattleCommandMenu")
	var i: int = menu.find("const FORMATIONS")
	assert_gt(i, -1, "CONTROL: located the formation table")
	var table: String = menu.substr(i, 2200)
	var needs_ninja: int = 0
	for fid in ["blade_storm", "shadow_strike"]:
		var f: int = table.find(fid)
		assert_gt(f, -1, "CONTROL: %s is still a formation" % fid)
		if table.substr(f, 400).contains("\"ninja\""):
			needs_ninja += 1
	assert_eq(needs_ninja, 2,
		"the ninja-dependent formations changed — if they no longer need the Ninja, this pin is stale")
