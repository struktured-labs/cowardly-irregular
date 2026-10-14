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
					out.append({"map": path.get_file(), "field": field, "words": words, "text": t})
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


## ⛔ THE RECT WAS A LIE: a flat `Vector2(300, 36)` for a block that measures 296x80px at that width
## and font — five lines in a two-line box, +44px past it. A Label does not clip by default, so the
## overflow drew DOWNWARD from y=-58 over the prop being examined and the player beside it.
func test_every_toast_string_gets_a_rect_that_holds_it() -> void:
	var rows: Array = await _toast_strings()
	var grew := 0
	for r in rows:
		if QuestExaminePoint.toast_height_for(str(r["text"])) > QuestExaminePoint.TOAST_MIN_HEIGHT:
			grew += 1
	assert_gt(grew, 0,
		"not one of the %d toast strings needs more than the authored two-line box — either the corpus is wrong or the rect was never the problem" % rows.size())
	gut.p("  strings needing more than the %.0fpx two-line box: %d of %d" % [
		QuestExaminePoint.TOAST_MIN_HEIGHT, grew, rows.size()])


## 🔑 THE PLAYER-FACING INVARIANT: the label grows UPWARD. Its bottom edge must sit where the
## authored rect's bottom sat for EVERY string, so a longer line rises away from the player instead
## of covering them. This is the arm that would fail if someone grew the rect downward instead.
func test_a_longer_toast_grows_upward_not_over_the_player() -> void:
	var want: float = QuestExaminePoint.TOAST_BASELINE_Y + QuestExaminePoint.TOAST_MIN_HEIGHT
	var drifted: Array = []
	for r in await _toast_strings():
		## Both halves come from the SHIPPED seams. An earlier version of this arm recomputed the
		## position here, which reduces to BASELINE + MIN algebraically — it could not fail.
		var h: float = QuestExaminePoint.toast_height_for(str(r["text"]))
		var bottom: float = QuestExaminePoint.toast_position_for(str(r["text"])).y + h
		if absf(bottom - want) > 0.01:
			drifted.append("%s.%s (bottom %.1f, want %.1f)" % [r["map"], r["field"], bottom, want])
	assert_eq(drifted, [], "these toasts would extend below the authored baseline, over the player: %s" % [drifted])


## The floor still holds for a prompt-length string, so a short idle_text is not given a tall box.
func test_a_short_string_stays_at_the_floor() -> void:
	assert_eq(QuestExaminePoint.toast_height_for("Locked."), QuestExaminePoint.TOAST_MIN_HEIGHT,
		"a seven-character string must sit at the floor, not be measured below it")


## ⛔ THE SETTLED RECT, READ ONE LAYOUT PASS LATER — the arm @cowir-adhoc's bench thread earned.
## `Control.size` returns what you just assigned; the clamp to `get_minimum_size()` lands on the
## NEXT layout pass, so an immediate read agrees with the assignment on every ordering and proves
## nothing. Three in-repo benches disagreed because they read at different moments.
##
## 🔑 HEIGHT is structurally safe here and WIDTH is the open axis: the clamp only raises `size` UP to
## the minimum, and this toast assigns the MEASURED content height, so it cannot be raised past it.
## But if `autowrap_mode` were not live when `size` landed, the minimum WIDTH would be the content
## width and 300 would be raised to it — `ItemsMenu`'s 1068. This drives the real `_toast` and reads
## the rect after two frames, so it answers for the shipped path rather than for a bench label.
func test_the_settled_rect_is_the_one_the_toast_asked_for() -> void:
	var rows: Array = await _toast_strings()
	assert_gt(rows.size(), 0, "CONTROL: no corpus to drive the toast with")
	var longest: Dictionary = rows[0]
	for r in rows:
		if int(r["words"]) > int(longest["words"]):
			longest = r
	var text: String = str(longest["text"])

	var point := QuestExaminePoint.new()
	## ⛔ PLACE IT WHERE THE GAME PLACES PROPS. A bare `add_child_autofree` leaves the node at (0,0),
	## i.e. SCREEN y=0, and `WorldToast.show` now clamps a toast whose risen top would leave the
	## viewport (cowir-overworld, `573119452`: these are world-space labels under a camera at zoom
	## 2.0-2.5 with `limit_top = 0`, so a prop near a map's top edge draws high on screen and a long
	## examine ran off the top — at 100% text size for Frosthold). This string needs 122 px above its
	## prop (58 baseline + 44 growth + 20 rise), so at y=0 the clamp correctly fires and lowers the
	## label 126 px, and the baseline assert below would then be measuring the clamp.
	##
	## 🔑 The FIXTURE was the unrealistic half, not the clamp: the game cannot put a prop at screen
	## y=0 — row 0 is wall and the camera clamps at the map edge — so the nearest real geometry is a
	## prop with headroom beneath the top of the view.
	point.position = Vector2(0.0,
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 720)) * 0.75)
	add_child_autofree(point)
	## ⚠️ `_ready` already builds an INDICATOR Label (`:76`), so "the Label child" is ambiguous and
	## picking the last one found would silently measure the wrong node. Snapshot first, then take
	## the child that appeared.
	var before: Array = point.get_children()
	point._toast(text)
	var lbl: Label = null
	for kid in point.get_children():
		if kid is Label and not (kid in before):
			lbl = kid
	assert_not_null(lbl, "CONTROL: _toast must have ADDED a Label, distinct from the indicator, or this arm judges nothing")
	var immediate: Vector2 = lbl.size
	for _i in 2:
		await get_tree().process_frame

	var want_h: float = QuestExaminePoint.toast_height_for(text)
	gut.p("  %d words: immediate %s -> settled %s  (asked %.0fx%.0f)" % [
		int(longest["words"]), str(immediate), str(lbl.size), QuestExaminePoint.TOAST_WIDTH, want_h])
	assert_almost_eq(lbl.size.x, QuestExaminePoint.TOAST_WIDTH, 0.5,
		"the settled WIDTH is not the one assigned — autowrap was not live when size landed, so the minimum became the content width (ItemsMenu's 1068 shape)")
	assert_almost_eq(lbl.size.y, want_h, 0.5,
		"the settled HEIGHT is not what the font query predicted, so the position that holds the bottom edge is wrong by the difference")
	## CONTROL, and it names a cause the assert below would otherwise misattribute: a toast sitting
	## BELOW its prop means the on-screen clamp fired, which is a fixture-headroom problem rather
	## than the growth rule failing. Without this line a clamped toast reds the next assert with the
	## message "draws over the prop", which is true of the pixels and wrong about the reason.
	assert_lt(lbl.position.y + lbl.size.y, 0.0,
		"CONTROL: the toast sits BELOW its prop (bottom %.0f), so WorldToast's on-screen clamp fired — give the fixture more headroom; the baseline assert below is about the growth rule, not the clamp" % (lbl.position.y + lbl.size.y))
	assert_almost_eq(lbl.position.y + lbl.size.y,
		QuestExaminePoint.TOAST_BASELINE_Y + QuestExaminePoint.TOAST_MIN_HEIGHT, 0.5,
		"the settled bottom edge left the authored baseline, so a long examine draws over the prop and the player")


## ⛔ THE TOAST IGNORED THE TEXT SIZE SETTING. Every other surface showing authored story text scales
## through TextScale — CutsceneDialogue, BattleDialogue, BattleSpeechBubble — and this one drew a raw
## 11, so a player on 200% read every examine at 100%. The surface whose entire content is prose was
## the one the accessibility setting did not reach.
const PRESETS: Array = [0.8, 1.0, 1.25, 1.5, 2.0]

var _saved_scale: float = 1.0


func before_each() -> void:
	if GameState and "text_size_scale" in GameState:
		_saved_scale = float(GameState.text_size_scale)


func _restore_scale() -> void:
	if GameState and "text_size_scale" in GameState:
		GameState.text_size_scale = _saved_scale


func test_the_toast_font_follows_the_text_size() -> void:
	var seen: Array = []
	for scale in PRESETS:
		GameState.text_size_scale = scale
		seen.append(QuestExaminePoint.toast_font_size())
	_restore_scale()
	assert_eq(seen[1], QuestExaminePoint.TOAST_FONT_SIZE,
		"CONTROL: 100%% must be the authored base size, got %d" % seen[1])
	assert_gt(seen[4], seen[1],
		"200%% must draw larger than 100%%, got %d vs %d — the setting does not reach this surface" % [seen[4], seen[1]])
	assert_gt(seen[2], seen[1], "125%% must draw larger than 100%%")
	gut.p("  toast font at %s: %s" % [str(PRESETS), str(seen)])


## The rect must follow the font, or scaling it just clips — the defect this file's own subject was.
func test_the_rect_grows_with_the_font() -> void:
	var text: String = "A planted line long enough to wrap at this width, so that a larger font needs strictly more vertical room than a smaller one does."
	GameState.text_size_scale = 1.0
	var at_100: float = QuestExaminePoint.toast_height_for(text)
	GameState.text_size_scale = 2.0
	var at_200: float = QuestExaminePoint.toast_height_for(text)
	var pos_200: float = QuestExaminePoint.toast_position_for(text).y
	_restore_scale()
	assert_gt(at_200, at_100,
		"the toast rect did not grow with the font (%.0f at 100%%, %.0f at 200%%) — scaling without growing is the clip" % [at_100, at_200])
	assert_almost_eq(pos_200 + at_200,
		QuestExaminePoint.TOAST_BASELINE_Y + QuestExaminePoint.TOAST_MIN_HEIGHT, 0.5,
		"the bottom edge left the authored baseline at 200%%, so a scaled examine draws over the prop and the player")


## And what must NOT change: the hold is a property of WORD COUNT, not of how large the words are.
func test_the_hold_is_not_scaled() -> void:
	GameState.text_size_scale = 1.0
	var at_100: float = QuestExaminePoint.toast_hold_for(30)
	GameState.text_size_scale = 2.0
	var at_200: float = QuestExaminePoint.toast_hold_for(30)
	_restore_scale()
	assert_almost_eq(at_200, at_100, 0.01,
		"the hold changed with Text Size (%.2f -> %.2f) — reading time depends on how many words there are, not how big they are drawn" % [at_100, at_200])
