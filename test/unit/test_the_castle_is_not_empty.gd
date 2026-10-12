extends GutTest

## `data/castle_harmonia_narrative.json` — 5 NPCs and a puzzle, 510 words — has been authored and
## reachable by no player since **2026-07-13**. @cowir-story's data-pack census found it; the handoff
## plan in `docs/design/w1-progression-expansion.md` named the halves even then: *"cowir-story is
## DONE for Castle … cowir-overworld is not yet started on Castle layout."* The floors, encounter
## pools, signposts and boss trigger all landed. **The NPCs did not, and `CastleHarmonia` had zero.**
## Success criterion 4 of that doc is literally this: *"traverse 3 floors, fighting corrupt guards,
## reading environmental storytelling, then face Mordaine."*
##
## 🔑 I RAN THE SUPERSESSION CHECK BEFORE WIRING ANY OF IT, because @cowir-story's own correction an
## hour earlier showed why: their `world2_coordinator_memos` pack turned out to have **7 of 8 beats
## already shipped** in a cutscene the player reaches, so wiring it would have duplicated content. A
## consumer census answers *"is this text loaded"*, never *"has this beat shipped"*.
##
## ⛔ AND MY FIRST SUPERSESSION INSTRUMENT WAS BROKEN IN THE DIRECTION THAT WOULD HAVE CANCELLED THE
## WORK. Matching each authored string's first 40 characters reported **51 verbatim hits across
## nearly every cutscene in the game** — because one husk line is `'...'`, three characters, whose
## prefix is ubiquitous. Read as a count that said "superseded, wire nothing". The fix is a
## distinctiveness floor and reading the hit rather than counting it:
##
##     18 of 20 strings (>= 25 chars) against a 290-file corpus  ->  0 verbatim hits
##     2 skipped as too short to be distinctive, reported not hidden
##     beat nouns `hollow` `husk` `servant` `tapestry`           ->  0 shipped files
##     the one adjacency: the castle's own signpost "The Petrified Court" names the ROOM where the
##     pack describes an individual courtier — complementary, not duplicate
##
## So the pack is genuinely unshipped, and this wires the NPC half. The 11 `castle_harmonia`
## entries in `examine_texts.json` are a separate, larger item (an examine surface plus a prop per
## entry) and are deliberately not in this change.

const CASTLE := "res://src/maps/dungeons/CastleHarmonia.gd"
const PACK := "res://data/castle_harmonia_narrative.json"

var _snap: Dictionary = {}


## The floor is cross-test state; `CastleFloor` names it and puts it back.
func before_each() -> void:
	_snap = CastleFloor.snapshot()


func after_each() -> void:
	CastleFloor.restore(_snap)


func _pack() -> Dictionary:
	var raw := FileAccess.get_file_as_string(PACK)
	assert_ne(raw, "", "CONTROL: the authored pack must be readable or every arm here is vacuous")
	var parsed = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "CONTROL: the pack must parse as a dictionary")
	return parsed as Dictionary if parsed is Dictionary else {}


## ⛔ THE CODE HALF — AND THIS GUARD WAS MEASURED FULLY SILENT WITHOUT IT. Attack: delete the
## FLOOR-3 servant's mark outright and name her in a quoted comment inside `_NPC_MARKS`.
##
##     before   EC=0 · 7/7 PASSING   an authored NPC reaches nobody and nothing says so
##     after    EC=1 · Failing 2     the placement arm names her, the floor-3 build arm counts her
##
## Two independent causes, which is why one fix was not enough: `src.contains(npc_id)` is an
## ACCEPTANCE assert that prose satisfies (@cowir-story's split), and the build arm below used to
## measure ONE floor — whichever an earlier test left set — so a loss on any other was invisible.
##
## 🔑 The controls are the pair this file's shape supports: `GdSource.split` puts only `"""` regions
## in `doc` and CastleHarmonia.gd has zero of them (measured doc len=0), so the usual doc floor
## would red on a correct strip. One control proves code survived, the other that prose did not.
func _source() -> String:
	var raw := FileAccess.get_file_as_string(CASTLE)
	assert_ne(raw, "", "CONTROL: CastleHarmonia.gd must be readable")
	var code: String = str(GdSource.split(raw)["code"])
	assert_true(code.contains("func _place_castle_npcs"),
		"CONTROL: the strip must keep real code; every arm here is vacuous if it ate the placer")
	assert_false(code.contains("##"),
		"CONTROL: no comment may survive into the code half, or a presence assert is still prose-satisfiable")
	return code


func test_the_pack_has_a_consumer_at_all() -> void:
	var src := _source()
	assert_true(src.contains("castle_harmonia_narrative.json"),
		"the castle must NAME the authored pack; this is the arm @cowir-story's data-pack census " +
		"would have kept red, and it was red from 2026-07-13 until this change")
	assert_true(src.contains("OverworldNPC.new()"),
		"and it must actually build NPCs — naming the pack without placing anyone reaches no player")


## Every authored NPC must be placed. A subset would be the silent-partial-wiring shape: the pack
## looks consumed and some of the prose still reaches nobody.
func test_every_authored_npc_is_placed() -> void:
	var authored: Dictionary = _pack().get("npcs", {})
	assert_gte(authored.size(), 5, "CONTROL: the pack must still carry its 5 NPCs, found %d" % authored.size())
	var src := _source()
	var missing: Array = []
	for npc_id in authored.keys():
		if not src.contains(str(npc_id)):
			missing.append(str(npc_id))
	missing.sort()
	assert_eq(missing, [],
		"these authored NPCs have no placement mark, so their lines still reach no player: %s" % ", ".join(missing))


## The lines stay in the pack. A copy in the script is a second source for the same prose, and the
## two drift the way a village's `fallbacks[]` drifted from its constructor dialogue.
func test_the_lines_are_not_copied_into_the_script() -> void:
	var src := _source()
	var authored: Dictionary = _pack().get("npcs", {})
	var copied: Array = []
	for npc_id in authored.keys():
		var entry: Dictionary = authored[npc_id]
		for line in (entry.get("lines", []) as Array):
			var l: String = str(line)
			if l.length() >= 25 and src.contains(l):
				copied.append("%s: %s" % [str(npc_id), l.substr(0, 40)])
	assert_eq(copied, [],
		"authored prose is duplicated in the script; the pack must stay the only source: %s" % ", ".join(copied))


## Placement goes through the SIGNS' allocator, which is what makes stacking impossible rather than
## unlikely. Two Harmonia librarians ring-searched independently and landed on one cell, and the
## nearest-wins probe then gave every approach cell to one of them.
func test_placement_shares_the_signposts_allocator() -> void:
	var src := _source()
	assert_true(src.contains("npc.position = _sign_position("),
		"NPCs must be placed through _sign_position, which consumes _sign_taken — a raw cell can " +
		"collide with a signpost or another NPC, and interaction is nearest-wins")
	assert_false(src.contains("npc.position = Vector2("),
		"a raw pixel position bypasses the allocator and the walkability check with it")


## Floor-scoped: the castle rebuilds per floor, so an NPC parented anywhere else survives the change
## and appears on a floor it was not authored for.
func test_npcs_are_built_per_floor_and_in_the_rebuilt_container() -> void:
	var src := _source()
	var at := src.find("func _place_castle_npcs")
	assert_gt(at, -1, "the placement helper must exist")
	var end := src.find("\nfunc ", at + 10)
	var body := src.substr(at, end - at)
	assert_true(body.contains("transitions.add_child(npc)"),
		"NPCs must go in the same per-floor container the signposts use, or they outlive their floor")
	assert_true(body.contains('int(authored.get("floor", 0)) != floor_num'),
		"each NPC must be filtered to the floor the PACK assigns it, not placed on every floor")


## A missing or malformed pack must degrade to signposts with a warning, never to an NPC with no
## lines — a silent NPC advertises a talk it cannot have, which is the mute-interactable class.
func test_a_broken_pack_places_nobody_rather_than_a_silent_npc() -> void:
	var src := _source()
	var at := src.find("func _place_castle_npcs")
	var body := src.substr(at, src.find("\nfunc ", at + 10) - at)
	assert_true(body.contains("lines.is_empty()"), "an authored entry with no lines must be skipped")
	assert_true(body.contains("authored.is_empty()"), "a missing authored entry must be skipped")
	for shape in ["push_warning"]:
		assert_true(body.contains(shape), "and the skip must say so rather than vanishing")
	assert_true(_source().contains("falls back to signposts only"),
		"a missing pack must degrade loudly and leave the castle's existing narration intact")


## ⛔ THE ARM THAT MATTERS, because every arm above reads SOURCE — and a source arm would pass with
## `_place_castle_npcs` never called, the pack path wrong at runtime, or `_sign_position` returning
## one cell five times. This builds the castle on EVERY floor and counts bodies, including floor 4,
## where the pack authors nobody: placing every NPC on every floor is caught, not merely unlikely.
func test_the_castle_builds_each_floors_npcs_and_no_others() -> void:
	var authored: Dictionary = _pack().get("npcs", {})
	assert_gt(authored.size(), 0, "CONTROL: the pack must author somebody")
	var covered: Array = []
	var placed_total := 0
	for floor_num in [1, 2, 3, 4]:
		var castle = await CastleFloor.build(self, floor_num)
		assert_not_null(castle, "CONTROL: the castle must build on floor %d" % floor_num)
		if castle == null:
			continue
		assert_eq(int(castle.total_floors), 4,
			"CONTROL: this arm walks floors 1-4; the castle now has %d" % int(castle.total_floors))
		assert_eq(int(castle.current_floor), floor_num,
			"CONTROL: floor %d was asked for and the castle built %d, so the rest of this arm would measure the wrong floor" % [
				floor_num, int(castle.current_floor)])

		var want: Array = []
		for npc_id in authored.keys():
			if int((authored[npc_id] as Dictionary).get("floor", 0)) == floor_num:
				want.append(str(npc_id))
		want.sort()

		var found: Dictionary = {}
		var cells: Dictionary = {}
		var stack: Array = [castle]
		while not stack.is_empty():
			var n = stack.pop_back()
			for c in n.get_children():
				stack.append(c)
			if n is OverworldNPC and str(n.name).begins_with("CastleNPC_"):
				found[str(n.npc_id)] = n
				var cell: String = str(Vector2i(n.position / float(castle.TILE_SIZE)))
				if cells.has(cell):
					fail_test("floor %d: two castle NPCs on cell %s: '%s' and '%s' — nearest-wins would make one unreachable" % [
						floor_num, cell, str(cells[cell]), str(n.npc_id)])
				cells[cell] = str(n.npc_id)

		var built: Array = found.keys()
		built.sort()
		assert_eq(built, want,
			"floor %d should hold exactly the NPCs the pack assigns it. built=%s authored=%s" % [
				floor_num, str(built), str(want)])
		for npc_id in found.keys():
			var npc = found[npc_id]
			assert_gt((npc.dialogue_lines as Array).size(), 0,
				"'%s' was placed with no lines — a silent NPC advertises a talk it cannot have" % str(npc_id))
			assert_true(npc.is_in_group("interactables"),
				"'%s' must be interactable or the player cannot reach its lines" % str(npc_id))
		placed_total += want.size()
		covered.append("f%d: %d" % [floor_num, want.size()])

	assert_eq(covered.size(), 4, "CONTROL: all four floors must have been measured, got %s" % str(covered))
	assert_eq(placed_total, authored.size(),
		"CONTROL: the floors together must account for all %d authored NPCs, not %d — one assigned to no floor reaches nobody" % [
			authored.size(), placed_total])
	gut.p("  " + ", ".join(covered))
