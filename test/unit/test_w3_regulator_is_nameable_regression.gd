extends GutTest
## The Regulator and the Grand Schedule are World 3's antagonist and its central mechanic. Every line
## introducing them lived in data/cutscenes/world3_brasston_npcs.json — one of six *_npcs.json files
## no src/ path plays (audit 2026-09-09) — so a player could walk W3's first village and never hear
## either name. Measured before: "Regulator" 0, "Grand Schedule" 0 in BrasstonVillage; control
## "Sprocket" present, so the reader worked and the zeros were real.
##
## ⛔ LIMIT: this proves the NPC is IN THE TREE CARRYING THESE LINES, not that a player can reach and
## talk to them. An NPC on a sealed ledge or missing an interaction Area2D passes every assertion
## here — all shipped in this repo the same week. CONTENT-reachable, never INTERACTION-reachable.

const VILLAGE_SRC := "res://src/maps/villages/BrasstonVillage.gd"

var _read_mode: String = ""


func _walk(n: Node) -> String:
	var out := ""
	if "dialogue_lines" in n:
		for l in (n.dialogue_lines as Array):
			out += str(l) + " "
	for c in n.get_children():
		out += _walk(c)
	return out


func _dialogue() -> String:
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


func test_the_village_dialogue_actually_read() -> void:
	var blob: String = await _dialogue()
	assert_gt(blob.length(), 400, "Brasston dialogue looks unread: " + str(blob.length()) + " chars")
	## Known-present control, reachable BY THE SAME PATH as the subject: a line an NPC speaks.
	## (An earlier guard of mine used a token that appears only in COMMENTS and passed on nothing.)
	assert_true(blob.find("perpetual motion") >= 0,
		"control: Sprocket's 'city of perpetual motion' line must be reachable")
	assert_false(blob.find("zzq_not_a_line") >= 0, "control: a fabricated token must not appear")
	## A source read would satisfy every assertion while the NPC is never parented.
	assert_eq(_read_mode, "instantiated",
		"must walk a live node tree, not read source. Mode was: '" + _read_mode + "'")


func test_w3s_antagonist_and_mechanic_are_nameable_in_its_first_village() -> void:
	var blob: String = await _dialogue()
	## Two DISJOINT claims: who is doing it, and what the thing is. Either alone leaves W3's premise
	## half-stated — a Regulator with no Schedule, or a Schedule nobody set.
	assert_true(blob.find("Regulator") >= 0,
		"No Brasston NPC names the Regulator, so W3's antagonist is introduced nowhere the player " +
		"can reach. The lines exist only in data/cutscenes/world3_brasston_npcs.json, which nothing plays.")
	assert_true(blob.find("Schedule") >= 0,
		"No Brasston NPC names the Schedule, W3's central mechanic. Same file, same reason.")
