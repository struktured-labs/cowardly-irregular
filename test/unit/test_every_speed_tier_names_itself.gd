extends GutTest

## The speed readout is struktured's own ask ("battle speed does not show anywhere in battle except
## the logs", 2026-10-06). It is built and placed correctly -- the sibling file
## test_the_battle_speed_shows_on_screen_regression pins that. What nothing pinned is that it names
## a speed AT ALL for every rung of the ladder.
##
## ⛔ `_update_speed_indicator` matched `_battle_speed_index` with SEVEN hand-written arms and NO
## default, so an eighth tier renders the readout BLANK -- not wrong, EMPTY -- while the battle
## genuinely runs faster. With turbo on it reads " TURBO" and no number. That is the reported bug
## returning through the one door the fix for it left open.
##
## ⚠️ HONEST ABOUT REACHABILITY, because the fix is cheap and the overclaim is not: NO live player
## path reaches an unarmed index today. Every writer is bounded -- SaveSystem rejects a stored index
## outside the array, SettingsMenu writes a row index, GameLoop writes `SPEEDS.size() - 1`. The
## driver is a LADDER EDIT: one const line, in a file whose ladder has already been rescaled twice
## (the v2 raw-label reset and the v3 `speed_scale_v3` migration both live in SaveSystem). So this
## guards a future edit, which is the whole of its value -- it is not a bug he hit.
##
## 🔑 The two arrays are PARALLEL AND READ FROM THREE FILES: GameLoop derives an index from
## `BATTLE_SPEEDS`, the readout indexes `BATTLE_SPEED_LABELS` with it, SettingsMenu aliases both.
## A shorter LABELS is an out-of-bounds read, which ABORTS `_update_speed_indicator` -- so the
## readout freezes on the PREVIOUS speed and every line after the abort is skipped. Pinning the
## lengths is what makes the index safe to pass between them.

const BattleStateHelper := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const BS := preload("res://src/battle/BattleScene.gd")
const BS_PATH := "res://src/battle/BattleScene.gd"

var _bm: RefCounted = null
var _scene: Node = null
var _saved_index := 0
var _saved_scale := 1.0
var _saved_default = null


func before_each() -> void:
	_bm = BattleStateHelper.new()
	_bm.snapshot()
	_saved_index = BS._battle_speed_index   # static: outlives this file unless restored
	_saved_scale = Engine.time_scale
	_saved_default = GameState.default_battle_speed if "default_battle_speed" in GameState else null


func after_each() -> void:
	if _scene and is_instance_valid(_scene):
		_scene.queue_free()
	_scene = null
	BS._battle_speed_index = _saved_index
	Engine.time_scale = _saved_scale
	if _saved_default != null:
		GameState.default_battle_speed = _saved_default
	if _bm != null:
		_bm.restore()


func after_all() -> void:
	SoundState.restore()


func _battle() -> Node:
	_scene = load("res://src/battle/BattleScene.tscn").instantiate()
	add_child(_scene)
	await get_tree().process_frame
	return _scene


func _readout() -> RichTextLabel:
	return _scene.get_node_or_null("UI/SpeedPanel/SpeedIndicator") as RichTextLabel


## What the player reads once the arrow ramp and the turbo tag are taken off.
func _spoken_speed(label: RichTextLabel) -> String:
	var t: String = label.get_parsed_text()
	for decoration in ["▸", "◂", "TURBO"]:
		t = t.replace(decoration, "")
	return t.strip_edges()


## FLOOR, in its own frame so it shifts no other arm's statement order. Every arm below reaches
## `_update_speed_indicator` on the scene INSTANCE, which resolves at runtime and can therefore
## abort -- and each does so after its own first assert, which is rung 3: the abort would be
## SILENT and the file would score Passing. The consts are reached through `BS` (a parse-time
## class reference), so they need no floor: a missing one is EC=3, nothing ran, impossible to miss.
func test_the_readout_builder_is_still_called_what_these_arms_call_it() -> void:
	await _battle()
	assert_true(_scene.has_method("_update_speed_indicator"),
		"BattleScene must still expose _update_speed_indicator -- every arm here drives it by name, "
		+ "and a rename would abort them one line in, after their first assert, scoring green")


func test_the_speed_ladder_arrays_agree() -> void:
	assert_eq(BS.BATTLE_SPEEDS.size(), BS.BATTLE_SPEED_LABELS.size(),
		"BATTLE_SPEEDS and BATTLE_SPEED_LABELS are indexed by ONE counter across three files: "
		+ "GameLoop derives it from SPEEDS, the readout indexes LABELS with it. A shorter LABELS "
		+ "is an out-of-bounds read that aborts _update_speed_indicator, freezing the readout")


## Derived over the ladder, so a tier added tomorrow is covered without touching this file.
##
## ⚠️ EXACT, NOT `contains`. "2x" is a substring of "32x", so a contains-check would accept the 2x
## rung rendering the 32x label -- the same substring trap that widened a sweep through "quip" in
## "eQUIPment". Comparing the stripped text to the label catches a swap as well as a blank.
func test_every_tier_names_its_own_speed() -> void:
	await _battle()
	var label := _readout()
	assert_not_null(label, "PRECONDITION: the readout exists, or these arms prove nothing")
	if label == null:
		return
	var spoken: Array = []
	for i in BS.BATTLE_SPEEDS.size():
		BS._battle_speed_index = i
		_scene._update_speed_indicator()
		spoken.append(_spoken_speed(label))
	assert_eq(spoken, Array(BS.BATTLE_SPEED_LABELS),
		"every rung of the ladder must name its own speed; got %s" % [spoken])
	## CONTROL: an all-blank readout would also make two EMPTY arrays compare equal if the ladder
	## were ever emptied. Assert there was something to read.
	assert_gt(BS.BATTLE_SPEEDS.size(), 1,
		"CONTROL: a ladder with fewer than two rungs makes the comparison above vacuous")


## POSITIVE CONTROL FOR THE DEFAULT ARM, and the reason it is testable at all: GDScript indexes
## arrays from the END on a negative subscript, so -1 is a VALID label lookup ("64x") that matches
## NO arm in the `match`. Before the default arm this rendered the empty string. Index 7 cannot
## stand in for it -- that one is out of bounds and would abort rather than fall through.
func test_an_index_with_no_arm_still_names_the_speed() -> void:
	await _battle()
	var label := _readout()
	assert_not_null(label, "PRECONDITION: the readout exists")
	if label == null:
		return
	BS._battle_speed_index = -1
	_scene._update_speed_indicator()
	var spoken := _spoken_speed(label)
	assert_false(spoken.is_empty(),
		"an index with no arm must still name a speed -- blank is the reported bug, and the battle "
		+ "is running at that speed either way")
	assert_eq(spoken, str(BS.BATTLE_SPEED_LABELS[-1]),
		"the fallback must name the speed it is actually running at, not a guess")


## The arm itself, pinned at the source so it cannot be deleted silently -- the runtime arms above
## would keep passing without it only because they stay inside the armed range.
##
## ⚠️ READS THE CODE HALF, AND THE STRIP IS PRECAUTIONARY HERE RATHER THAN LOAD-BEARING -- MEASURED,
## because I first wrote the opposite. The explanatory block sits INSIDE the arm, below `_:`, so
## deleting the arm takes the prose with it (confirmed: the mutation that removes the arm leaves no
## trace of either), and the prose does not contain the literal token this asserts in any case. So a
## raw read would red too. What the strip buys is the NEXT edit: a `## _:` written anywhere in this
## function would satisfy a raw check with no arm present, which is how a sibling guard of mine went
## green through its own subject. Cheap, correct, and not yet carrying weight.
func test_the_readout_keeps_a_default_arm() -> void:
	var code: String = GdSource.code_of(BS_PATH)
	var body: String = ""
	var started := false
	for line in code.split("\n"):
		var l: String = str(line)
		if l.begins_with("func _update_speed_indicator("):
			started = true
			continue
		if started and l.begins_with("func "):
			break
		if started:
			body += l + "\n"
	assert_true(started, "PRECONDITION: _update_speed_indicator must be findable in the code half")
	assert_string_contains(body, "\n\t\t_:",
		"_update_speed_indicator's match over the speed index must keep its default arm, or the "
		+ "next tier added to the ladder renders the readout blank")
