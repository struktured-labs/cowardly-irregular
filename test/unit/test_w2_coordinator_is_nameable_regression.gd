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


## Set by _npc_dialogue_blob so the read MODE is assertable. cowir-battle demonstrated 2026-09-09
## that source-text assertions certify a line EXISTS and say nothing about whether it RESOLVES --
## mutating a lookup to always return "" left their source-pin suite 6/6 green. So this guard
## instantiates the village and walks the real node tree; "source" is a FAILURE mode, not a fallback.
var _read_mode: String = ""


func _npc_dialogue_blob() -> String:
	_read_mode = ""
	var script: Script = load(VILLAGE_SRC)
	if script == null:
		return ""
	var village = script.new()
	if village == null:
		return ""
	add_child_autofree(village)
	await get_tree().process_frame
	var blob := _walk(village)
	if blob != "":
		_read_mode = "instantiated"
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
	## Known-present control -- a line an NPC actually SAYS. "HOA" was the original choice and it was
	## WRONG: it appears only in source COMMENTS, so it passed the source-text reader and failed the
	## moment this guard started walking real dialogue. A control has to be reachable by the same
	## path as the subject or it certifies the reader rather than the content.
	assert_true(blob.find("storm drain") >= 0,
		"control: Tyler's 'something in the storm drain' line must be reachable. Absent means the " +
		"walk found no dialogue, not that the content is missing.")
	assert_false(blob.find("zzq_not_a_line") >= 0, "control: a fabricated token must not appear")
	## Name the instrument. If this flips to "scene" the guard got STRONGER and should be re-read;
	## if it ever goes "" the read failed entirely and every assertion above was vacuous.
	## The village must have been INSTANTIATED and its NPCs actually added to the tree. A source-text
	## read would pass every assertion below while the NPC is never parented -- existence, not reach.
	assert_eq(_read_mode, "instantiated",
		"the guard must walk a live node tree, not read source. Mode was: '" + _read_mode + "'")


func test_the_coordinator_is_nameable_in_w2s_first_village() -> void:
	var blob: String = await _npc_dialogue_blob()
	assert_true(blob.find("Coordinator") >= 0,
		"No NPC in Maple Heights names the Coordinator, so W2's antagonist is introduced nowhere " +
		"the player can reach. The introduction lines exist only in " +
		"data/cutscenes/world2_maple_heights_npcs.json, which nothing plays.")
