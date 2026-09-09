extends GutTest
## The Coordinator is World 2's antagonist. Every line introducing them lived in
## data/cutscenes/world2_maple_heights_npcs.json -- one of six *_npcs.json files no src/ path plays
## (audit 2026-09-09) -- so a player could cross the portal, walk W2's first village, and never hear
## the name. Measured before the fix: "Coordinator" 0, "portal" 0 in MapleHeightsVillage; control
## "HOA" 2, so the reader worked and the zeros were real.
##
## Pins REACHABILITY of the name, not which NPC says it.

const VILLAGE := "res://src/maps/villages/MapleHeightsVillage.tscn"
const VILLAGE_SRC := "res://src/maps/villages/MapleHeightsVillage.gd"


## Set by _npc_dialogue_blob so the read MODE is assertable -- a silent fallback that works is the
## defect class this whole file exists for, and it would be absurd for the guard to have one.
var _read_mode: String = ""


func _npc_dialogue_blob() -> String:
	## Only HarmoniaVillage ships a .tscn today, so this village reads from SOURCE. That is fine and
	## it is asserted below, so if Maple ever gains a scene the mode change is visible rather than silent.
	var blob := ""
	_read_mode = ""
	if ResourceLoader.exists(VILLAGE):
		var packed: PackedScene = load(VILLAGE)
		if packed != null:
			var scene: Node = packed.instantiate()
			add_child_autofree(scene)
			await get_tree().process_frame
			blob = _walk(scene)
			if blob != "":
				_read_mode = "scene"
	if blob == "":
		var fh := FileAccess.open(VILLAGE_SRC, FileAccess.READ)
		if fh != null:
			blob = fh.get_as_text()
			fh.close()
			_read_mode = "source"
	return blob


func _walk(n: Node) -> String:
	var out := ""
	if "dialogue_lines" in n:
		for l in (n.dialogue_lines as Array):
			out += str(l) + " "
	for c in n.get_children():
		out += _walk(c)
	return out


func test_the_village_dialogue_actually_read() -> void:
	var blob: String = await _npc_dialogue_blob()
	assert_gt(blob.length(), 400, "Maple Heights dialogue looks unread: " + str(blob.length()) + " chars")
	## Known-present control: if this is absent the reader is broken, not the content.
	assert_true(blob.find("HOA") >= 0 or blob.find("hoa") >= 0,
		"control: 'HOA' must appear in Maple Heights dialogue")
	assert_false(blob.find("zzq_not_a_line") >= 0, "control: a fabricated token must not appear")
	## Name the instrument. If this flips to "scene" the guard got STRONGER and should be re-read;
	## if it ever goes "" the read failed entirely and every assertion above was vacuous.
	assert_eq(_read_mode, "source",
		"expected the SOURCE reader (MapleHeightsVillage has no .tscn). Mode was: '" + _read_mode + "'")


func test_the_coordinator_is_nameable_in_w2s_first_village() -> void:
	var blob: String = await _npc_dialogue_blob()
	assert_true(blob.find("Coordinator") >= 0,
		"No NPC in Maple Heights names the Coordinator, so W2's antagonist is introduced nowhere " +
		"the player can reach. The introduction lines exist only in " +
		"data/cutscenes/world2_maple_heights_npcs.json, which nothing plays.")
