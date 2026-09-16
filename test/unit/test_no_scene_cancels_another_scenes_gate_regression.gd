extends GutTest

## Generalises the defect in this branch's first commit so it cannot recur. world1_prologue wrote
## cutscene_flag_spotlight_unlocked_<lead_job>; five gates in _get_pending_story_cutscene read that
## same key as "already happened" and refused to fire. Five scenes died, and nothing could see it:
## both sides were guarded, the collision between them was not.
##
## The rule: if a gate says a scene plays only while flag F is UNSET, then no OTHER reachable scene
## may set F. One scene writing its own completion flag is the normal case and is fine.
##
## Reachability is the load-bearing half, because an unreachable writer cannot cancel anything —
## and an oracle that wrongly says "unreachable" SILENCES an offender, so its errors must fall the
## other way. CLAUDE.md's "a scene reaches a player at least SIX different ways — SIX IS A FLOOR,
## NOT A TOTAL" is why it scans text rather than checking a list of known forms: a literal, a const
## and a loop variable all match, and so does a form nobody has thought of yet.
##
## Corpus, and why each piece is in it:
##   every .gd under src/   the engine, any form
##   every .tscn            MasteriteEncounter.cutscene_id is an @export, so a scene file can
##                          configure a play. Measured 2026-09-16: no .tscn sets one TODAY, which
##                          is exactly why the scan is here rather than added after it bites.
##   data/quests/*.json     by KEY (cutscene_on_complete / cutscene / cutscene_id), because SIX
##                          scenes — world1..world6_orrery — are reachable by no other form, and
##                          this guard's first version could not see any of them.
## NOT raw JSON text: data/sfx_manifest.json names cutscene ids inside prompt strings, recording
## which scene a cue was authored for. Measured 2026-09-16 (cowir-sfx counted 22 mentions across 20
## keys in their own file; derived here as 16 DISTINCT ids that have a cutscene file, since three
## keys can name one scene): 16 named in prose, of which 4 are reached by NO real form —
## world2_arbiter_intro, world3_tempo_intro, world4_curator_intro, world4_warden_intro. So a
## blanket scan does not merely risk a phantom consumer, it invents exactly four, and each one
## SILENCES an offender rather than crying wolf. Pinned by
## test_a_cue_prompt_is_not_a_wiring so the exclusion cannot be tidied away by someone who sees
## only one example.
##
## ⚠️ SECOND DECLARER: test_orphan_boss_cutscene_registry.gd (tick 243) ALSO declares
## world2_arbiter_intro — as one of 20 KNOWN_PLANNED_INTROS, and its arms red when an entry gains a
## code reference. So wiring that scene reds BOTH files, correctly, and retiring either declaration
## means checking the other. A self-retiring pin protects the fact; it does not tell you how many
## pins the fact has (cowir-music, who shipped a red branch as the second declarer of one collision).
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


## Every .gd under src/ and every .tscn in the project, concatenated once.
func _src() -> String:
	if _src_blob != "":
		return _src_blob
	var parts: PackedStringArray = []
	var dirs: Array = ["res://src", "res://"]
	var seen: Dictionary = {}
	while not dirs.is_empty():
		var d: String = dirs.pop_back()
		if seen.has(d):
			continue
		seen[d] = true
		for sub in DirAccess.get_directories_at(d):
			if sub.begins_with(".") or sub == "addons" or sub == "tmp" or sub == "builds":
				continue
			dirs.append(d.trim_suffix("/") + "/" + sub)
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd") and d.begins_with("res://src"):
				parts.append(_read(d.trim_suffix("/") + "/" + f))
			elif f.ends_with(".tscn"):
				parts.append(_read(d.trim_suffix("/") + "/" + f))
	_src_blob = "\n".join(parts)
	return _src_blob


## Scene ids any DATA file can configure, read by KEY so authored prose cannot look like a wiring.
## Walks all of data/ rather than data/quests/ alone: this oracle has already gone blind twice in
## one hour by missing a form, so a third data file carrying a cutscene key is not hypothetical.
## data/cutscenes/ itself is excluded — a scene's own id is not a wiring for it.
func _quest_played() -> Dictionary:
	var out: Dictionary = {}
	var dirs: Array = ["res://data"]
	while not dirs.is_empty():
		var d: String = dirs.pop_back()
		if d.begins_with("res://data/cutscenes"):
			continue
		for sub in DirAccess.get_directories_at(d):
			dirs.append(d.trim_suffix("/") + "/" + sub)
		for name in DirAccess.get_files_at(d):
			if not name.ends_with(".json"):
				continue
			_harvest_cutscene_keys(JSON.parse_string(_read(d.trim_suffix("/") + "/" + name)), out)
	return out


func _harvest_cutscene_keys(node, out: Dictionary) -> void:
	if node is Dictionary:
		for k in (node as Dictionary):
			var v = (node as Dictionary)[k]
			if (k == "cutscene_on_complete" or k == "cutscene" or k == "cutscene_id") and v is String and str(v) != "":
				out[str(v)] = true
			else:
				_harvest_cutscene_keys(v, out)
	elif node is Array:
		for x in (node as Array):
			_harvest_cutscene_keys(x, out)


func _is_reachable(scene_id: String) -> bool:
	return _src().contains('"%s"' % scene_id) or _quest_played().has(scene_id)


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
	# A RATCHET, not a measurement: five is the W1 starter count. A SIXTH spotlight scene should red
	# this, and the correct response is to add it to `planted` — not to relax the number.
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


func test_the_quest_form_is_in_the_oracle() -> void:
	# FLOOR: six scenes reach a player ONLY as a quest's cutscene_on_complete. This guard's first
	# version scanned src/ alone and would have called all six unreachable — the direction that
	# silences an offender rather than crying wolf.
	var quest_ids := _quest_played()
	assert_gt(quest_ids.size(), 5, "the data-side oracle must still find its ids: %s" % [quest_ids.keys()])
	# FLOOR on the WALK, not just the result: a harvest that only ever reads one directory would
	# pass the line above forever on the six orreries alone.
	assert_true(DirAccess.get_directories_at("res://data").size() > 1,
		"control: data/ really has sub-directories to walk")
	assert_true(quest_ids.has("world6_orrery"), "control: the W6 orrery is quest-played and by nothing else")
	assert_false(_src().contains('"world6_orrery"'), "control: and it is genuinely absent from the code scan")
	assert_true(_is_reachable("world6_orrery"), "so the oracle must call it reachable")


func test_the_scan_reads_scene_files_and_not_authored_prose() -> void:
	# .tscn is in the corpus because MasteriteEncounter.cutscene_id is an @export; raw JSON is NOT,
	# because sfx_manifest names a scene id inside a prompt.
	assert_true(_src().contains("[gd_scene"), "control: at least one .tscn really was read")
	assert_true(_read("res://data/sfx_manifest.json").contains("world2_arbiter_intro"),
		"control: authored prose still names that id — the reason raw JSON stays out of the corpus")
	assert_false(_is_reachable("world2_arbiter_intro"),
		"prose is not a wiring: the latent case stays latent")


## Cutscene ids named in an SFX cue's prompt text — provenance, never a consumer.
func _ids_named_in_sfx_prose() -> Array:
	var manifest := _read("res://data/sfx_manifest.json")
	var out: Array = []
	for name in DirAccess.get_files_at(CUTSCENE_DIR):
		if not name.ends_with(".json"):
			continue
		var parsed = JSON.parse_string(_read(CUTSCENE_DIR + "/" + name))
		if not (parsed is Dictionary):
			continue
		var id: String = str((parsed as Dictionary).get("id", name.trim_suffix(".json")))
		if id != "" and manifest.contains(id):
			out.append(id)
	return out


func test_a_cue_prompt_is_not_a_wiring() -> void:
	# A floor, not a count: cowir-sfx may name more scenes in cue prompts at any time, and that is
	# the provenance those strings exist for. What must stay true is that none of them COUNTS.
	var named := _ids_named_in_sfx_prose()
	assert_gt(named.size(), 5, "control: cue prompts really do name scenes (%d)" % named.size())
	var phantom: Array = []
	for id in named:
		if not _is_reachable(str(id)):
			phantom.append(id)
	assert_gt(phantom.size(), 0,
		"control: at least one prose-named scene is reached by no real form — the set a raw-JSON scan would invent consumers for: %s" % [phantom])
	for id in phantom:
		assert_false(_src().contains('"%s"' % id),
			"a cue's prompt must not read as a wiring for %s" % id)


## Every statement-level assignment to a cutscene-id field, as (file, line, right-hand side).
func _id_assignments() -> Array:
	var out: Array = []
	# The dotted prefix is OPTIONAL: `boss_cutscene_id = "x"` has no word boundary inside its own
	# name, so a mandatory prefix matched 3 of 20 assignments — the floors below are what caught it.
	var re := RegEx.create_from_string("^(?:@export\\s+var\\s+|var\\s+)?(?:[A-Za-z_][A-Za-z0-9_]*\\.)?(?:boss_)?cutscene_id\\b[^=]*=\\s*(.+)$")
	var dirs: Array = ["res://src"]
	while not dirs.is_empty():
		var d: String = dirs.pop_back()
		for sub in DirAccess.get_directories_at(d):
			dirs.append(d.trim_suffix("/") + "/" + sub)
		for f in DirAccess.get_files_at(d):
			if not f.ends_with(".gd"):
				continue
			var path := d.trim_suffix("/") + "/" + f
			var n := 0
			for line in _read(path).split("\n"):
				n += 1
				var t: String = line.strip_edges()
				if t.begins_with("#") or t.contains("=="):
					continue
				var m := re.search(t)
				if m:
					out.append([path, n, m.get_string(1).strip_edges()])
	return out


func test_a_cutscene_id_reaching_the_engine_is_always_a_literal() -> void:
	# THE PRECONDITION OF THE ORACLE ABOVE, which was an unstated assumption until now: a text scan
	# finds every configured play only while every id is WRITTEN OUT. One `boss_cutscene_id =
	# "world%d_boss" % w` and the scan goes blind — in the silencing direction, since an
	# unreachable-looking writer passes this guard's offender check.
	var assignments := _id_assignments()
	assert_gt(assignments.size(), 10, "control: the scan really finds the assignments (%d)" % assignments.size())
	var constructed: Array = []
	var literals := 0
	var whole_string := RegEx.create_from_string('^"[^"]*"\\s*(?:#.*)?$')
	for a in assignments:
		var rhs: String = str(a[2])
		# CONSTRUCTION IS TESTED FIRST, and "a literal" means the WHOLE right-hand side is one.
		# Ordered the other way, `"world%d_x" % w` begins with a quote and was filed as a literal:
		# the arm passed the mutation it exists for. Caught by predicting the red, not by the green.
		if rhs.contains("%") or rhs.contains(" + ") or rhs.contains("str("):
			constructed.append("%s:%d -> %s" % [a[0], a[1], rhs])
		elif whole_string.search(rhs) != null:
			literals += 1
	assert_gt(literals, 10, "control: most assignments are plain literals (%d)" % literals)
	assert_eq(constructed, [],
		"a constructed cutscene id cannot be found by a text scan — widen the oracle in the same change:\n  %s" % "\n  ".join(PackedStringArray(constructed)))


## The SECOND PIN on this fact, asserted rather than described. @cowir-autogrind's discriminator:
## where the premise is a FACT, prose is the weaker choice — and "does that registry still declare
## this scene" is checkable from here without editing a file that is not mine.
func test_the_other_pin_on_this_fact_still_exists() -> void:
	var sibling: String = _read("res://test/unit/test_orphan_boss_cutscene_registry.gd")
	# TWO CONTROLS, because an agreement check between two files passes hardest when it can read
	# NEITHER: rename the sibling or its constant and a bare `contains` goes quietly green
	# (cowir-music, whose own control caught exactly this).
	assert_gt(sibling.length(), 500,
		"CONTROL: the sibling guard read back %d chars — moved or renamed, so this arm proves nothing" % sibling.length())
	assert_true(sibling.contains("KNOWN_PLANNED_INTROS"),
		"CONTROL: the sibling's declaration list is still called KNOWN_PLANNED_INTROS")
	assert_true(sibling.contains('"world2_arbiter_intro"'),
		"the OTHER pin on world2_arbiter_intro is gone — if that scene got wired, retire BOTH declarations, not one")
