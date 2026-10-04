extends GutTest

## BattleScene handles three RAW keycodes and two RAW pad buttons — outside the InputMap entirely,
## so the action-side sweep in test_controls_reference_lists_every_global_key_regression cannot see
## them. That sweep's scope note says as much; this is the companion for the raw half.
##
## What it found: **"Repeat last turn's actions" was completely undocumented.** Y key, west face
## button, and NOTHING else — no command-menu row, not in the F1 reference, not in CLAUDE.md's
## Battle Controls table, not in the hint bar. In a CTB game where you queue up to four actions
## across five characters, repeating the whole previous turn in one press is the largest time-saver
## in the battle UI, and the only way to find it was to read BattleScene.
##
## ⚠️ SCOPE: BattleScene's raw branches only. Other scenes bind their own raw keys (the grid editors
## use Delete/Backspace and Shift+E/I) and are NOT scanned here. Stated because the filename could
## be read as "every raw battle key in the game", which is broader than what runs.

const BS := "res://src/battle/BattleScene.gd"

## raw binding -> the words that must appear in the F1 reference for it. A key here is a claim that
## a player can discover the binding; it is checked against the reference, never assumed.
const MUST_BE_NAMED := {
	"KEY_QUOTELEFT": "Battle speed",
	"KEY_Y": "Repeat last turn",
	"KEY_F": "Cycle party formation",
	"JOY_BUTTON_Y": "Battle speed",
	"JOY_BUTTON_X": "Repeat last turn",
}


func _battle_source() -> String:
	var src := FileAccess.get_file_as_string(BS)
	assert_gt(src.length(), 1000, "PRECONDITION: BattleScene must be readable")
	return src


func _raw_bindings() -> Array[String]:
	var src := _battle_source()
	var out: Array[String] = []
	var keys := RegEx.create_from_string("event\\.keycode == (KEY_[A-Z_0-9]+)")
	var btns := RegEx.create_from_string("event\\.button_index == (JOY_BUTTON_[A-Z_]+)")
	for re in [keys, btns]:
		for m in re.search_all(src):
			var binding: String = m.get_string(1)
			if not out.has(binding):
				out.append(binding)
	out.sort()
	return out


## CONTROL FIRST: a scanner returning nothing makes every arm below vacuously green.
func test_the_scanner_finds_the_raw_bindings() -> void:
	var found := _raw_bindings()
	assert_gt(found.size(), 3, "PRECONDITION: BattleScene must yield real raw bindings")
	assert_true(found.has("KEY_Y"), "CONTROL present: KEY_Y repeats the previous turn")
	assert_true(found.has("JOY_BUTTON_X"), "CONTROL present: the west face button does too")
	assert_false(found.has("KEY_F19"), "CONTROL absent: the scan can report a key missing")


## THE RATCHET. Every raw binding BattleScene handles must be findable in the F1 reference.
func test_every_raw_battle_binding_is_advertised() -> void:
	var reference := HowToPlayOverlay.build_text()
	var missing: Array[String] = []
	for binding in _raw_bindings():
		var words: String = str(MUST_BE_NAMED.get(binding, ""))
		if words == "":
			missing.append("%s (no declared description at all)" % binding)
		elif not reference.contains(words):
			missing.append("%s -> expected \"%s\"" % [binding, words])
	assert_eq(missing, [] as Array[String],
		"a raw binding BattleScene handles is named nowhere the player reads — that is how " +
		"Repeat-last-turn stayed invisible: %s" % [", ".join(missing)])


## CONTROL: no MUST_BE_NAMED entry may be inert. An entry for a binding BattleScene no longer
## handles is a promise about a key that does nothing, and it inflates the apparent coverage.
func test_no_declared_binding_is_stale() -> void:
	var found := _raw_bindings()
	var inert: Array[String] = []
	for binding in MUST_BE_NAMED:
		if not found.has(binding):
			inert.append(binding)
	assert_eq(inert, [] as Array[String],
		"a declared binding is no longer handled by BattleScene — delete it: %s" % [", ".join(inert)])


## The feature itself must still exist. If the repeat handler is ever removed, the row this test
## forced into the reference becomes a lie in the other direction.
func test_the_repeat_feature_still_exists() -> void:
	var src := _battle_source()
	assert_true(src.contains("func _repeat_previous_actions"),
		"the repeat handler must exist, or the reference now advertises a key that does nothing")
	assert_true(src.contains("BattleManager.repeat_previous_actions()"),
		"and it must reach BattleManager — the row promises it repeats the whole party's turn")
