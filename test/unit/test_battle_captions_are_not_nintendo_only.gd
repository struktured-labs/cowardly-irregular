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
	## ⚠️ WAS `count(hint_for_action) == 9` AND IT WENT STALE ON A CORRECT MERGE. cowir-autogrind
	## landed `face_glyph_for_index(JOY_BUTTON_Y)` for the Y token in the same file — the RIGHT helper,
	## since Y has no InputMap action — and my count dropped to 7 while the file got better. I pinned
	## the NAME of one helper, which is the exact class cowir-main called out at the fold: a lane's
	## ratchet pinning a helper name goes stale on another lane's better helper. Now: every format
	## slot in a help line must be fed by SOME derivation, and which one is the author's business.
	var ge := _src(GRID_EDITOR)
	var derivations: int = ge.count("InputProfileManager.hint_for_action(") + ge.count("InputProfileManager.face_glyph_for_index(")
	assert_gt(derivations, 5, "CONTROL: the grid editor derives its pad captions at all (%d)" % derivations)
	## Per STATEMENT, not per line: help_label1 puts its format args on continuation lines, so a
	## line-by-line scan sees the string without its `% [...]` and reports a correct file as frozen.
	## My first version did exactly that and failed on the merged tree.
	var lines: PackedStringArray = ge.split("\n")
	for i in lines.size():
		var line: String = lines[i]
		if not (line.contains("help_label1.text") or line.contains("help_label2.text") or line.contains("help.text")):
			continue
		var slots: int = line.count("%s")
		if slots == 0:
			continue
		## Statement window: this line plus continuations, stopping at the first line that closes it.
		var stmt: String = line
		var k: int = i + 1
		while k < lines.size() and k <= i + 8 and not line.strip_edges().ends_with("]"):
			stmt += lines[k]
			if lines[k].strip_edges().begins_with("]"):
				break
			k += 1
		assert_true(stmt.contains("InputProfileManager."),
			"a help caption with %d format slots must feed them from InputProfileManager: %s" % [slots, line.strip_edges().substr(0, 80)])

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

## ── the stripper itself ───────────────────────────────────────────────────────────────────────
## cowir-sfx 2026-09-11: pin the HELPER, not the corpus. Six costumes of this bug were found across
## four lanes in one afternoon, every one by mutating a source file and watching a guard, and every
## fix blind to the next. A case table on the helper reds on the SEVENTH instead of waiting for a
## corpus that happens to expose it.
##
## ⚠️ DUPLICATION, stated rather than hidden: an identical _strip_comments lives in
## test_full_banks_are_recorded on another branch. Two copies of one rule is the defect I spent the
## morning routing out of the AP economy. They cannot share a helper without coupling two branches
## into a fold-order dependency, so this pins one copy and the duplication is a follow-up once both
## land — NOT a thing I am claiming is fine.

func test_the_stripper_cuts_comments_and_keeps_strings() -> void:
	var cases := [
		["var x := 1  # gone", "var x := 1  ", "a trailing comment is cut"],
		["# whole line", "", "a full-line comment is blanked"],
		["var c := \"#ff0000\"", "var c := \"#ff0000\"", "a hash INSIDE a string survives — my absence asserts live there"],
		["var c := '#ff0000'", "var c := '#ff0000'", "single quotes too"],
		["var c := \"#ff0000\"  # gone", "var c := \"#ff0000\"  ", "a string hash then a real comment: cut at the comment only"],
		## ⚠️ THE ROW THAT DISCRIMINATES IS AN ESCAPED QUOTE, NOT AN ESCAPED BACKSLASH. My first table
		## used `"a\\\\"` — cowir-overworld's example, which illustrates the LOOKBEHIND bug — and it passes
		## identically with escape handling REMOVED ENTIRELY, because two backslashes toggle nothing.
		## An escaped quote is what a missing skip gets wrong: the string closes early, the # lands
		## inside the next one, and the comment survives into the scan.
		["var q := \"a\\\"b\"  # gone", "var q := \"a\\\"b\"  ", "an escaped QUOTE must not close the string"],
		["var q := \"a\\\\\"  # gone", "var q := \"a\\\\\"  ", "an escaped backslash DOES close it — the lookbehind costume"],
		["var s := \"it's fine\"  # gone", "var s := \"it's fine\"  ", "an apostrophe inside a double-quoted string is not a quote"],
		["plain code", "plain code", "no hash, untouched"],
	]
	for c in cases:
		assert_eq(_strip_comments(c[0]), c[1], "%s — input: %s" % [c[2], c[0]])

func test_the_stripper_preserves_line_count() -> void:
	## substr windows in this file and the next are computed against the STRIPPED text, so a
	## stripper that dropped blanked lines would silently shift every offset.
	var raw := "a\n# b\nc  # d\n"
	assert_eq(_strip_comments(raw).split("\n").size(), raw.split("\n").size(),
		"blanking must not remove lines")


## ⛔ THE GAP THIS FILE HAD: "Start:Save" re-froze and BOTH guards stayed green (measured
## 2026-09-11 by mutation). The frozen list above holds FACE letters, and cowir-autogrind's scan
## looks for face-button letters — "Start" is neither. So the non-face names were unguarded on
## every side, which is how "Start" survived the batch that derived "Select" beside it.
##
## Banned set DERIVED from BUTTON_NAMES, not listed: every family's spelling of a non-face button
## (Start/Plus/Options, Select/Back/Share, L/LB/L1, R/RB/R1, L3/L-Stick). A new family or a
## renamed button cannot open a hole here.
##
## Scans LABEL ASSIGNMENTS only. `print("[AUTOBATTLE] Start pressed via ui_menu")` at :1885 is a
## debug line, not player-facing, and a whole-file scan would report it as a defect.
func test_no_help_label_spells_a_non_face_button() -> void:
	var banned: Array[String] = []
	for family in InputProfileManager.BUTTON_NAMES:
		for idx in InputProfileManager.BUTTON_NAMES[family]:
			var n: String = InputProfileManager.BUTTON_NAMES[family][idx]
			if not banned.has(n):
				banned.append(n)
	assert_gt(banned.size(), 8, "PRECONDITION: the banned set must come from BUTTON_NAMES, got %s" % [banned])

	## EMIT THE CORPUS, ASSERT ITS SIZE. @cowir-sprites 2026-09-11: a guard whose SUBJECT drains
	## scores a clean green over zero work — a loop over nothing asserts nothing, and GUT cannot
	## flag it because one assert anywhere in the call graph clears [Risky]. If the label-assignment
	## shape ever changes, this arm must FAIL rather than quietly scan an empty set.
	var per_file: Dictionary = {}
	var offenders: Array[String] = []
	for path in [GRID_EDITOR, "res://src/ui/autogrind/AutogrindGridEditor.gd"]:
		per_file[path] = 0
		for raw in _src(path).split("\n"):
			var line: String = raw.strip_edges()
			if line.begins_with("#") or not line.contains(".text = "):
				continue
			per_file[path] += 1
			for n in banned:
				# "Start:Save" / "Start Save" — a caption naming the button, not a word inside prose
				if line.contains("\"%s:" % n) or line.contains(" %s:" % n):
					offenders.append("%s :: %s" % [path.get_file(), n])
	## ⛔ WAS A FLOOR (`examined > 4` across both files). @cowir-adhoc 2026-09-11: a floor is armed
	## against TOTAL vacuity and BLIND TO PARTIAL LOSS. Measured — breaking `.text = ` in ONE editor
	## left the other above the floor and the file scored EC=0, Asserts 39, unchanged. The free
	## assert-count detector missed it too, because these asserts are not per-row.
	## Named membership instead: EVERY file in the corpus must contribute, so losing half is a red.
	for path in per_file:
		assert_gt(int(per_file[path]), 0,
			"PRECONDITION: %s contributed ZERO label assignments — the scan silently covered only " % path.get_file() +
			"the other editor, and a green below would be half a result reported as a whole one")
	assert_eq(offenders, [] as Array[String],
		"a help label spells a NON-FACE button by one family's name — derive it through " +
		"hint_for_action so Nintendo reads Plus and PlayStation reads Options: %s" % [", ".join(offenders)])
