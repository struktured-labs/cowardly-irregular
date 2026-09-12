extends GutTest

## The console binds four things to two keys: E exports rules to a file, Shift+E copies a COWIR1 share
## code, I imports from a file, Shift+I pastes a code. Measured before this fix, the bare arms read:
##
##     elif ... event.keycode == KEY_E and not event.is_echo():        # no shift exclusion
##
## So `Shift+E` satisfies the BARE arm too, and the chord won only because its arm sits EARLIER in the
## same elif chain. ⛔ That makes correctness a property of LINE ORDER: a refactor, a merge that
## reflows the chain, or someone grouping the arms differently silently turns "Copy Share Code" into
## "Export to File" — a player pressing Shift+E writes a file instead of filling their clipboard, and
## nothing errors. No test pressed either chord.
##
## Same reasoning already applied to KEY_R in this file, whose comment says it: excluding the chord
## explicitly beats depending on ordering, "which is tree ordering, not an asserted property."
##
## ⚠️ HONEST ABOUT WHAT THIS OBSERVES. I first wrote "these arms PRESS the keys and observe which
## route fires" — they do not, and could not: the four routes open file dialogs and touch the
## clipboard, which a headless run must not drive. The load-bearing arm asserts on the bare arm's OWN
## CONDITION (does it exclude shift?), which is order-INDEPENDENT and is the property at issue — a
## scan asserting "the shift arm comes first" would pass on the bug. One arm does press, KEY_H, purely
## as a control that the press plumbing reaches _input at all.

var _ui


func before_each() -> void:
	AutogrindSystem._test_disable_persistence = true
	_ui = preload("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(_ui)
	await get_tree().process_frame
	await get_tree().process_frame
	_ui.visible = true


func after_each() -> void:
	AutogrindSystem._test_disable_persistence = false


## The four routes, by the method each arm calls. Taken from the arms themselves, so a rename reds
## here rather than silently un-testing a route.
## ⚠️ I INVENTED ALL FOUR OF THESE NAMES ON THE FIRST DRAFT and the control arm below caught it —
## read off the arms, not from memory: _export_scripts / _import_scripts / _copy_rules_share_code /
## _paste_rules_share_code. A guessed symbol in a guard tests nothing while looking thorough.
const ROUTES := {
	"export": "_export_scripts",
	"import": "_import_scripts",
	"copy": "_copy_rules_share_code",
	"paste": "_paste_rules_share_code",
}


func _press(keycode: int, shift: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	ev.shift_pressed = shift
	_ui._input(ev)


## Every route named above must EXIST. A typo here would silently test nothing.
func test_all_four_share_routes_exist() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindUI.gd")
	for k in ROUTES.keys():
		assert_true(src.contains("func %s(" % ROUTES[k]),
			"this guard names '%s' as the %s route and no such function exists — the guard is testing nothing" % [ROUTES[k], k])


## ⛔ THE ARM THAT MATTERS: the bare key must not be reachable by the chord. Asserted on the CONDITION
## because the routes open file dialogs / touch the clipboard, which a headless test must not drive —
## but asserted on the bare arm's own text, not on which arm comes first.
func test_the_bare_arms_exclude_shift_so_order_cannot_matter() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindUI.gd")
	var problems: Array = []
	for line in src.split("\n"):
		var t: String = line.strip_edges()
		if not t.begins_with("elif event is InputEventKey"):
			continue
		for key in ["KEY_E", "KEY_I"]:
			if not t.contains("keycode == %s " % key):
				continue
			var is_chord_arm: bool = t.contains("and event.shift_pressed")
			if is_chord_arm:
				continue
			if not t.contains("not event.shift_pressed"):
				problems.append("%s bare arm does not exclude shift" % key)
	assert_eq(problems, [],
		("a bare E/I arm is reachable by its own Shift chord, so which route fires depends on elif " +
		"ORDER. Reflow the chain and Shift+E exports a file instead of copying a share code: %s") % [problems])


## The control: both chords must still HAVE their own arm. An over-eager fix that deleted the chord
## arms would satisfy the exclusion above while removing the feature.
func test_both_chords_still_have_their_own_arm() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindUI.gd")
	var chords := 0
	for line in src.split("\n"):
		var t: String = line.strip_edges()
		if t.begins_with("elif event is InputEventKey") and t.contains("and event.shift_pressed"):
			if t.contains("keycode == KEY_E ") or t.contains("keycode == KEY_I "):
				chords += 1
	assert_eq(chords, 2,
		"expected a Shift+E and a Shift+I arm, found %d — the share chords are gone, not hardened" % chords)


## The ring must advertise them AND a handler must exist for what it advertises.
## ⚠️ My first version only checked the LABELS, and that is a hole I found by predicting a count:
## moving the Shift+E arm to another keycode left the label "Copy Share Code   (Shift+E)" intact, so
## the arm passed while the chord did nothing. Predicted Failing 2, measured 1. The label and the
## handler are independent, so a guard that reads one certifies nothing about the other — this is the
## "promises a key that does not work" defect, on the ring instead of the hint strip.
func test_every_chord_the_ring_advertises_has_a_handler() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindUI.gd")
	var advertised: Array = []
	for o in _ui._options_ring_spec()["options"]:
		var label: String = str(o["label"])
		for chord in ["Shift+E", "Shift+I"]:
			if label.contains(chord) and not advertised.has(chord):
				advertised.append(chord)
	assert_eq(advertised.size(), 2,
		"the ring should advertise both share chords, found %s" % [advertised])

	var problems: Array = []
	for chord in advertised:
		var key: String = "KEY_" + chord.split("+")[1]
		var found := false
		for line in src.split("\n"):
			var t: String = line.strip_edges()
			if t.begins_with("elif event is InputEventKey") and t.contains("keycode == %s " % key) and t.contains("and event.shift_pressed"):
				found = true
		if not found:
			problems.append("%s is advertised but no `%s and event.shift_pressed` arm exists" % [chord, key])
	assert_eq(problems, [],
		"the ring promises a chord the console does not handle — pressing it does nothing, or worse falls through to the bare key's route: %s" % [problems])


## Pressing a BARE key must not be swallowed either — the exclusion must be on shift, not on the key.
## Observed through the tree: the export route opens a dialog, so assert the console handled the event
## rather than driving the dialog itself.
func test_a_bare_press_is_still_handled() -> void:
	## KEY_H is a plain toggle with no chord sibling and no dialog — a safe positive control that the
	## press plumbing in this guard actually reaches the console's _input at all.
	var before: bool = _ui._ludicrous_speed_enabled
	_press(KEY_H, false)
	assert_ne(_ui._ludicrous_speed_enabled, before,
		"CONTROL: a bare KEY_H press did not reach _input, so every press in this file proves nothing")
