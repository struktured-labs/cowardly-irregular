extends GutTest

## MY OWN REGRESSION, found by sweeping bound keys against the strings a screen shows.
##
## 1199a259 (mine) replaced AutogrindUI's footer — "[1/2/3]: Presets  [4-6]: Custom  [S]: Save
## [D]: Del  [E/I]: Files  [Sh+E/I]: Codes" — with a pad-oriented hint strip that names none of
## those keys. The options ring I added in the same commit carried no key hints either, unlike
## AutobattleGridEditor's ring which has always shown "(E)", "(Tab)". So a KEYBOARD player lost
## the on-screen list of nine working keys, on a screen that already has a commit titled
## "autogrind start discoverability — user couldn't find the binding".
##
## Every hint here was read off the handler, not remembered. A label naming the wrong key would be
## the same defect one layer over.

const UI := "res://src/ui/autogrind/AutogrindUI.gd"

## id -> the key its handler is actually bound to, verified against the elif chain
const EXPECTED := {
	"ludicrous": "H", "permadeath": "P", "auto_advance": "W", "toggle_row": "Tab",
	"preset_casual": "1", "preset_standard": "2", "preset_hardcore": "3",
	"save_preset": "S", "delete_preset": "D",
	"custom_1": "4", "custom_2": "5", "custom_3": "6",
	"export": "E", "import": "I", "copy_code": "Shift+E", "paste_code": "Shift+I",
}

var _vp: SubViewport = null
var _ui: Control = null


func before_each() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	add_child_autofree(_vp)
	var layer := CanvasLayer.new()
	_vp.add_child(layer)
	_ui = load(UI).new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_ui)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if _ui and is_instance_valid(_ui):
		_ui.queue_free()
	_ui = null


func _labels() -> Dictionary:
	var out := {}
	for opt in (_ui._options_ring_spec().get("options", []) as Array):
		out[str(opt.get("id", ""))] = str(opt.get("label", ""))
	return out


## Behavioural: every row whose verb HAS a key must print that key.
func test_every_keyed_row_names_its_key() -> void:
	var labels := _labels()
	var checked := 0
	for id in EXPECTED:
		assert_true(labels.has(id), "the ring must still offer '%s'" % id)
		var want: String = "(%s)" % EXPECTED[id]
		assert_true(labels[id].contains(want),
			"row '%s' must name its key %s so a keyboard player can learn it — got: %s" % [id, want, labels[id]])
		checked += 1
	assert_eq(checked, EXPECTED.size(), "every expected row must have been inspected")


## THE HALF THAT MATTERS: a hint must be TRUE. Each named key must be bound in the handler.
func test_every_named_key_is_actually_bound() -> void:
	var src := FileAccess.get_file_as_string(UI)
	for id in EXPECTED:
		var key: String = EXPECTED[id]
		var bare := key.replace("Shift+", "")
		# Match the BINDING FORM, not the token. Two weaker versions were measured hollow here:
		# contains("KEY_P") passed on KEY_PLUS, and a word-boundary match then passed on my own
		# COMMENT saying "permadeath was KEY_P only". Prose cannot fail; a comparison can.
		var re := RegEx.new()
		re.compile("keycode\\s*==\\s*KEY_%s\\b" % bare.to_upper())
		assert_not_null(re.search(src),
			"row '%s' advertises %s but nothing COMPARES a keycode to KEY_%s" % [id, key, bare.to_upper()])
	var ctl := RegEx.new()
	ctl.compile("KEY_ZZQ\\b")
	assert_null(ctl.search(src), "CONTROL: the binding check can report absence")
	var sub := RegEx.new()
	sub.compile("keycode\\s*==\\s*KEY_P\\b")
	assert_not_null(sub.search(src),
		"CONTROL: a real KEY_P COMPARISON exists — not KEY_PLUS, and not a comment naming it")


## Rows with NO key must not invent one. cycle_member/cycle_ability are pad-only by design.
func test_unkeyed_rows_claim_no_key() -> void:
	var labels := _labels()
	for id in ["cycle_member", "cycle_ability"]:
		if not labels.has(id):
			continue
		assert_false(labels[id].contains("("),
			"row '%s' has no key binding and must not imply one — got: %s" % [id, labels[id]])


## CONTROL: the ring must be non-empty and larger than the keyed set, or the arms above are
## inspecting a corpus that cannot fail.
func test_the_ring_is_really_populated() -> void:
	var labels := _labels()
	assert_gt(labels.size(), EXPECTED.size(),
		"the ring carries more rows than the keyed ones (pad-only rows exist), got %d" % labels.size())
