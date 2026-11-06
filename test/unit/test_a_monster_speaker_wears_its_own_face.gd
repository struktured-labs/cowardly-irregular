extends GutTest

## The World 5 Goblin is the Whispering Cave goblin ("Do you remember me?"), and all 18 of its lines wore a human
## villager's face while its artist sheet sat on disk (cowir-cutscenes 2026-11-06). The dragon guard covers boss intros
## a dungeon names; this one covers EVERY cutscene: a speaker named as a monster with art never wears a GENERIC face.
## "Generic" is derived, not listed: a portrait key that many different speakers wear is nobody's own face.

const DIALOGUE := "res://src/cutscene/CutsceneDialogue.gd"
const CUTSCENES := "res://data/cutscenes/"
## A face this many distinct speakers share is a stock face (mysterious, villager, shopkeeper...). Every boss's own is 1-2.
const GENERIC_SPEAKERS := 4
## A HUMAN who shares a monster's name by design, each with the reason. An entry that stops matching reds below.
const NAMESAKES := {
	"shift supervisor": "world4_chapter2's gatekeeper is a person with the title, not the W4 enemy; the managers ARE the monsters' template (cowir-story 22523)",
}

var _dialogue: Node = null


func _d() -> Node:
	if _dialogue == null:
		_dialogue = load(DIALOGUE).new()
		autofree(_dialogue)
	return _dialogue


func _collect(o, out: Array) -> void:
	if o is Dictionary:
		if o.has("speaker") and o.has("portrait"):
			out.append(o)
		for v in o.values():
			_collect(v, out)
	elif o is Array:
		for v in o:
			_collect(v, out)


## [{file, speaker, portrait}] for every authored line, branch-nested ones included.
func _lines() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(CUTSCENES):
		if not f.ends_with(".json"):
			continue
		var found: Array = []
		_collect(JSON.parse_string(FileAccess.get_file_as_string(CUTSCENES + f)), found)
		for l in found:
			out.append({"file": f, "speaker": str(l["speaker"]).strip_edges().to_lower(), "portrait": str(l["portrait"])})
	return out


func _generic_faces(lines: Array) -> Dictionary:
	var who := {}
	for l in lines:
		if not who.has(l["portrait"]):
			who[l["portrait"]] = {}
		who[l["portrait"]][l["speaker"]] = true
	var out := {}
	for p in who:
		if (who[p] as Dictionary).size() >= GENERIC_SPEAKERS:
			out[p] = true
	return out


## speaker (lowercase) -> monster id, by the monster's display name or its short name before ", the ...".
func _monster_speakers() -> Dictionary:
	var out := {}
	var mons = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	for id in mons:
		if not (mons[id] is Dictionary):
			continue
		var name := str(mons[id].get("name", "")).strip_edges().to_lower()
		if name == "":
			continue
		out[name] = id
		if name.contains(", "):
			out[name.get_slice(", ", 0)] = id
	return out


func _offenders() -> Dictionary:
	var lines := _lines()
	var generic := _generic_faces(lines)
	var monsters := _monster_speakers()
	var out := {}
	for l in lines:
		var id: String = monsters.get(l["speaker"], "")
		if id == "" or not generic.has(l["portrait"]) or _d().monster_art(id) == null:
			continue
		out["%s as %s in %s" % [l["speaker"], l["portrait"], l["file"]]] = l["speaker"]
	return out


func test_the_corpus_was_read() -> void:
	var lines := _lines()
	assert_gt(lines.size(), 1000, "floor: every cutscene line was read (%d)" % lines.size())
	var generic := _generic_faces(lines)
	assert_true(generic.has("mysterious") and generic.has("villager"), "CONTROL: the stock faces derive as generic (%s)" % str(generic.keys()))
	assert_false(generic.has("fire_dragon"), "CONTROL: a boss's own face is not generic")
	assert_eq(_monster_speakers().get("goblin", ""), "goblin", "CONTROL: the Goblin speaks as a monster")


func test_no_monster_with_art_wears_a_stock_face() -> void:
	var bad: Array = []
	for k in _offenders():
		if not NAMESAKES.has(_offenders()[k]):
			bad.append(k)
	assert_eq(bad, [], "a monster with a battle sheet speaks under its own face")


func test_a_namesake_still_shares_the_name() -> void:
	var still := {}
	for k in _offenders():
		still[_offenders()[k]] = true
	for s in NAMESAKES:
		assert_true(still.has(s), "'%s' no longer wears a stock face; drop it from NAMESAKES (%s)" % [s, NAMESAKES[s]])


func test_the_goblin_remembers_its_face() -> void:
	var tex: Texture2D = _d().portrait_texture("goblin")
	var art: Texture2D = _d().monster_art("goblin")
	assert_not_null(art, "the goblin has battle art")
	assert_true(tex != null and not (tex is ImageTexture), "'goblin' resolves to art, not the procedural goblin")
	if tex is AtlasTexture and art is AtlasTexture:
		assert_eq((tex as AtlasTexture).atlas, (art as AtlasTexture).atlas, "from the goblin's own sheet")
