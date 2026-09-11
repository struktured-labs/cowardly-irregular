extends GutTest

## cowir-controller derived the hint bar and the interact prompts, then found their own ratchet is
## structurally blind to the UNBRACKETED form — it matches `"[A]` and glyphs, so `"Press A"`,
## `"A:Confirm"` and `"Sel:Auto"` are the same frozen caption in three costumes it cannot see. Four
## of the surfaces they listed are in my files. These are those four.
##
## What a player got: an Xbox or PlayStation player was told to press buttons their pad does not
## have — and on a DualSense "X" is ✕, which is CANCEL, so the speed hint named the wrong button
## rather than a missing one.
##
## Speed is the odd one and it is why this file exists rather than a fifth arm on theirs: it is raw
## JOY_BUTTON_Y with NO InputMap action, so `hint_for_action` cannot reach it. Win98Menu already
## owned that pad/keyboard decision for the hint bar, so BattleScene now ASKS it (`speed_hint()`)
## rather than restating it — the same move as routing the headless resolver through `billed_ap`.

const BATTLE_SCENE := "res://src/battle/BattleScene.gd"
const GRID_EDITOR := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const WIN98 := "res://src/ui/Win98Menu.gd"

## ⚠️ COMMENTS BLANKED. cowir-controller 2026-09-11: a source pin is satisfied by the COMMENT, so it
## catches the tidy removal and misses the realistic one — nobody deletes a line without leaving the
## note explaining it. Measured on THIS file: swapping the derivation back for a literal "X" with
## `## was: Win98MenuClass.speed_hint()` beside it left all five arms GREEN. Line count preserved.
## Cut at the first `#` OUTSIDE a string. LOOKAHEAD, not lookbehind (cowir-overworld 2026-09-11):
## a backslash consumes the NEXT char atomically, so `"a\\"` correctly reads as a closed string.
## Lookbehind asks "was the previous char an escape?" — a question with no local answer, since the
## backslash may itself be escaped, and that is the sixth costume this class produced today.
## Latent here (10 lines carry \" across the two files I scan, none beside a later #) — retired by
## construction rather than by an arm someone has to remember. Line count preserved for substr.
func _strip_comments(raw: String) -> String:
	var out: Array = []
	for line in raw.split("\n"):
		var i := 0
		var in_d := false
		var in_s := false
		var cut := -1
		while i < line.length():
			var c := line[i]
			if c == "\\":
				i += 2
				continue
			if c == '"' and not in_s:
				in_d = not in_d
			elif c == "'" and not in_d:
				in_s = not in_s
			elif c == "#" and not in_d and not in_s:
				cut = i
				break
			i += 1
		out.append(line.substr(0, cut) if cut > -1 else line)
	return "\n".join(out)
func _src(p: String) -> String:
	var raw := FileAccess.get_file_as_string(p)
	assert_gt(raw.length(), 1000, "CONTROL: read %s" % p)
	return _strip_comments(raw)

func test_no_battle_caption_hardcodes_a_nintendo_button() -> void:
	## The literals as they shipped. Each names a button that is wrong or absent on two of the three
	## pad families, and none is reachable by a bracketed-token scan.
	var frozen := {
		BATTLE_SCENE: ["Press X (or the ` key)", "Press R to queue"],
		GRID_EDITOR: ["A:Confirm", "B:Cancel", "A:Import", "Sel:Auto", "A:Edit", "B/Esc:Back", "Del/Y:Delete"],
	}
	var found: Array = []
	for path in frozen:
		var s := _src(path)
		for lit in frozen[path]:
			if s.contains(lit):
				found.append("%s: \"%s\"" % [path.get_file(), lit])
	assert_eq(found.size(), 0,
		"a player-facing caption names a button by its Nintendo spelling: " + str(found))

func test_the_captions_derive_instead() -> void:
	## The other half: absence of the literal is not presence of a derivation. Deleting the whole
	## line would satisfy the arm above.
	var bs := _src(BATTLE_SCENE)
	assert_true(bs.contains("Win98MenuClass.speed_hint()"),
		"the speed hint must ask the one place that knows raw JOY_BUTTON_Y")
	assert_true(bs.contains("hint_for_action(\"battle_advance\")"),
		"the Advance hint must derive from its InputMap action")
	var ge := _src(GRID_EDITOR)
	assert_eq(ge.count("InputProfileManager.hint_for_action("), 9,
		"the grid editor has NINE pad tokens across FOUR help lines — the sweep that found it reported two lines, its own scan found three, the file has four")

func test_speed_has_no_inputmap_action_so_the_helper_is_the_only_route() -> void:
	## The premise, measured rather than asserted. If someone later ADDS a battle_speed action, this
	## reds and the helper should be retired in favour of hint_for_action — which is the outcome I
	## would want, not a failure.
	var proj := FileAccess.get_file_as_string("res://project.godot")
	assert_gt(proj.length(), 100, "CONTROL: read project.godot")
	assert_true(proj.contains("battle_advance"), "CONTROL: battle_* actions are declared here")
	assert_false(proj.contains("battle_speed"),
		"no speed action exists — if one is added, retire speed_hint() for hint_for_action")

func test_the_speed_helper_covers_the_no_pad_case() -> void:
	## cowir-controller measured that with zero pads the bar returned a pad glyph — "Ⓨ Speed", a
	## button a keyboard player cannot press — because the glyph lookup falls back to the xbox
	## family rather than "?". The helper must branch on pad presence, not on the "?" sentinel.
	var w := _src(WIN98)
	var i: int = w.find("static func speed_hint()")
	assert_gt(i, -1, "the helper must exist")
	var j: int = w.find("\nstatic func ", i + 10)
	var body: String = w.substr(i, (j - i) if j > -1 else 600)
	assert_true(body.contains("get_connected_joypads().is_empty()"),
		"no pad means keyboard vocabulary, decided before any glyph lookup")
	assert_true(body.contains("` key"), "and the keyboard answer is the backtick, the real binding")

func test_the_bar_and_the_hint_agree_on_where_speed_lives() -> void:
	## Both read JOY_BUTTON_Y. If one moved, a player would see two different buttons for one
	## control on the same screen — the bar is on screen while the hint fires.
	## ⚠️ My first version counted JOY_BUTTON_Y across the whole file and expected 2. It is 5 — three
	## of them COMMENTS explaining the button. I spent the day telling other lanes to grep the
	## consumer rather than the comment and then wrote the comment-counting assertion myself.
	## Function-bounded, so only real uses count.
	var w := _src(WIN98)
	for fn in ["static func speed_hint()", "static func hint_text()"]:
		var i: int = w.find(fn)
		assert_gt(i, -1, "CONTROL: located %s" % fn)
		var j: int = w.find("\nstatic func ", i + 10)
		var body: String = w.substr(i, (j - i) if j > -1 else 800)
		assert_true(body.contains("face_glyph_for_index(JOY_BUTTON_Y)"),
			"%s must key on the same raw button as the other" % fn)
