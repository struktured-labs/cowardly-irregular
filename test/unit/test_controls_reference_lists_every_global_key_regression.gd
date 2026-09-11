extends GutTest

## The F1 controls reference is the ONLY place a player learns the global keys, and it is the
## screen struktured asked for by name ("it should be really easy to know all the buttons").
##
## Found by the reverse legend sweep: GameLoop binds KEY_F8 -> _write_feedback_bundle(), a
## screenshot + log + save + game state written as ONE FILE a tester can send back. It was named
## NOWHERE a player can see — not the overlay, not ControlsMenu, not a tutorial hint. His artist
## reports bugs in prose ("I tried a lot of keys"); the one feature built to replace that with an
## artifact was undiscoverable.
##
## ⚠️ SCOPE, STATED TO MATCH THE INSTRUMENT: this checks GLOBAL **F-KEYS ONLY** — the regex is
## `keycode == KEY_F<digits>`. GameLoop also binds ESCAPE, P, T, X and Y globally and this sees
## NONE of them. The filename says "every global key" and that is broader than what runs.
##
## This class is `feedback_label_broader_than_predicate` (2026-08-05), and its first line is why
## none of my controls caught it: A CONTROL TESTS THE EXPRESSION, AND THE EXPRESSION IS FINE. The
## regex correctly finds every F-key; the fabricated-key control correctly reports absence. Both
## true, and neither touches the gap between "every global key" and "every F-key".
##
## Recorded because cowir-main demonstrated the cost again on 2026-09-10: a predicate phrased more
## broadly than its implementation ("unreachable by ANY path", over a scanner that followed two of
## three link kinds) CONCEALS the gap, because broad-sounding language deters anyone from reading
## the code beneath it. An honest narrow claim gets interrogated; a confident wide one does not.
##
## So: next global NON-F key added is NOT caught by this. That is a gap to fill, not a covered case.

const GL := "res://src/GameLoop.gd"
const OVERLAY := "res://src/ui/HowToPlayOverlay.gd"

## NO SUPPRESSION LIST. There was one, holding "F5", and its stated reason — "printed on that
## editor's own legend" — was NEVER TRUE: F5 appears in zero on-screen strings in
## AutobattleGridEditor. @cowir-sfx named this shape FALSE (never true; the mechanism was simply
## unmodelled), distinct from EXPIRED, and it is the dangerous one because no rot check can catch
## it — there is no transition to detect. The entry was also UNNECESSARY: F5 is listed on the F1
## overlay, so the assertion passes without it. An exemption that is both false and unneeded reads
## as a considered decision and hides that nobody checked.


func _global_fkeys() -> Array:
	var src := FileAccess.get_file_as_string(GL)
	var re := RegEx.new()
	re.compile("keycode\\s*==\\s*KEY_(F\\d+)\\b")
	var out := []
	for m in re.search_all(src):
		var k := m.get_string(1)
		if not out.has(k):
			out.append(k)
	out.sort()
	return out


## THE RATCHET: every global F-key must appear in the reference the player is told to open.
func test_the_reference_lists_every_global_fkey() -> void:
	var keys := _global_fkeys()
	assert_gt(keys.size(), 3,
		"CONTROL: GameLoop must really bind several F-keys, else this sweep proves nothing (got %s)" % str(keys))
	var overlay := FileAccess.get_file_as_string(OVERLAY)
	assert_gt(overlay.length(), 0, "CONTROL: the overlay must be readable")
	for k in keys:
		assert_true(overlay.contains(k),
			"%s is bound globally and the controls reference never names it — the only screen that tells a player the keys" % k)


## The one that prompted this. Named explicitly so deleting the row is unambiguous, not just a
## count changing.
func test_the_bug_report_key_is_advertised() -> void:
	var overlay := FileAccess.get_file_as_string(OVERLAY)
	assert_true(overlay.contains("F8"),
		"F8 writes a screenshot + log + save bundle a tester can send back; it must be discoverable")
	assert_true(overlay.to_lower().contains("bug report"),
		"and the row must say what it DOES — 'F8' alone teaches nobody why to press it")


## The advertised key must be real. A reference that lies is the defect this lane spent the day
## removing; matching the COMPARISON, not the token, because a comment naming it cannot fail.
func test_the_advertised_key_is_actually_bound() -> void:
	var src := FileAccess.get_file_as_string(GL)
	var re := RegEx.new()
	re.compile("keycode\\s*==\\s*KEY_F8\\b")
	assert_not_null(re.search(src),
		"the overlay advertises F8, so something must COMPARE a keycode to KEY_F8")
	assert_true(src.contains("_write_feedback_bundle"),
		"and it must reach the bundle writer")
	var ctl := RegEx.new()
	ctl.compile("keycode\\s*==\\s*KEY_F97\\b")
	assert_null(ctl.search(src), "CONTROL: this binding check can report absence")


## ─────────────────────────────────────────────────────────────────────────────────────────────
## ACTION-SIDE SWEEP (2026-09-10). The F-key arms above are honest about seeing only F-keys; this
## narrows that documented gap from the other direction — every action the PROJECT declares must be
## named in the reference a player reads. It found `dash`: Shift / west face, a 1.7x run multiplier
## on the overworld, advertised nowhere, on a map that recently got bigger.
## Corpus is the 14 actions in project.godot's [input] — not Godot's ~50 built-ins.

## action -> why it needs no row. Each entry is a claim that can go stale, so it is checked below.
const NO_ROW_NEEDED := {
	"ui_up": "the D-Pad / Arrow Keys 'Navigate' row covers all four directions",
	"ui_down": "same row",
	"ui_left": "same row",
	"ui_right": "same row",
	"camera_rotate_left": "DEAD ACTION — no handler anywhere; Mode7Overlay.camera_angle is only ever set to 0.0. Advertising it would document a control that does nothing.",
	"camera_rotate_right": "DEAD ACTION — same. If camera rotation is ever implemented, delete this entry and add the row.",
}

## Human-facing words that count as advertising each action.
const ADVERTISED_AS := {
	"ui_accept": "Confirm",
	"ui_cancel": "Cancel",
	"ui_menu": "Start",
	"battle_advance": "Advance",
	"battle_defer": "Defer",
	"battle_toggle_auto": "Back (Minus)",  # the ROW's gamepad cell — "Toggle Autobattle" also appears in prose below the table
	"party_chat": "Defer / Party Chat",  # the ROW's description cell — "PARTY CHAT" is also a section header
	"dash": "1.7x",  # the multiplier, unique to its row — "Run" also matches "Turbo — run it faster"
}


func _project_actions() -> Array[String]:
	var src := FileAccess.get_file_as_string("res://project.godot")
	var start := src.find("[input]")
	assert_gt(start, -1, "project.godot must declare an [input] section")
	var stop := src.find("\n[", start + 1)
	var body := src.substr(start, (stop - start) if stop > start else -1)
	var out: Array[String] = []
	for m in RegEx.create_from_string("(?m)^([A-Za-z_][A-Za-z0-9_]*)=\\{").search_all(body):
		out.append(m.get_string(1))
	return out


## THE RATCHET: a new action must either get a row or say why it does not need one.
func test_every_project_action_is_advertised_or_declared() -> void:
	var actions := _project_actions()
	assert_gt(actions.size(), 5, "PRECONDITION: the roster must be real")
	var reference := (HowToPlayOverlay.build_text() + TitleScreen.build_confirm_cancel_rows("A", "B")).to_lower()
	var missing: Array[String] = []
	for a in actions:
		if NO_ROW_NEEDED.has(a):
			continue
		var word: String = str(ADVERTISED_AS.get(a, ""))
		if word == "" or not reference.contains(word.to_lower()):
			missing.append(a)
	assert_eq(missing, [] as Array[String],
		"a pressable action is named nowhere the player can read — that is how `dash` hid a run " +
		"button for months: %s" % [", ".join(missing)])


## dash specifically, because it is the one this sweep found and the row is easy to lose in an edit.
func test_the_run_button_is_named() -> void:
	var reference := HowToPlayOverlay.build_text().to_lower()
	assert_true(reference.contains("run"),
		"Shift / west face is a 1.7x run multiplier — a movement feature advertised nowhere")
	assert_true(reference.contains("shift"), "and the reference must name the key that does it")


## CONTROL: every NO_ROW_NEEDED entry must name a REAL action. An exemption for an action that no
## longer exists is an inert suppression, and it makes the list read as wider coverage than it has.
func test_no_exemption_is_stale() -> void:
	var actions := _project_actions()
	var inert: Array[String] = []
	for a in NO_ROW_NEEDED:
		if not actions.has(a):
			inert.append(a)
	assert_eq(inert, [] as Array[String],
		"an exemption names an action project.godot no longer declares — delete it: %s"
		% [", ".join(inert)])


## ─────────────────────────────────────────────────────────────────────────────────────────────
## CORPUS WIDENED (2026-09-10). The arms above scan GameLoop.gd ONLY, and that is exactly how F11
## hid: GamepadDiagnostic binds it in its OWN _input, so the file the ratchet reads never mentioned
## it. F11 opens the live pad readout — button and axis numbers — which is the single most useful
## screen for a pad whose mode switch moves its button indices, and it was surfaced only inside a
## NO-SDL-MAPPING warning row that a working pad never sees.
##
## This is the scope note above being narrowed by one measured case, not a claim that the file/key
## gap is closed: non-F global keys are still unscanned, and other scenes may bind their own.

const F_KEY_BINDERS := [
	"res://src/GameLoop.gd",
	"res://src/ui/GamepadDiagnostic.gd",
]


## Every global F-key bound in ANY of the scanned files must appear in the reference.
func test_every_bound_f_key_in_the_corpus_is_advertised() -> void:
	var reference := HowToPlayOverlay.build_text()
	var found: Array[String] = []
	var missing: Array[String] = []
	var re := RegEx.create_from_string("keycode\\s*==\\s*(KEY_F\\d+)\\b")
	for path in F_KEY_BINDERS:
		var src := FileAccess.get_file_as_string(path)
		assert_gt(src.length(), 0, "corpus file must be readable: %s" % path)
		for m in re.search_all(src):
			var key: String = m.get_string(1).replace("KEY_", "")
			if not found.has(key):
				found.append(key)
			if not reference.contains(key) and not missing.has(key):
				missing.append(key)
	assert_gt(found.size(), 3, "PRECONDITION: the corpus must yield real F-key bindings")
	assert_true(found.has("F11"),
		"CONTROL: F11 must be found — it is the binding this widening was added for, and if the " +
		"scan cannot see it the widening is inert")
	assert_eq(missing, [] as Array[String],
		"an F-key is bound but named nowhere the player reads: %s" % [", ".join(missing)])
