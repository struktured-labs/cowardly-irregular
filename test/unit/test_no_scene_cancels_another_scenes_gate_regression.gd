extends GutTest

## Generalises the defect in this branch's first commit so it cannot recur. world1_prologue wrote
## cutscene_flag_spotlight_unlocked_<lead_job>; five gates in _get_pending_story_cutscene read that
## same key as "already happened" and refused to fire. Five scenes died, and nothing could see it:
## both sides were guarded, the collision between them was not.
##
## The rule: if a gate says a scene plays only while flag F is UNSET, then no OTHER reachable scene
## may set F. One scene writing its own completion flag is the normal case and is fine.
##
## Reachability is the load-bearing half, because an unreachable writer cannot cancel anything.
## CLAUDE.md's "a scene reaches a player at least SIX different ways — SIX IS A FLOOR, NOT A TOTAL"
## is why the oracle here scans every .gd under src/ for the id rather than checking a list of
## known forms: a literal, a loop variable and a const all match, and a form nobody has thought of
## yet still matches.
##
## KNOWN LATENT, declared rather than allowlisted: world2_arbiter_intro (11 authored steps) writes
## arbiter_suburban_intro_complete, which gates world2_chapter4 — and world2_chapter4 writes it too,
## as its own completion flag. The intro reaches a player by no form today, so it cancels nothing.
## Wire it and this guard reds, which is the point: the choice is then made deliberately.

const GAME_LOOP := "res://src/GameLoop.gd"
const CUTSCENE_DIR := "res://data/cutscenes"
const GATE_FN := "func _get_pending_story_cutscene"
## A floor, not a count — the extractor must keep finding gates or its silence means nothing.
const MIN_GATES := 40

var _src_blob: String = ""


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _indent(line: String) -> int:
	var n := 0
	while n < line.length() and line[n] == "\t":
		n += 1
	return n


## (blocking_flag, scene) pairs, where the `return` lives INSIDE the if-block that tests the flag.
## Pairing on "the next return within N lines" instead reads four engine auto-advance blocks as
## gates and names the wrong scene — measured, so the block scope is the instrument.
func _gates() -> Array:
	var lines := _read(GAME_LOOP).split("\n")
	var start := -1
	var stop := lines.size()
	for i in lines.size():
		if lines[i].begins_with(GATE_FN):
			start = i
		elif start > -1 and i > start and lines[i].begins_with("func "):
			stop = i
			break
	assert_gt(start, -1, "control: found %s" % GATE_FN)
	var out: Array = []
	var flag_re := RegEx.create_from_string('not flags\\.get\\("cutscene_flag_([a-z0-9_]+)"')
	var ret_re := RegEx.create_from_string('return "([a-z0-9_]+)"')
	for i in range(start, stop):
		var line: String = lines[i]
		if not line.strip_edges().begins_with("if "):
			continue
		var found := flag_re.search_all(line)
		if found.is_empty():
			continue
		var base := _indent(line)
		var scene := ""
		for j in range(i + 1, mini(i + 8, stop)):
			var nxt: String = lines[j]
			if nxt.strip_edges() == "":
				continue
			if _indent(nxt) <= base:
				break
			var m := ret_re.search(nxt)
			if m:
				scene = m.get_string(1)
				break
		if scene == "":
			continue
		for f in found:
			out.append([f.get_string(1), scene])
	return out


func _collect_flags(steps: Array, out: Dictionary) -> void:
	for s in steps:
		if not (s is Dictionary):
			continue
		var step: Dictionary = s
		if step.get("type", "") == "set_flag" and str(step.get("flag", "")) != "":
			out[str(step["flag"])] = true
		for key in ["if_true", "if_false"]:
			if step.get(key) is Array:
				_collect_flags(step[key], out)
		if step.get("cases") is Dictionary:
			for case_steps in (step["cases"] as Dictionary).values():
				if case_steps is Array:
					_collect_flags(case_steps, out)


## flag -> [scene ids that write it]
func _writers() -> Dictionary:
	var out: Dictionary = {}
	for name in DirAccess.get_files_at(CUTSCENE_DIR):
		if not name.ends_with(".json"):
			continue
		var parsed = JSON.parse_string(_read(CUTSCENE_DIR + "/" + name))
		if not (parsed is Dictionary):
			continue
		var data: Dictionary = parsed
		var id: String = str(data.get("id", name.trim_suffix(".json")))
		var flags: Dictionary = {}
		_collect_flags(data.get("steps", []), flags)
		for f in flags:
			if not out.has(f):
				out[f] = []
			(out[f] as Array).append(id)
	return out


## Every .gd under src/, concatenated once. An id can appear as a literal, a const or a loop
## variable, so the question asked is only "does this string exist in the engine at all".
func _src() -> String:
	if _src_blob != "":
		return _src_blob
	var parts: PackedStringArray = []
	var dirs: Array = ["res://src"]
	while not dirs.is_empty():
		var d: String = dirs.pop_back()
		for sub in DirAccess.get_directories_at(d):
			dirs.append(d + "/" + sub)
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd"):
				parts.append(_read(d + "/" + f))
	_src_blob = "\n".join(parts)
	return _src_blob


func _is_reachable(scene_id: String) -> bool:
	return _src().contains('"%s"' % scene_id)


func test_no_reachable_scene_cancels_another_scenes_gate() -> void:
	var gates := _gates()
	assert_gt(gates.size(), MIN_GATES, "control: the gate extractor still finds gates (%d)" % gates.size())
	var writers := _writers()
	var offenders: Array = []
	for pair in gates:
		var flag: String = pair[0]
		var scene: String = pair[1]
		for writer in writers.get(flag, []):
			if str(writer) == scene:
				continue  # a scene writing its own completion flag is the normal case
			if _is_reachable(str(writer)):
				offenders.append("%s is gated on NOT %s, which reachable scene %s sets" % [scene, flag, writer])
	assert_eq(offenders, [], "a scene must not cancel another scene's gate:\n  %s" % "\n  ".join(PackedStringArray(offenders)))


func test_the_detector_sees_the_defect_it_was_written_for() -> void:
	# FLOOR: replay the pre-fix prologue write against the live gates. Without this, an extractor
	# that silently found nothing would report the tree clean forever.
	var gates := _gates()
	var planted := {
		"spotlight_unlocked_fighter": "world1_prologue",
		"spotlight_unlocked_cleric": "world1_prologue",
		"spotlight_unlocked_mage": "world1_prologue",
		"spotlight_unlocked_rogue": "world1_prologue",
		"spotlight_unlocked_bard": "world1_prologue",
	}
	var caught: Array = []
	for pair in gates:
		if planted.has(pair[0]) and str(pair[1]) != planted[pair[0]]:
			caught.append(pair[1])
	assert_eq(caught.size(), 5,
		"the five spotlight gates must be visible to the extractor, or a green above means nothing: %s" % [caught])


func test_the_reachability_oracle_can_answer_both_ways() -> void:
	# FLOOR: an oracle that always said "unreachable" would silence every offender.
	assert_true(_is_reachable("world1_prologue"), "control: a wired scene reads as reachable")
	assert_false(_is_reachable("world2_arbiter_intro"),
		"control: the declared-latent scene reads as unreachable — wire it and the arm above reds")


func test_the_latent_w2_pair_is_still_exactly_one_scene_away() -> void:
	# The declaration, kept honest: both scenes really do write the shared flag, and the wired one
	# really is the flag's owner in the completion map. If either half changes, re-read the docstring.
	var writers := _writers()
	var sharers: Array = writers.get("arbiter_suburban_intro_complete", [])
	sharers.sort()
	assert_eq(sharers, ["world2_arbiter_intro", "world2_chapter4"],
		"the known-latent pair is exactly these two scenes: %s" % [sharers])
	assert_true(_read(GAME_LOOP).contains('"world2_chapter4":                  "cutscene_flag_arbiter_suburban_intro_complete"'),
		"world2_chapter4 owns that flag in the completion map — so the intro is the interloper, not it")
