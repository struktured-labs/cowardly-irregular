extends GutTest

## play_item's docstring claimed HP potions were silent BY DESIGN because "healing_done already
## plays `heal`". Both halves were false: heal_hp maps to `heal` in _ITEM_EFFECT_SFX so items DO
## cue, and the healing_done path is purely visual. The behaviour was right and the justification
## was wrong — which is the shape that makes the next reader delete a working cue.
## This pins the two FACTS the corrected comment asserts, not its wording.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const RESULTS := "res://src/battle/BattleResultsDisplay.gd"
const BATTLE_SCENE := "res://src/battle/BattleScene.gd"
const ITEMS := "res://data/items.json"


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


## A function's own body, comments stripped — so a `##` line mentioning a cue is not a call.
func _body(path: String, fn: String) -> String:
	var lines: PackedStringArray = GdSource.code_of(path).split("\n")
	var out := ""
	var inside := false
	for l in lines:
		if l.begins_with("func " + fn + "("):
			inside = true
			continue
		if inside:
			if l.begins_with("func ") or (l.length() > 0 and not l.begins_with("\t") and not l.strip_edges().is_empty()):
				break
			out += l + "\n"
	return out


func test_an_hp_healing_item_really_does_cue() -> void:
	## The half the old comment denied outright.
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(ITEMS))
	var items = parsed.get("items", parsed) if parsed is Dictionary else {}
	assert_true(items is Dictionary and (items as Dictionary).size() > 50,
		"CONTROL: items.json read back %s — this arm would judge an empty corpus" % [(items as Dictionary).size() if items is Dictionary else "nothing"])
	var hp_items: Array = []
	var cued: Array = []
	for iid in (items as Dictionary).keys():
		var e = (items as Dictionary)[iid]
		if not (e is Dictionary and e.get("effects") is Dictionary):
			continue
		var ef: Dictionary = e["effects"]
		if ef.has("heal_hp") or ef.has("heal_hp_percent"):
			hp_items.append(str(iid))
			if str(sm._item_sounds.get(str(iid), "")) != "":
				cued.append(str(iid))
	assert_gt(hp_items.size(), 0, "CONTROL: no HP-healing item authored — this arm measures nothing")
	assert_eq(cued.size(), hp_items.size(),
		"%d of %d HP-healing items resolve to NO cue — play_item would be silent for them, which is what the old comment wrongly described as the design" % [hp_items.size() - cued.size(), hp_items.size()])


func test_the_heal_cue_is_the_one_they_resolve_to() -> void:
	## Anti-overcorrection: "they cue at all" is satisfied by any mapping. The claim is that the
	## heal_hp row in _ITEM_EFFECT_SFX is live, and a hybrid still takes the MP cue above it.
	var sm: Node = _sm()
	if sm == null:
		return
	var cues := {}
	for iid in sm._item_sounds.keys():
		var c := str(sm._item_sounds[iid])
		cues[c] = int(cues.get(c, 0)) + 1
	assert_true(cues.has("heal"),
		"no item resolves to the `heal` cue — the heal_hp row in _ITEM_EFFECT_SFX is dead, so the corrected comment is now wrong in the other direction: %s" % str(cues))
	assert_true(cues.has("ability_mp_restore"),
		"no item takes the MP cue — the ordering comment above heal_hp ('LAST, so a hybrid takes the MP cue') describes nothing")


func test_the_healing_done_path_still_plays_nothing() -> void:
	## The other half. If a cue is ever added here, the doubling the old comment worried about
	## becomes REAL and play_item's docstring must be re-read — so this arm names that, rather
	## than forbidding the change.
	var relay: String = _body(BATTLE_SCENE, "_on_healing_done")
	assert_ne(relay, "", "CONTROL: BattleScene._on_healing_done not found — the scan anchors on it")
	assert_false(relay.contains("SoundManager."),
		"BattleScene._on_healing_done now plays a cue; play_item ALSO cues an HP potion, so the two would double on one heal — re-read play_item's docstring, it asserts this path is silent")
	var display: String = _body(RESULTS, "on_healing_done")
	assert_ne(display, "", "CONTROL: BattleResultsDisplay.on_healing_done not found")
	assert_false(display.contains("SoundManager."),
		"BattleResultsDisplay.on_healing_done now plays a cue — same doubling, one layer down")


func test_every_member_this_file_reaches_for_still_exists() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	## ⚠️ THIS LIST IS A SNAPSHOT, derived once from this file's own sm. reaches and frozen — NOT
	## a live derivation. Add a new sm. reach to this file and it is NOT covered until you add it here.
	assert_true(sm.has_method("play_item"), "SoundManager has no method play_item — this file is about it")
	assert_true(sm.get("_item_sounds") != null,
		"SoundManager has no _item_sounds — this file reaches for it directly")
	var consts: Dictionary = sm.get_script().get_script_constant_map()
	assert_true(consts.has("_ITEM_EFFECT_SFX"),
		"_ITEM_EFFECT_SFX is gone — the map both arms above describe")
