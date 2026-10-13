extends GutTest

## ⛔ QUEST EXAMINE TEXT COULD NOT BE READ. `QuestExaminePoint._toast` held a flat 2.2s with the fade
## starting at 1.0s, so the label was gone 3.2s after the press, while the strings it carries run to
## 43 words — about 10s of reading at 250 wpm. The player saw a line or two and it left. Fixed in
## `bad66e791` by deriving the hold from the word count.
##
## ⛔ AND THE FIRST VERSION OF THIS FILE JUDGED THE WRONG POPULATION. It built its corpus from
## `data/examine_texts.json` — 45 authored rows that never reach this renderer at all. Those are
## placed as `ReadableProp`, a paged panel the player dismisses, by BOTH `BaseVillage:904` and
## `BaseInterior`. I had grepped `examine_text =`, landed on `BaseVillage:610`, and taken it for the
## pack placer; it is `_add_quest_examine_point`, 300 lines above the real one. The arms passed and
## asserted nothing about this renderer — a corpus that could not fail.
##
## 🔑 SO THE CORPUS IS NOW BUILT, NOT PARSED: each map is instantiated and the tree walked for nodes
## that actually carry `examine_text`. A regex over positional call arguments would be guessing at
## which string is the `examined` one; the node knows.
##
## Related rule, the hard way: a data-side corpus cannot see a defect that only exists once the
## scene tree is up. Same reason my nine pack-reading files were green on a placement bug.

const DIRS := ["res://src/maps/villages", "res://src/maps/dungeons"]
const NOT_A_MAP := ["BaseVillage.gd", "DragonCave.gd", "BossTrigger.gd", "HeightGrid.gd", "VillageProp.gd", "VillageLighting.gd"]

## An independent reading rate, deliberately FASTER than the implementation's 4 words/sec. A
## restatement of the formula would pass by construction; 5 w/s is a bound the formula must beat, so
## lowering WORDS_PER_SECOND below 5 reds this file.
const FAST_READER_WPS := 5.0

## Strings this short are prompts, not prose — they are not what the defect was about.
const PROSE_WORDS := 8


func _map_scripts() -> Array:
	var out: Array = []
	for dir in DIRS:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f in d.get_files():
			if f.ends_with(".gd") and not (f in NOT_A_MAP):
				out.append("%s/%s" % [dir, f])
	return out


## Every string that actually reaches `_toast`, collected from the LIVE tree: a node carrying
## `examine_text` is a QuestExaminePoint, and `ReadableProp` carries a provider callable instead.
## ⚠️ CACHED: three arms ask for this corpus and each build instantiates every village and dungeon.
## Uncached that is three full map-set builds per run (8.8s measured) — and a test slow enough to
## read as infrastructure is the failure this repo keeps paying for. The cached rows are plain
## dictionaries of strings and counts, never node references, so `add_child_autofree` freeing the
## instances between tests cannot invalidate them.
var _corpus: Array = []
var _corpus_built: bool = false


func _toast_strings() -> Array:
	if _corpus_built:
		return _corpus
	var out: Array = []
	for path in _map_scripts():
		var scr = load(path)
		if scr == null or not scr.can_instantiate():
			continue
		var inst = scr.new()
		if not (inst is Node):
			continue
		add_child_autofree(inst)
		for _i in 3:
			await get_tree().process_frame
		for node in _walk(inst):
			if not ("examine_text" in node):
				continue
			for field in ["examine_text", "idle_text"]:
				var t: String = str(node.get(field))
				var words: int = t.split(" ", false).size()
				if words >= PROSE_WORDS:
					out.append({"map": path.get_file(), "field": field, "words": words})
	_corpus = out
	_corpus_built = true
	return out


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for kid in n.get_children():
		out.append_array(_walk(kid))
	return out


func test_the_corpus_is_built_and_non_trivial() -> void:
	var rows: Array = await _toast_strings()
	assert_gt(rows.size(), 9,
		"CONTROL: only %d toast-fed prose strings found in the live maps — without a real population the arm below judges nothing" % rows.size())
	var maps: Dictionary = {}
	for r in rows:
		maps[r["map"]] = true
	assert_gt(maps.size(), 3, "CONTROL: the population must span several maps, saw %d" % maps.size())
	gut.p("  toast-fed prose strings: %d across %d maps" % [rows.size(), maps.size()])


## The arm the defect would have failed: every string that reaches the timed toast must outlast a
## FAST read, bounded by the deliberate ceiling.
func test_every_toast_string_outlasts_a_fast_read() -> void:
	var short: Array = []
	for r in await _toast_strings():
		var words: int = int(r["words"])
		var need: float = minf(float(words) / FAST_READER_WPS, QuestExaminePoint.MAX_HOLD_SECONDS)
		var got: float = QuestExaminePoint.toast_hold_for(words)
		if got + 0.001 < need:
			short.append("%s.%s (%d words: %.2fs held, %.2fs needed)" % [r["map"], r["field"], words, got, need])
	assert_eq(short, [], "these fade before a fast reader finishes them: %s" % [short])


## Monotonic inside the band, clamped at both ends — a constant hold passes none of these, and none
## of it depends on which population feeds the renderer.
func test_the_hold_tracks_the_text() -> void:
	assert_gt(QuestExaminePoint.toast_hold_for(40), QuestExaminePoint.toast_hold_for(20),
		"a longer line must hold longer, or the hold is not derived from the text at all")
	assert_eq(QuestExaminePoint.toast_hold_for(1), QuestExaminePoint.MIN_HOLD_SECONDS,
		"a one-word line must sit at the floor, not below it")
	assert_eq(QuestExaminePoint.toast_hold_for(100000), QuestExaminePoint.MAX_HOLD_SECONDS,
		"a pathological line must sit at the ceiling, not pin the label forever")
	assert_lt(QuestExaminePoint.MIN_HOLD_SECONDS, QuestExaminePoint.MAX_HOLD_SECONDS,
		"CONTROL: the clamp band must be non-empty or the arms above are vacuous")


## The old flat lifetime as a CONSEQUENCE, not a spelling: a 20-word string must now outlast the
## 3.2s the whole label used to live for.
func test_a_prose_string_outlasts_the_old_whole_lifetime() -> void:
	assert_gt(QuestExaminePoint.toast_hold_for(20), 3.2,
		"a 20-word examine holds only %.2fs — the label used to live 3.2s, so this is not an improvement" % QuestExaminePoint.toast_hold_for(20))
