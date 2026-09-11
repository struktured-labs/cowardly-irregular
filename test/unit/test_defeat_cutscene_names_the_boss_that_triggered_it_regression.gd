extends GutTest

## YOU BEAT THE WARDEN OF THE ASSEMBLY LINE AND THE FIREWALL GAVE THE EULOGY.
##
## 2026-09-11. Three tests already pinned the masterite defeat cutscenes — wired,
## reachable, scoped to the right dungeon map, present in the completion-flag table.
## All four gates were green. Two of them played the wrong boss's scene.
##
##   AssemblyCore's boss is masterite_warden_industrial (Warden of the Assembly Line).
##   Beating it played world4_warden_defeat: "ACCESS: GRANTED", green scrolling text,
##   a firewall discovering it has nothing left to refuse. That is the FUTURISTIC
##   Warden, a boss the player has not met, from the next world.
##
##   RootProcess's boss is masterite_arbiter_futuristic (Arbiter of the Benchmark).
##   Beating it played world5_arbiter_defeat — the ABSTRACT Arbiter's aftermath.
##
## The masterite intro/defeat scenes are filed one world BELOW the boss they belong
## to: world3_warden_defeat is the industrial Warden's, world4_arbiter_defeat is the
## futuristic Arbiter's. Every one of those files names its true owner TWICE — in its
## `trigger` field and in the set_flag step it closes with — and the gates were wired
## by FILENAME, so nothing ever read either.
##
## THE PROPERTY NO EXISTING ARM ASKED FOR: the scene a defeat gate plays must belong
## to the boss whose flag opened the gate. "A cutscene is wired" and "the right
## cutscene is wired" are different questions, and four green arms answered only the
## first. This file asks the second and nothing else — the reachability arms stay
## where they are, deliberately separate, because a single file that checked both
## would have gone green on the half it could already prove.
##
## ⚠️ TRIGGER IS THE AUTHORITY, NOT `world`, AND NOT THE FILENAME. The `world` field
## was re-stamped to match the filename when these were filed, so it agrees with the
## wrong half. world5_curator_defeat carries `"world": 5` and is played by the W6
## NullChamber — correctly, because its trigger says boss_curator_abstract_defeated
## and NullChamber's boss IS masterite_curator_abstract. An earlier pass of this
## check keyed on `world` and flagged that scene; it was the instrument that was
## wrong. The file's own declaration of which boss it is about is the only field
## that survived the misfiling intact.
##
## ⚠️ WHAT THIS CANNOT SEE. It reads the gate and the JSON, so it knows which scene
## is SELECTED, never what a player watched: it cannot tell whether the dungeon is
## reachable, whether the flag is ever set, or whether a portrait resolves to art.
## The first two live in the sibling arms. The third is open and larger than this
## file: 33 of 71 cutscenes name a masterite variant from another world in their
## `portrait` fields. 29 of those are invisible — only the four MEDIEVAL masterites
## have portrait PNGs on disk, so every other id falls through to the same procedural
## bust and a wrong one looks exactly like a right one. Art landing is what makes
## them visible, which is the wrong moment to find out.

const GAME_LOOP := "res://src/GameLoop.gd"
const CUTSCENE_DIR := "res://data/cutscenes/"

## Exactly the dungeon-aftermath gate shape: a masterite defeat flag, a completion
## guard, a dungeon map scope, a return. The map-id line is load-bearing as a FILTER,
## not decoration — three W2 gates fire a CHAPTER off a boss flag with no map scope
## (world2_chapter3, chapter5, chapter7_infrastructure). Those are story beats that
## follow a defeat, not that boss's aftermath, and they are not this file's subject.
const GATE_PATTERN := "flags\\.get\\(\"cutscene_flag_(warden|tempo|arbiter|curator)_([a-z]+)_defeated\", false\\) and not flags\\.get\\(\"cutscene_flag_[a-z0-9_]+\", false\\):\\s*\\n\\s*if _current_map_id == \"[a-z0-9_]+\":\\s*\\n\\s*return \"([a-z0-9_]+)\""


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


## Comment lines blanked, line count preserved. Without this the scan matches a
## COMMENTED-OUT gate as readily as a live one: measured 2026-09-11, commenting out
## the W4 gate — which stops the aftermath playing at all — left this file 6/6 GREEN.
## @cowir-controller's question is the one that found it: what does the file look like
## after a REAL PERSON removes the thing you are defending? They delete the branch and
## leave the comment that explained it, which is the mutation a bare source scan is
## least able to see and the one that actually happens.
func _code_only(text: String) -> String:
	var out: PackedStringArray = []
	for line in text.split("\n"):
		out.append("" if line.strip_edges().begins_with("#") else line)
	return "\n".join(out)


## [[role, world, cutscene_id]] for every dungeon-aftermath gate in GameLoop.
func _gates() -> Array:
	var out: Array = []
	var re := RegEx.new()
	if re.compile(GATE_PATTERN) != OK:
		return out
	for m in re.search_all(_code_only(_read(GAME_LOOP))):
		out.append([m.get_string(1), m.get_string(2), m.get_string(3)])
	return out


func _trigger_of(cutscene_id: String) -> String:
	var path: String = CUTSCENE_DIR + cutscene_id + ".json"
	if not FileAccess.file_exists(path):
		return ""
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return ""
	return str((parsed as Dictionary).get("trigger", ""))


## Every boss that any authored cutscene claims as its own, read from `trigger`.
func _bosses_with_an_authored_aftermath() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(CUTSCENE_DIR)
	if dir == null:
		return out
	for name in dir.get_files():
		if not name.ends_with(".json"):
			continue
		var trig: String = _trigger_of(name.substr(0, name.length() - 5))
		if trig.begins_with("boss_") and trig.ends_with("_defeated"):
			var boss: String = trig.substr(5, trig.length() - 5 - "_defeated".length())
			if not out.has(boss):
				out.append(boss)
	out.sort()
	return out


## The five dungeon bosses that HAVE an aftermath gate. Named, not counted — see below.
const EXPECTED_GATED_BOSSES: Array[String] = [
	"warden_suburban",      # SuburbanUnderground
	"tempo_steampunk",      # SteampunkMechanism
	"warden_industrial",    # AssemblyCore
	"arbiter_futuristic",   # RootProcess
	"curator_abstract",     # NullChamber
]


## PREMISE, and it took two tries to make it one. A size floor (`>= 4`) is armed
## against VACUITY — the scan finding nothing — and blind to PARTIAL LOSS. Measured
## 2026-09-11: commenting out the W4 gate, which stops that aftermath playing at all,
## left the scan with four gates and the whole file 6/6 GREEN. The gate was not
## mis-wired, it was ABSENT, and a check that validates the gates it finds cannot see
## one that is gone.
##
## So the membership is NAMED. Removal now fails and says which boss lost its scene.
## Growth is fine — a sixth dungeon gate is caught by the ownership ratchet below,
## which is the arm that should judge a new one.
func test_premise_every_dungeon_boss_still_has_its_aftermath_gate() -> void:
	# THE CONTROL MUST NOT BE DRAINABLE EITHER. Measured 2026-09-11: emptying EXPECTED_GATED_BOSSES
	# gave Failed 0, Risky 0 — the loop below runs zero times and the corpus floor is a
	# literal that still passes, so the named-member fix I added an hour ago introduced
	# a new silent control. @cowir-sfx's cell: every `for x in LIST` and every
	# `size() >= LIST.size()` is silent at LIST == []. Pinned to a literal.
	assert_eq(EXPECTED_GATED_BOSSES.size(), 5,
		"EXPECTED_GATED_BOSSES has been emptied or resized — the named-member check below is now vacuous. If a member was deliberately retired, change this number in the same edit.")
	var gates := _gates()
	var found: Array[String] = []
	for gate in gates:
		found.append("%s_%s" % [str(gate[0]), str(gate[1])])
	var missing: Array[String] = []
	for boss in EXPECTED_GATED_BOSSES:
		if not found.has(boss):
			missing.append(boss)
	assert_eq(missing.size(), 0,
		"a dungeon boss lost its aftermath gate: %s — the scene no longer plays at all. If the gate was deliberately retired, remove the boss from EXPECTED_GATED_BOSSES in this file and say why; if GATE_PATTERN stopped matching, fix the pattern. Found: %s" % [", ".join(missing), ", ".join(found)])


## POSITIVE CONTROL, harvested not built: the W2 Warden gate was correct before this
## fix and after it. If the resolution below cannot confirm a pair that IS right, a
## clean run of the ratchet means nothing.
func test_the_check_can_confirm_a_pair_that_agrees() -> void:
	var found := false
	for gate in _gates():
		if str(gate[0]) == "warden" and str(gate[1]) == "suburban":
			found = true
			assert_eq(_trigger_of(str(gate[2])), "boss_warden_suburban_defeated",
				"the W2 Warden of Routine gate is the known-good pair; if resolving it fails, this file's reader is broken, not GameLoop")
	assert_true(found,
		"the W2 suburban warden gate was not among the parsed gates — the scan is not seeing the family it claims to")


## NEGATIVE CONTROL, synthesised: the corpus does not contain a pair that disagrees
## once the fix lands, so the only way to show the comparison can say NO is to build
## one. An instrument never shown able to fail is not evidence when it passes.
func test_the_check_can_reject_a_pair_that_disagrees() -> void:
	var real: String = _trigger_of("world5_curator_defeat")
	assert_eq(real, "boss_curator_abstract_defeated",
		"fixture drift: world5_curator_defeat should declare the abstract Curator")
	assert_ne(real, "boss_curator_futuristic_defeated",
		"COMPARISON IS INERT: a trigger that names the abstract Curator compared equal to one naming the futuristic Curator, so every assertion below would pass on any input")


## THE RATCHET. A defeat gate must play the aftermath of the boss whose flag opened it.
func test_every_defeat_gate_plays_its_own_bosss_aftermath() -> void:
	var gates := _gates()
	var authored := _bosses_with_an_authored_aftermath()
	var wrong: Array[String] = []
	var unauthored: Array[String] = []

	for gate in gates:
		var boss: String = "%s_%s" % [str(gate[0]), str(gate[1])]
		var cutscene_id: String = str(gate[2])
		var want: String = "boss_%s_defeated" % boss
		var got: String = _trigger_of(cutscene_id)
		if got == want:
			continue
		# Exemption, DERIVED: a boss with no authored aftermath anywhere has nothing
		# right to play, and naming it here would be a permanent excuse. Computed from
		# the corpus, so authoring the scene retires the exemption by itself and the
		# ratchet then demands the rewire.
		if not authored.has(boss):
			unauthored.append("%s (gate plays %s, which belongs to %s)" % [boss, cutscene_id, got])
			continue
		wrong.append("%s -> plays %s, whose own trigger says %s" % [boss, cutscene_id, got])

	assert_eq(wrong.size(), 0,
		"a defeat gate plays another boss's aftermath: %s. The scene each one should play is authored and has no caller — wire the gate to the cutscene whose `trigger` field names the boss whose flag opened it" % ", ".join(wrong))

	# Bidirectional: the exemption list is debt, not a settled state. It shrinks when
	# someone authors the missing scene, and this fails so the gate gets rewired
	# instead of the new file sitting unreachable next to the wrong one still playing.
	assert_eq(unauthored.size(), 1,
		"the no-authored-aftermath set is %d, expected exactly 1 (tempo_steampunk — The Grand Schedule, W3's Grand Mechanism boss, whose gate plays the INDUSTRIAL Tempo's aftermath because no steampunk masterite cutscene exists at all). Current set: %s. If this shrank, the scene was authored: point the gate at it. If it grew, a gate lost its scene." % [unauthored.size(), ", ".join(unauthored)])


## The scene a gate names has to be on disk, or the gate drops the player to the
## console-only fallback DragonCave:655 documents.
func test_every_gated_aftermath_scene_exists() -> void:
	var missing: Array[String] = []
	for gate in _gates():
		var path: String = CUTSCENE_DIR + str(gate[2]) + ".json"
		if not FileAccess.file_exists(path):
			missing.append(str(gate[2]))
	assert_eq(missing.size(), 0,
		"defeat gate names a cutscene with no JSON on disk: %s" % ", ".join(missing))


## Second property, same subject: WITHIN a gated aftermath scene, the faces must be
## the boss whose scene it is. world2_warden_defeat asked for masterite_warden_medieval
## in all ten of its lines — the World 1 Warden of the Old Guard — for the Warden of
## Routine's aftermath. It is the only place this was VISIBLE: the four medieval
## masterites are the only ones with portrait art on disk, so every other wrong id
## fell through to the same procedural bust and looked identical to a right one.
## Her own intro minutes earlier (world2_warden_routine) asked for the suburban id and
## drew the silhouette, so the same boss changed faces between the two scenes.
##
## Keyed on the scene's OWN trigger, not on its world or filename — same reason as
## above, and it is what makes world3_tempo_defeat pass here while remaining the
## exempt row above: its portraits agree with the industrial Tempo it declares. The
## two arms disagree about that file on purpose. This one asks "is the scene
## internally coherent"; the one above asks "is it the right scene".
func test_gated_aftermath_scenes_show_their_own_bosss_face() -> void:
	var checked: int = 0
	var wrong: Array[String] = []
	var re := RegEx.new()
	if re.compile("\"(?:boss_)?(warden|tempo|arbiter|curator)_(medieval|suburban|steampunk|industrial|futuristic|abstract)_defeated\"") != OK:
		fail_test("trigger pattern failed to compile")
		return

	for gate in _gates():
		var cutscene_id: String = str(gate[2])
		var path: String = CUTSCENE_DIR + cutscene_id + ".json"
		if not FileAccess.file_exists(path):
			continue
		var raw: String = FileAccess.get_file_as_string(path)
		var parsed: Variant = JSON.parse_string(raw)
		if not (parsed is Dictionary):
			continue
		var m := re.search("\"%s\"" % str((parsed as Dictionary).get("trigger", "")))
		if m == null:
			continue  # name-shaped trigger (the fragment scenes); no world to compare against
		checked += 1
		var own: String = "masterite_%s_%s" % [m.get_string(1), m.get_string(2)]
		var ids := RegEx.new()
		if ids.compile("masterite_(?:warden|tempo|arbiter|curator)_(?:medieval|suburban|steampunk|industrial|futuristic|abstract)") != OK:
			continue
		var seen: Array[String] = []
		for hit in ids.search_all(raw):
			var id: String = hit.get_string()
			if id != own and not seen.has(id):
				seen.append(id)
		if not seen.is_empty():
			wrong.append("%s declares %s but draws %s" % [cutscene_id, own, ", ".join(seen)])

	assert_gt(checked, 2,
		"only %d gated scenes had a <role>_<world> trigger to compare against — the walk is not reading the family, so a clean result below means nothing" % checked)
	assert_eq(wrong.size(), 0,
		"a gated aftermath scene draws another masterite's face: %s" % ", ".join(wrong))
