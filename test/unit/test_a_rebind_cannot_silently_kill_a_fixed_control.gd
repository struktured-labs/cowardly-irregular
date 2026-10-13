extends GutTest

## ⛔ REBIND THE BATTLE LOG ONTO THE NORTH FACE AND BATTLE SPEED STOPS WORKING, SILENTLY, FOREVER.
## Battle speed is raw `JOY_BUTTON_Y` and Repeat-last-turn is raw `JOY_BUTTON_X` in
## `BattleScene._input`. Neither has an InputMap action, so neither can be rebound and neither
## appears as a row on the Controls screen. The action arms in that same `_input` run BEFORE the raw
## arms and every arm calls `set_input_as_handled()` and returns — so the moved action wins and the
## fixed control is unreachable, with nothing on any screen naming it.
##
## 🔑 `binding_would_trap_the_player` is structurally blind to this: it compares the candidate button
## against OTHER ACTIONS' indices, and these two are not actions. And the capture accepts it —
## ControlsMenu's own comment is "# Any other button = capture it".
##
## ⚠️ A WARNING, NOT A REFUSAL, and the arm below pins that: it is recoverable (rebind away), and the
## north face is a binding players have always been allowed — the symmetric refusal was measured and
## rejected in `FIELD_MENU_REFUSES`. What the player lacks is not permission but INFORMATION, since
## the shadowed control is on no row they can read.

const IPM_PATH := "res://src/input/InputProfileManager.gd"
const BS_PATH := "res://src/battle/BattleScene.gd"
const GL_PATH := "res://src/GameLoop.gd"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")

var _ipm: Node


func before_each() -> void:
	_ipm = load(IPM_PATH).new()
	add_child_autofree(_ipm)


func test_the_warning_names_the_control_and_the_action() -> void:
	var out: Dictionary = _ipm.binding_would_shadow_a_fixed_control("battle_open_log", [JOY_BUTTON_Y])
	assert_true(out.get("shadows", false),
		"moving the battle log onto the north face must be reported — that face is battle speed")
	if not out.get("shadows", false):
		return  ## the two asserts below describe the message; with no message they only add noise
	var why: String = str(out.get("reason", ""))
	assert_string_contains(why, "Battle speed",
		"the message must NAME the control that will stop working, or the player cannot act on it")
	assert_string_contains(why, "cannot be rebound",
		"and must say why they will not find it on this screen")


## ⛔ ONE BUTTON, TWO FIXED CONTROLS, AND THEY DIE IN DIFFERENT CONTEXTS. `JOY_BUTTON_Y` is battle
## speed in `BattleScene._input` and the autogrind turbo toggle in `GameLoop._input:1279` (gated on
## `LoopState.AUTOGRIND`, `ui_cancel` consuming above it at `:1274`). Naming one sends the player
## hunting the other, so the message must name every entry on that button.
func test_the_message_names_every_control_on_that_button() -> void:
	var out: Dictionary = _ipm.binding_would_shadow_a_fixed_control("ui_cancel", [JOY_BUTTON_Y])
	assert_true(out.get("shadows", false), "PRECONDITION: Cancel onto the north face shadows")
	if not out.get("shadows", false):
		return
	var why: String = str(out.get("reason", ""))
	for name in _ipm.fixed_controls_on(JOY_BUTTON_Y):
		assert_string_contains(why, str(name),
			"the warning must name EVERY control this button carries, missing '%s'" % name)
	## ⚠️ THIS ARM CANNOT CATCH A NAME BEING DROPPED, and the honest reason is worth stating: it
	## iterates the const, so deleting an entry deletes the requirement. A missing NAME is prose --
	## nothing in the source says "these two controls share this button" -- which is exactly why the
	## turbo one was found by a person reading GameLoop and not by a guard. What IS derivable is that
	## every raw button handled in those two scopes HAS an entry, and the arm below does that.


func test_the_other_fixed_face_is_covered_too() -> void:
	var out: Dictionary = _ipm.binding_would_shadow_a_fixed_control("ui_cancel", [JOY_BUTTON_X])
	assert_true(out.get("shadows", false), "the west face is Repeat-last-turn, same shape")
	if not out.get("shadows", false):
		return  ## else the next assert reports an empty-string error over the real cause
	assert_string_contains(str(out.get("reason", "")), "Repeat",
		"and the message must name THAT control, not a generic one")


## NEGATIVE DIRECTION: the check must stay quiet where there is nothing to say, or it is noise that
## trains the player to dismiss it.
func test_an_ordinary_rebind_says_nothing() -> void:
	for probe in [["battle_open_log", JOY_BUTTON_A], ["ui_cancel", JOY_BUTTON_B],
			["battle_advance", JOY_BUTTON_Y]]:
		var out: Dictionary = _ipm.binding_would_shadow_a_fixed_control(str(probe[0]), [int(probe[1])])
		assert_false(out.get("shadows", false),
			"%s onto button %d shadows nothing and must be silent" % [probe[0], probe[1]])
	## battle_advance onto the north face is the interesting quiet case: its arm runs in
	## _unhandled_input, AFTER the raw arm, so the raw control still wins and nothing breaks.


## ⛔ THE ARM THAT KEEPS THIS HONEST. `SHADOWING_ACTIONS` is a statement about the ORDER of arms in
## BattleScene._input, and that order lives in BattleScene. A copy in InputProfileManager drifts the
## day someone moves an arm, so this derives the order from the source and reds on disagreement.
func test_the_shadowing_list_matches_battlescenes_arm_order() -> void:
	## BOTH files, because the const is now a claim about both: BattleScene's whole _input, and
	## GameLoop's AUTOGRIND block only (its raw turbo arm is inside that gate, so an action outside
	## it cannot shadow it). One scan, two scopes -- not a second derivation to maintain.
	##
	## ⚠️ THE GAMELOOP SCOPE CANNOT CHANGE TODAY'S ANSWER AND I AM NOT PRETENDING IT CAN: the only
	## remappable action above its raw arm is `ui_cancel`, which BattleScene's scope already yields,
	## so the union is identical with or without it. What it buys is the PRECONDITION below -- it reds
	## if GameLoop's raw turbo arm moves above the gate or disappears -- and it buys correctness the
	## day an action arm is added there. A scope that contributes nothing yet is worth its two lines
	## only because the const now makes a claim about that file; without the claim it would be noise.
	var seen: Array = []
	var scoped := 0
	for spec in [[BS_PATH, "func _input("], [GL_PATH, "if current_state == LoopState.AUTOGRIND:"]]:
		var lines: PackedStringArray = GdSource.code_of(str(spec[0])).split("\n")
		var inside := false
		var first_raw := -1
		for i in lines.size():
			var l: String = str(lines[i])
			if not inside:
				if l.contains(str(spec[1])):
					inside = true
				continue
			if first_raw < 0 and l.contains("button_index == JOY_BUTTON_Y"):
				first_raw = i
				break
			if l.contains("is_action_pressed("):
				for a in _ipm.REMAPPABLE_ACTIONS:
					if l.contains('is_action_pressed("%s")' % a) and not seen.has(a):
						seen.append(a)
		assert_gt(first_raw, 0,
			"PRECONDITION: %s must still reach a raw JOY_BUTTON_Y arm after '%s'" % [spec[0], spec[1]])
		if first_raw > 0:
			scoped += 1
	assert_eq(scoped, 2, "PRECONDITION: both scopes must have been read, or the union is partial")
	seen.sort()
	var pinned: Array = _ipm.SHADOWING_ACTIONS.duplicate()
	pinned.sort()
	assert_eq(seen, pinned,
		"SHADOWING_ACTIONS must equal the remappable actions whose arm precedes the raw JOY_BUTTON_Y "
		+ "arm in BattleScene._input. Derived %s, pinned %s — if an arm moved, move this list" % [seen, pinned])


## ⛔ THE ARM THE OTHERS DO NOT COVER: every assert above drives the API DIRECTLY, so deleting
## ControlsMenu's call would leave all of them green while the player sees nothing. The warning is
## only worth having if the capture path raises it, and that is a fact about ControlsMenu's source.
## Read from the CODE half, because the explanatory comment beside the call names this very function.
func test_the_capture_path_actually_raises_the_warning() -> void:
	var code: String = GdSource.code_of("res://src/ui/ControlsMenu.gd")
	assert_string_contains(code, "binding_would_shadow_a_fixed_control",
		"ControlsMenu's capture must ASK — the API alone warns nobody")
	if code.find("binding_would_shadow_a_fixed_control") < 0:
		return  ## else the asserts below substr(-1) and report an empty-string error instead
	## And it must reach the player: the result has to go through the flash, not be dropped.
	var idx: int = code.find("binding_would_shadow_a_fixed_control")
	var tail: String = code.substr(idx, 600)
	assert_string_contains(tail, "_show_flash",
		"the answer must be shown; a computed warning that is never displayed is the defect again")
	## ...and the bind must still be applied BEFORE the check, or this became a refusal by accident.
	var head: String = code.substr(maxi(0, idx - 400), 400)
	assert_string_contains(head, "set_custom_binding",
		"the bind must already have landed when the warning is raised — warning, not refusal")


## ✅ THE DERIVABLE HALF: every raw pad button handled in the two shadowing scopes must HAVE an
## entry in FIXED_PAD_CONTROLS. This catches a whole BUTTON being missed (a third raw arm added
## tomorrow), which is the part the source can answer. Which named controls share a button is not in
## the source and stays a human read.
func test_every_raw_button_in_those_scopes_has_an_entry() -> void:
	## ⛔ A REGEX, NOT substr ARITHMETIC. My first version did `t.substr(at + 18)` against a
	## 27-character needle, so every extracted name was a fragment, nothing ever matched the face
	## table and THE ARM COULD NOT FAIL -- it passed the mutation that removes the whole entry. Caught
	## by running that mutation, not by reading it.
	var re := RegEx.new()
	re.compile("button_index == (JOY_BUTTON_[A-Z_]+)")
	var found: Array = []
	for spec in [[BS_PATH, "func _input("], [GL_PATH, "if current_state == LoopState.AUTOGRIND:"]]:
		var lines: PackedStringArray = GdSource.code_of(str(spec[0])).split("\n")
		var inside := false
		for l in lines:
			var t: String = str(l)
			if not inside:
				if t.contains(str(spec[1])):
					inside = true
				continue
			if t.begins_with("func "):
				break
			var m := re.search(t)
			if m != null and not found.has(m.get_string(1)):
				found.append(m.get_string(1))
	assert_gt(found.size(), 0, "PRECONDITION: at least one raw button arm must be findable")
	## CONTROL: the extractor must yield REAL constant names, not fragments. This is the assert my
	## broken substr version would have failed, and the reason it is here rather than in a comment.
	assert_true(found.has("JOY_BUTTON_Y"),
		"CONTROL: the extractor must produce whole JOY_BUTTON_* names; got %s" % [found])
	## Only the FACE buttons can collide with these two entries; a shoulder or stick arm is a
	## different control set and is out of this arm's claim.
	var face_index := {"JOY_BUTTON_A": JOY_BUTTON_A, "JOY_BUTTON_B": JOY_BUTTON_B,
		"JOY_BUTTON_X": JOY_BUTTON_X, "JOY_BUTTON_Y": JOY_BUTTON_Y}
	var missing: Array = []
	for name in found:
		if face_index.has(name) and _ipm.fixed_controls_on(int(face_index[name])).is_empty():
			missing.append(name)
	assert_eq(missing, [],
		"a raw pad button handled in a shadowing scope has no FIXED_PAD_CONTROLS entry, so a rebind "
		+ "onto it warns about nothing: %s (found %s)" % [missing, found])


## ⛔ THE ARM THAT WOULD HAVE SAVED THE `.681` FOLD. I first wrote this const as
## `{JOY_BUTTON_Y: [...], JOY_BUTTON_X: [...]}` -- a non-empty Dictionary whose every value is an
## Array, which is EXACTLY the shape `test_input_profile_binding_coverage_regression._profiles()`
## uses to recognise a pad profile. It was counted as a fourth profile whose buttons were control
## names, and every arm demanding a profile cover `ui_accept`/`ui_cancel` red. `REFUSED_SHARES`
## two consts above carries that warning verbatim and I introduced the shape anyway.
##
## ✅ So this REPRODUCES THE PREDICATE rather than pinning the container type by name: whatever
## shape the const takes, it must not satisfy the profile test. A rename cannot defeat this and a
## future reshape is caught at the source.
func test_the_const_is_not_mistaken_for_a_pad_profile() -> void:
	var script: Script = load(IPM_PATH)
	var consts: Dictionary = script.get_script_constant_map()
	assert_true(consts.has("FIXED_PAD_CONTROLS"), "PRECONDITION: the const must be reachable here")
	if not consts.has("FIXED_PAD_CONTROLS"):
		return
	var value = consts["FIXED_PAD_CONTROLS"]
	## The predicate, copied from _profiles() so it moves only when that one does.
	var looks_like_a_profile := value is Dictionary and not (value as Dictionary).is_empty()
	if looks_like_a_profile:
		for action in value:
			if not value[action] is Array:
				looks_like_a_profile = false
	assert_false(looks_like_a_profile,
		"FIXED_PAD_CONTROLS must NOT be a non-empty Dictionary of Arrays -- that is how the binding "
		+ "coverage guard recognises a pad profile, and it would demand this const cover ui_accept")
	## CONTROL: the predicate must be able to say YES, or the assert above is vacuous.
	var decoy := {"ui_accept": [1], "ui_cancel": [0]}
	var decoy_matches := decoy is Dictionary and not decoy.is_empty()
	for action in decoy:
		if not decoy[action] is Array:
			decoy_matches = false
	assert_true(decoy_matches, "CONTROL: the copied predicate must match a real profile shape")


## The bind must still LAND. This is the line between a warning and the refusal path, and a future
## edit that routed this through binding_would_trap_the_player would take the player's choice away.
func test_the_shadowing_bind_is_still_applied() -> void:
	var before: Array = _ipm.get_current_button_indices("battle_open_log")
	_ipm.set_custom_binding("battle_open_log", [JOY_BUTTON_Y])
	var after: Array = _ipm.get_current_button_indices("battle_open_log")
	assert_true(JOY_BUTTON_Y in after,
		"a shadowing bind is WARNED about, not refused — the player keeps the choice (was %s, now %s)"
			% [before, after])
