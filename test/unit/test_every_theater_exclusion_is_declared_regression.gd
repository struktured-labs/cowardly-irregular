extends GutTest

## The Theater's roster is every cutscene on disk MINUS three ID SUBSTRINGS, at
## CutsceneGallery.gd: `if "guidance" in id or "encounter" in id or "npcs" in id: continue`,
## commented "Guidance hints + encounter barks aren't story beats".
##
## ⛔ MEASURED 2026-09-16: that line drops 18 scenes and 12 OF THEM ARE LIVE — content a player
## reaches in the ordinary way and can then never replay. They are not barks:
##     4 x world1_*_encounter   titled beats ("The Arbiter of Steel"), letterboxed, music-cued,
##                              assigned as an NPC's cutscene_id in three villages + TallyWall
##     8 x world*_guidance_*    PartyChatSystem.REGISTRY, player-initiated from PartyChatMenu
##     6 x world*_npcs          the only genuinely unplayed ones, 0 callers
##
## ⚠️ THIS GUARD DOES NOT RULE ON THAT. Whether the twelve belong in the Theater is struktured's
## and cowir-story's call, not a test's. What it refuses is the SILENCE: a substring over ids
## captures whatever happens to be named that way, and nothing on screen says which scenes it
## took. The roster below is the deliverable version of that comment — you cannot silence this
## green, only explain it green, and the explanation is the fix (CLAUDE.md's rule for a guard
## over two sources where the author cannot see which wins).
##
## 🔑 THE TERMS ARE READ OUT OF THE GALLERY, NOT COPIED HERE. A guard that hardcodes the three
## strings passes intact while the filter it defends says something else entirely — the same
## defect as a scanner whose step-type list is written from memory rather than derived from the
## dispatcher, which this lane shipped twice in one evening.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")

const GALLERY := "res://src/ui/CutsceneGallery.gd"
const CUTSCENE_DIR := "res://data/cutscenes/"

## Every scene the filter hides, and whether anything can play it. LIVE means a real caller
## exists in src/; UNPLAYED means none does. Both halves are asserted below, so an entry that
## goes stale reds instead of sitting here as decoration.
const HIDDEN := {
	"world1_arbiter_encounter": "LIVE",       # GrimhollowVillage NPC cutscene_id
	"world1_curator_encounter": "LIVE",       # IronhavenVillage NPC cutscene_id
	"world1_tempo_encounter": "LIVE",         # EldertreeVillage NPC cutscene_id
	"world1_warden_encounter": "LIVE",        # TallyWall
	"world1_guidance_capital": "LIVE",        # PartyChatSystem.REGISTRY
	"world1_guidance_cave": "LIVE",
	"world1_guidance_forest": "LIVE",
	"world2_guidance_explore": "LIVE",
	"world3_guidance_mechanism": "LIVE",
	"world4_guidance_director": "LIVE",
	"world5_guidance_core": "LIVE",
	"world6_guidance_question": "LIVE",
	"world1_eldertree_npcs": "UNPLAYED",
	"world1_harmonia_npcs": "UNPLAYED",
	"world2_maple_heights_npcs": "UNPLAYED",
	"world2_oak_street_npcs": "UNPLAYED",
	"world3_brasston_npcs": "UNPLAYED",
	"world4_rivet_row_npcs": "UNPLAYED",
}

const SRC_DIRS := ["res://src/"]


## The filter's own terms, parsed out of the line that applies them.
func _filter_terms() -> Array:
	var code: String = GdSource.code_of(GALLERY)
	var terms: Array = []
	for raw in code.split("\n"):
		var line: String = (raw as String).strip_edges()
		if not line.begins_with("if ") or not line.ends_with(" in id:"):
			continue
		if line.count(" in id") < 2:
			continue
		# `if "a" in id or "b" in id or "c" in id:` — every quoted literal on the line.
		var parts: PackedStringArray = line.split("\"")
		var i := 1
		while i < parts.size():
			terms.append(parts[i])
			i += 2
		break
	return terms


func _scene_ids() -> Array:
	var ids: Array = []
	var dir := DirAccess.open(CUTSCENE_DIR)
	if dir == null:
		return ids
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".json"):
			var fh := FileAccess.open(CUTSCENE_DIR + f, FileAccess.READ)
			if fh != null:
				var json := JSON.new()
				if json.parse(fh.get_as_text()) == OK and json.data is Dictionary:
					var d: Dictionary = json.data
					# The Gallery drops these before the substring test — match it exactly.
					if str(d.get("id", "")) != "" and int(d.get("world", 0)) > 0:
						ids.append(str(d["id"]))
				fh.close()
		f = dir.get_next()
	dir.list_dir_end()
	return ids


func _hidden_by_filter() -> Array:
	var terms := _filter_terms()
	var out: Array = []
	for id in _scene_ids():
		for t in terms:
			if str(id).contains(str(t)):
				out.append(id)
				break
	out.sort()
	return out


func _src_code_blob() -> String:
	var parts: PackedStringArray = []
	var stack: Array = SRC_DIRS.duplicate()
	while not stack.is_empty():
		var d: String = str(stack.pop_back())
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if dir.current_is_dir():
				if not f.begins_with("."):
					stack.append(d + f + "/")
			elif f.ends_with(".gd"):
				parts.append(GdSource.code_of(d + f))
			f = dir.get_next()
		dir.list_dir_end()
	return "\n".join(parts)


## ANTI-VACUITY: if the line moves or changes shape, every arm below compares empty sets.
func test_the_filter_terms_are_read_out_of_the_gallery() -> void:
	var terms := _filter_terms()
	assert_eq(terms.size(), 3,
		"expected three id substrings on the Gallery's filter line, parsed %s — if that line " % [terms] +
		"changed shape this guard is measuring nothing")
	for t in terms:
		assert_gt(str(t).length(), 3, "a filter term must be a real substring, got %s" % [t])


## ANTI-VACUITY: an empty corpus makes "every exclusion is declared" true by construction.
func test_the_cutscene_corpus_is_really_scanned() -> void:
	var ids := _scene_ids()
	assert_gt(ids.size(), 150, "expected the full cutscene corpus, read %d ids" % ids.size())
	assert_true(ids.has("world1_prologue"), "a known scene must be among them")


func test_every_scene_the_theater_hides_is_declared_here() -> void:
	var hidden := _hidden_by_filter()
	var declared: Array = HIDDEN.keys()
	declared.sort()
	assert_eq(hidden, declared,
		"the Theater hides a scene this roster does not name (or names one it no longer hides). " +
		"A new id containing 'guidance', 'encounter' or 'npcs' leaves the Theater SILENTLY — " +
		"add it above with LIVE or UNPLAYED and say which caller reaches it. hidden=%s" % [hidden])


## The reciprocal pin: the status column is only worth having if it cannot quietly become a lie.
## Comments are stripped first — MapleHeightsVillage.gd names world2_maple_heights_npcs in PROSE,
## recording a voice migrated off it, and a raw scan counts that as a caller.
func test_every_status_in_the_roster_still_holds() -> void:
	var blob := _src_code_blob()
	assert_gt(blob.length(), 200000, "src/ looks truncated: %d chars of code" % blob.length())
	assert_true(blob.contains("_get_pending_story_cutscene"), "control: a known src symbol survives the strip")

	for id in HIDDEN:
		var referenced: bool = blob.contains("\"%s\"" % id)
		if HIDDEN[id] == "LIVE":
			assert_true(referenced,
				"%s is declared LIVE but no src/ code names it — if it was unwired, change it to " % id +
				"UNPLAYED; it is now hidden from the Theater AND unreachable, which nothing else reports")
		else:
			assert_false(referenced,
				"%s is declared UNPLAYED but src/ code names it now. If it was wired up, it is a " % id +
				"scene a player can see and cannot replay — mark it LIVE and raise the roster with struktured")
