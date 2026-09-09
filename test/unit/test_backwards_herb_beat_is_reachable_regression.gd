extends GutTest
## The backwards-healing herb is the seed of the Scriptweaver arc: a healing item with a
## flipped sign is an EDITED CONSTANT, not blight. It was authored in
## data/cutscenes/world1_eldertree_npcs.json -- a file NO src/ path references, so no player
## could ever reach it (audit 2026-09-09: 6 *_npcs.json cutscenes, 77 lines, 0 src refs).
## It now lives on a live village NPC. This pins REACHABILITY, not which NPC carries it.

##
## ⛔ WHAT THIS GUARD DOES NOT PROVE (stated 2026-09-09, from cowir-battle's retraction: "a test that
## calls the repaired function directly cannot tell either -- reachability is not a property you can
## observe from inside the thing you are reaching").
## It proves the NPC is IN THE TREE CARRYING THESE LINES. It does NOT prove a player can reach and
## talk to them. An NPC standing on a sealed one-tile ledge, behind a prop footprint, or with a
## missing interaction Area2D passes every assertion below -- and all three of those shipped in this
## repo this week. "reachable" in the filename means CONTENT-reachable, never INTERACTION-reachable.
## The instrument for the latter is a navigation/interaction probe and it does not live in this lane.

const VILLAGE_DIR := "res://src/maps/villages/"
## Any one of these phrases is the beat; a rewrite may keep the idea and drop a word.
const BEAT_MARKERS := ["healed the wrong direction", "heals backwards", "healing herb"]


func _village_sources() -> Dictionary:
	var out := {}
	var dir := DirAccess.open(VILLAGE_DIR)
	assert_not_null(dir, "village dir must open: " + VILLAGE_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".gd"):
			var fh := FileAccess.open(VILLAGE_DIR + f, FileAccess.READ)
			if fh != null:
				out[f] = fh.get_as_text()
				fh.close()
		f = dir.get_next()
	dir.list_dir_end()
	return out


func test_village_sources_actually_loaded() -> void:
	var src := _village_sources()
	## Domain claim, not a shape claim: if this dir ever stops loading, every assert below
	## passes vacuously on an empty dictionary.
	assert_gt(src.size(), 8, "expected the full village set, got " + str(src.size()))
	assert_true(src.has("EldertreeVillage.gd"), "EldertreeVillage.gd must be among them")
	var total := 0
	for k in src:
		total += (src[k] as String).length()
	assert_gt(total, 20000, "village sources look truncated: " + str(total) + " chars")


func test_backwards_herb_beat_reachable_from_a_live_npc() -> void:
	var src := _village_sources()
	var carriers: Array = []
	for fname in src:
		var text: String = src[fname]
		for marker in BEAT_MARKERS:
			if text.to_lower().find(marker) >= 0:
				carriers.append(fname)
				break
	assert_gt(carriers.size(), 0,
		"the backwards-herb beat is not on ANY village NPC -- it exists only in " +
		"data/cutscenes/world1_eldertree_npcs.json, which no src/ path plays, so no player " +
		"can reach it. Markers searched: " + str(BEAT_MARKERS))


func test_the_beat_sits_inside_an_npc_dialogue_array() -> void:
	## Reachability means a player can TALK to someone. A marker in a comment would satisfy
	## the test above while remaining invisible in game.
	var src := _village_sources()
	var found_in_dialogue := false
	for fname in src:
		var text: String = src[fname]
		for line in text.split("\n"):
			var s: String = (line as String).strip_edges()
			if s.begins_with("#"):
				continue
			if s.begins_with("\"") and s.to_lower().find("wrong direction") >= 0:
				found_in_dialogue = true
				break
		if found_in_dialogue:
			break
	assert_true(found_in_dialogue,
		"the beat must be a quoted dialogue string on an NPC, not a comment or an identifier")
