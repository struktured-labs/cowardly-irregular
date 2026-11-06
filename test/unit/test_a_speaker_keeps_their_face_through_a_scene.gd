extends GutTest

## The Calibrant revealed itself in world6_chapter3, then spoke all 13 playstyle-branch lines under the hood; Bram turned
## into a stranger for two lines in his own shop (cowir-cutscenes 2026-11-06). Rule, ORDERED: once a speaker has worn
## their own face in a scene, no later line of theirs wears a stock face. A hood-then-face reveal passes by construction.
## "Stock" is derived: a key that many different speakers wear is nobody's own face.

const CUTSCENES := "res://data/cutscenes/"
const GENERIC_SPEAKERS := 4


func _collect(o, out: Array) -> void:
	if o is Dictionary:
		if o.has("speaker") and o.has("portrait"):
			out.append({"speaker": str(o["speaker"]).strip_edges().to_lower(), "portrait": str(o["portrait"])})
		for v in o.values():
			_collect(v, out)
	elif o is Array:
		for v in o:
			_collect(v, out)


## {file: [lines in authored order]}, branch-nested lines included.
func _scenes() -> Dictionary:
	var out := {}
	for f in DirAccess.get_files_at(CUTSCENES):
		if f.ends_with(".json"):
			var found: Array = []
			_collect(JSON.parse_string(FileAccess.get_file_as_string(CUTSCENES + f)), found)
			out[f] = found
	return out


func _stock(scenes: Dictionary) -> Dictionary:
	var who := {}
	for f in scenes:
		for l in scenes[f]:
			if not who.has(l["portrait"]):
				who[l["portrait"]] = {}
			who[l["portrait"]][l["speaker"]] = true
	var out := {}
	for p in who:
		if (who[p] as Dictionary).size() >= GENERIC_SPEAKERS:
			out[p] = true
	return out


## A mood key is its base character, the way CutsceneDialogue resolves it: fighter_determined is the Fighter.
func _is_stock(key: String, stock: Dictionary) -> bool:
	return stock.has(key) or stock.has(key.get_slice("_", 0))


## "file: speaker loses <own> for <stock>" for every line that drops back to a stock face after its own.
func _lapses(scenes: Dictionary) -> Array:
	return _lapses_with(scenes, _stock(scenes))


func test_the_corpus_was_read() -> void:
	var scenes := _scenes()
	var n := 0
	for f in scenes:
		n += (scenes[f] as Array).size()
	assert_gt(n, 1000, "floor: every cutscene line was read (%d)" % n)
	var stock := _stock(scenes)
	assert_true(stock.has("mysterious") and stock.has("villager"), "CONTROL: the stock faces derive as stock")
	assert_false(_is_stock("calibrant", stock), "CONTROL: the Calibrant's own face is not stock")


func test_no_speaker_falls_back_to_a_stock_face() -> void:
	assert_eq(_lapses(_scenes()), [], "a speaker who has shown their own face keeps it for the rest of the scene")


## The rule must still SEE a lapse, and must let a reveal and a mood through.
func test_the_rule_tells_a_lapse_from_a_reveal() -> void:
	var stock := {"mysterious": true, "villager": true, "fighter": true}
	var lapse := {"t.json": [{"speaker": "bram", "portrait": "bram"}, {"speaker": "bram", "portrait": "villager"}]}
	var reveal := {"t.json": [{"speaker": "warden", "portrait": "mysterious"}, {"speaker": "warden", "portrait": "masterite_warden_medieval"}]}
	var mood := {"t.json": [{"speaker": "fighter", "portrait": "fighter_determined"}, {"speaker": "fighter", "portrait": "fighter"}]}
	assert_eq(_lapses_with(lapse, stock).size(), 1, "own face then a stock face is a lapse")
	assert_eq(_lapses_with(reveal, stock).size(), 0, "a hood then the own face is a reveal")
	assert_eq(_lapses_with(mood, stock).size(), 0, "a mood and its base are one character")


func _lapses_with(scenes: Dictionary, stock: Dictionary) -> Array:
	var out: Array = []
	for f in scenes:
		var own := {}
		for l in scenes[f]:
			var s: String = l["speaker"]
			var p: String = l["portrait"]
			if not _is_stock(p, stock):
				own[s] = p
			elif own.has(s) and stock.has(p) and p.get_slice("_", 0) != str(own[s]).get_slice("_", 0):
				out.append("%s: %s loses %s for %s" % [f, s, own[s], p])
	return out
