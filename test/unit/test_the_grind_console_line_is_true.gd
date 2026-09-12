extends GutTest

const GdSource = preload("res://test/unit/helpers/gd_source.gd")

## Every control the grind console advertises must actually be bound where that line is shown.
##
## The line lives in BattleScene's autogrind console; the live handler during a grind is GameLoop's
## LoopState.AUTOGRIND branch. They are in different files, nothing joined them, and the two drifted:
## pause was KEY_P only, so this line dropped the token for pad players ON PURPOSE — then .328 bound
## pause to `battle_toggle_auto` and the comment explaining the omission silently became false. The
## control existed and the caption hid it, which is the same defect as advertising one that does not
## exist, arriving from the other side.
##
## So this guard is BIDIRECTIONAL and derived from both files: a token with no binding reds, and a
## binding with no token reds. Neither half can be satisfied by editing only one file.

const BS := "res://src/battle/BattleScene.gd"
const GL := "res://src/GameLoop.gd"


func _code_only(src: String, must_survive: String) -> String:
	## "".contains("") is TRUE, so an empty control passes while asserting nothing. Required is
	## not supplied (cowir-sfx/cowir-controller, 2026-09-12) — floor it rather than rely on
	## every call site happening to pass a real symbol.
	assert_gt(must_survive.length(), 0,
		"CONTROL: must_survive must name a real code site — an empty control asserts nothing")
	var stripped: String = str(GdSource.split(src)["code"])
	assert_true(stripped.contains(must_survive),
		"CONTROL: the stripper removed load-bearing code (%s) — every arm below it is vacuous" % must_survive)
	return stripped


func _bound_controls() -> Dictionary:
	var src: String = _code_only(FileAccess.get_file_as_string(GL), "func ")
	var i: int = src.find("LoopState.AUTOGRIND")
	assert_gt(i, -1, "CONTROL: the AUTOGRIND branch was found to read")
	var branch: String = src.substr(i, 4000)
	var out: Dictionary = {}
	if branch.contains("KEY_Y"):
		out["Turbo"] = true
	if branch.contains("JOY_BUTTON_LEFT_SHOULDER") or branch.contains("KEY_T"):
		out["Tier"] = true
	if branch.contains("ui_cancel"):
		out["Exit"] = true
	if branch.contains("KEY_P") or branch.contains("battle_toggle_auto"):
		out["Pause"] = true
	assert_gt(out.size(), 2, "CONTROL: bindings were actually read from the branch (%s)" % str(out.keys()))
	return out


## What the console line advertises ON THE PAD PATH specifically.
##
## ⚠️ The first version scanned the WHOLE function, and that made this guard blind to the very
## defect it was written for. The keyboard branch returns "…P:Pause" and returns EARLY, so a
## function-wide scan sees "Pause" advertised even when the pad path never names it — which is
## exactly the .328 staleness: keyboard fine, pad silent. Measured: reverting the fix red the
## derived-token arm and left this one GREEN. The pad path is everything after the keyboard
## early-return, so that is what gets read.
func _advertised() -> Dictionary:
	var src: String = _code_only(FileAccess.get_file_as_string(BS), "func ")
	var i: int = src.find("func _grind_console_controls")
	assert_gt(i, -1, "CONTROL: the console-line builder was found")
	var body: String = src.substr(i, src.find("\nfunc ", i + 10) - i)
	## The pad path begins at the first derivation, NOT at the `if` that guards the keyboard branch —
	## my first anchor cut one line too early and left the keyboard `return "…P:Pause"` inside the
	## window, which the control below caught on a CLEAN tree before it could flatter anything.
	var split: int = body.find("button_name_for_index(JOY_BUTTON_Y)")
	assert_gt(split, -1, "CONTROL: the pad path's first derivation was found, so it can be isolated")
	var pad_path: String = body.substr(split)
	## ⚠️ Third try at this control, and the first two were MY bugs rather than the subject's. The
	## marker has to be unique to the keyboard branch: `X/Esc:Exit` is not — the pad path carries it
	## as a per-token FALLBACK, and so is `Y:Turbo`. Only the whole early-return string appears
	## nowhere else. Each wrong version fired on a clean tree, which is the good direction to be
	## wrong in: a control that cries wolf gets fixed, one that sleeps does not.
	assert_false(pad_path.contains("Y:Turbo T:Tier X/Esc:Exit P:Pause"),
		"CONTROL: the isolated pad path must NOT still contain the keyboard early-return, or the "
		+ "split failed and this guard is reading both branches again")
	var out: Dictionary = {}
	for label in ["Turbo", "Tier", "Exit", "Pause"]:
		if pad_path.contains(":%s" % label):
			out[label] = true
	assert_gt(out.size(), 2, "CONTROL: tokens were actually read from the pad path (%s)" % str(out.keys()))
	return out


func test_every_advertised_control_is_bound() -> void:
	var bound := _bound_controls()
	var said := _advertised()
	var phantom: Array = []
	for label in said.keys():
		if not bound.has(label):
			phantom.append(str(label))
	assert_eq(phantom.size(), 0,
		"the grind console advertises a control the AUTOGRIND branch does not bind: "
		+ ", ".join(phantom) + " — either bind it in GameLoop's LoopState.AUTOGRIND branch, or drop "
		+ "the token from _grind_console_controls in src/battle/BattleScene.gd. A caption naming a "
		+ "control that does nothing is how `+/-: Speed` survived in the hint bar for six weeks")


func test_every_bound_control_is_advertised() -> void:
	## The half that caught this. .328 bound pause on a pad and the line went on hiding it, because
	## nothing required the caption to keep up with the binding — only the reverse.
	var bound := _bound_controls()
	var said := _advertised()
	var hidden: Array = []
	for label in bound.keys():
		if not said.has(label):
			hidden.append(str(label))
	assert_eq(hidden.size(), 0,
		"the AUTOGRIND branch binds a control the grind console never names: " + ", ".join(hidden)
		+ " — add its token to _grind_console_controls in src/battle/BattleScene.gd, derived through "
		+ "InputProfileManager.hint_for_action(<the action>) so a Controls rebind moves the caption "
		+ "with it. An unadvertised control is an undocumented mode")


func test_the_pause_token_is_derived_not_frozen() -> void:
	## Pause is the one whose pad binding is an ACTION rather than a raw key, so the caption must go
	## through the action or it freezes one family's letter.
	var src: String = _code_only(FileAccess.get_file_as_string(BS), "func ")
	var i: int = src.find("func _grind_console_controls")
	var body: String = src.substr(i, src.find("\nfunc ", i + 10) - i)
	assert_true(body.contains("hint_for_action(\"battle_toggle_auto\")"),
		"the pad pause token must be derived from battle_toggle_auto — GameLoop binds it as the "
		+ "ACTION precisely so a Controls rebind moves it, and a frozen caption would not follow")


func test_the_keyboard_line_still_names_the_key() -> void:
	## CONTROL for the arms above: a no-pad player pauses with P, and the derived path must not have
	## eaten the keyboard case while making the pad one work.
	var scene = load(BS).new()
	autofree(scene)
	if not Input.get_connected_joypads().is_empty():
		pending("a pad is connected in this harness; the no-pad line cannot be measured")
		return
	var line: String = scene._grind_console_controls()
	assert_true(line.contains("P:Pause"),
		"with no pad the console must still name the P key: '%s'" % line)
