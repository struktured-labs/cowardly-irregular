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
## cowir-controller 2026-09-11: my corpus named ONE file and the subject is TWO. The autogrind
## editor has caption statements with format slots and my derivation property never reached it —
## the narrowing was not in a comparison, it was in a const nobody re-reads (cowir-deploy's shape).
const AUTOGRIND_EDITOR := "res://src/ui/autogrind/AutogrindGridEditor.gd"
const WIN98 := "res://src/ui/Win98Menu.gd"

## ONE list. The premise arm and the scan filter each had their own copy — two literal lists for
## one corpus, free to drift, which is the defect I spent the morning routing out of the AP economy
## (billed_ap) and the afternoon out of the headless resolver. A premise that does not narrow the
## SAME set the scan narrows is not a premise about that scan.
## Both editors' spellings. autobattle: help_label1/2 + help. autogrind: help1/2. A selector that
## knows one file's naming is a second, quieter way to have the wrong corpus.
const CAPTION_LABELS: Array[String] = ["help_label1.text", "help_label2.text", "help.text", "help1.text", "help2.text"]

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
	## ⚠️ THE SINGLE ASSERT IS OUTSIDE THE LOOP, so draining `frozen` would pass with ZERO work —
	## and @cowir-overworld's free detector (a drained loop shows as a DROP in GUT's assert count)
	## cannot see it here, because the count would not move. Pin the corpus size, and assert once
	## PER LITERAL so the count does move if anyone trims the list.
	var total: int = 0
	for path in frozen:
		total += (frozen[path] as Array).size()
	assert_eq(total, 9, "CONTROL: the frozen-literal corpus is intact — 2 BattleScene + 7 grid editor")

	var found: Array = []
	for path in frozen:
		var s := _src(path)
		for lit in frozen[path]:
			assert_false(s.contains(lit),
				"%s still names a button by its Nintendo spelling: \"%s\"" % [path.get_file(), lit])
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
	var ge := _src(GRID_EDITOR) + "\n" + _src(AUTOGRIND_EDITOR)
	var derivations: int = ge.count("InputProfileManager.hint_for_action(") + ge.count("InputProfileManager.face_glyph_for_index(")
	assert_gt(derivations, 5, "CONTROL: the grid editor derives its pad captions at all (%d)" % derivations)
	## Per STATEMENT, not per line: help_label1 puts its format args on continuation lines, so a
	## line-by-line scan sees the string without its `% [...]` and reports a correct file as frozen.
	## My first version did exactly that and failed on the merged tree.
	## ⚠️ SUBJECT PREMISE (cowir-adhoc 2026-09-11): the exemption axis and the subject axis are
	## orthogonal, and I had only pinned the first. Renaming help_label1/2 makes this loop examine
	## ZERO statements and the whole file passes — measured, 7/7 green with the scan matching
	## nothing. A corpus-size control on the LITERAL list cannot see that; only counting what the
	## scan actually examined can.
	var lines: PackedStringArray = ge.split("\n")
	## ⚠️ NAMED MEMBERSHIP, NOT A COUNT. My first version pinned `captions_seen == 4` — an exact
	## count of SUBJECTS, written an hour after I retracted an exact count of HELPERS for going
	## stale on someone's correct change. Adding a fifth help line would have redded it the same way.
	## A floor (`> 0`) is the other trap: cowir-controller measured that it catches a TOTAL drain and
	## misses a PARTIAL one, and partial is likelier — a rename touches one label, not all of them.
	## Each label must contribute at least once; adding statements is free, losing one is not.
	for label in CAPTION_LABELS:
		var seen: int = 0
		for line in lines:
			if line.contains(label):
				seen += 1
		assert_gt(seen, 0,
			"CONTROL: `%s` contributed ZERO caption statements — it was renamed or removed, so every assertion below scanned less than it claims" % label)

	for i in lines.size():
		var line: String = lines[i]
		var is_caption: bool = false
		for label in CAPTION_LABELS:
			if line.contains(label):
				is_caption = true
				break
		if not is_caption:
			continue
		var slots: int = line.count("%s")
		if slots == 0:
			continue
		## Statement window: this line plus continuations, stopping at the first line that closes it.
		var stmt: String = line
		var closed: bool = line.strip_edges().ends_with("]") or line.strip_edges().ends_with(")")
		var k: int = i + 1
		while k < lines.size() and k <= i + 24 and not closed:
			stmt += lines[k]
			if lines[k].strip_edges().begins_with("]"):
				closed = true
				break
			k += 1
		## cowir-controller 2026-09-11: the window was i+8 and a longer continuation fell out the
		## BOTTOM — silently passing rather than failing, because an unterminated window still gets
		## scanned and `InputProfileManager.` happens to be in it. A bound that is reached is a
		## measurement that did not finish, so it must fail rather than answer.
		assert_true(closed,
			"could not find the end of this caption statement within 24 lines — widen the bound rather than trusting the result: %s" % line.strip_edges().substr(0, 70))
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
	## ⛔ THE CORPUS LIST IS ITSELF DRAINABLE, and this arm had that hole after two prior fixes.
	## @cowir-sfx 2026-09-11: `for x in LIST:` over `[]` runs no body and asserts nothing — and GUT
	## does not even flag Risky, because sibling asserts in the same function clear it. Measured:
	## emptying this list gave EC=0, Passing 8/8, Risky 0, SILENT.
	## A floor derived from the list it defends compares the list against itself. Pinned to a
	## LITERAL count and both members NAMED, so draining the corpus is itself the violation.
	var paths: Array[String] = [GRID_EDITOR, AUTOGRIND_EDITOR]
	## GTE, not EQ. @cowir-overworld 2026-09-11 ran the magnitude nobody was testing — PLUS-ONE —
	## and an `== 2` REDS ON A CORRECT ADDITION: a third caption-bearing file is work this guard
	## should welcome, not tax. Their two questions: may this set grow on correct work? YES.
	## Is growth itself the signal? NO. -> gte with a LITERAL floor (never `>= OTHER.size()`,
	## which is `0 >= 0` when both drain), and the named members below catch minus-one.
	assert_gte(paths.size(), 2,
		"PRECONDITION: the corpus lost an editor; a shortened list scans less and says nothing")
	assert_true(paths.has(GRID_EDITOR), "PRECONDITION: the autobattle editor must be in the corpus")
	assert_true(paths.has(AUTOGRIND_EDITOR), "PRECONDITION: the autogrind editor must be in the corpus")
	var per_file: Dictionary = {}
	var offenders: Array[String] = []
	for path in paths:
		per_file[path] = 0
		for raw in _src(path).split("\n"):
			var line: String = raw.strip_edges()
			if line.begins_with("#") or not line.contains(".text = "):
				continue
			per_file[path] += 1
			for n in banned:
				## TWO IDIOMS, because a bare word-match cannot work here: "Start", "Back", "Options"
				## and "Share" are ordinary English verbs ("Start a new grind", "Back to menu"), so
				## matching the word alone floods on correct prose.
				##   "Start:Save"        the terse caption form
				##   "Press Start to…"   the prose form — @cowir-music's shape, found by mutation:
				##                       my banned SET named Start while my PATTERN could not emit
				##                       it, so "Press Start to save" scored GREEN.
				## ⚠️ STILL A PATTERN, NOT A PROPERTY. A third idiom escapes. Recorded as the known
				## reach of this arm rather than claimed as coverage of the class.
				if line.contains("\"%s:" % n) or line.contains(" %s:" % n) \
						or line.contains("Press %s " % n) or line.contains("Press %s." % n):
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


## ── does the named input actually REACH the handler ───────────────────────────────────────────
## cowir-autogrind 2026-09-11, on their own console: "The Start token was wrong a SECOND way, and
## deriving it from the action would have kept it wrong." Deriving a caption from an InputMap action
## is only correct if that action's binding is what reaches the handler. It found the defect in MY
## shipped caption: Del/%s:Delete derived from `ui_menu`, whose pad half is Start/L3 (save-and-close)
## and whose keyboard half is Enter/Escape, both eaten earlier in the same elif chain. Three tokens
## in one legend were wrong this way. These two arms quantify over the chain, not over the answer.

const DELETER := "_delete_current_cell()"

func test_the_delete_caption_names_the_button_that_actually_deletes() -> void:
	## BOTH sides derived from source. A literal expectation here would have agreed with whatever I
	## happened to write in the caption, which is how the wrong one shipped green.
	var ge := _src(GRID_EDITOR)
	var arm_re := RegEx.new()
	arm_re.compile("event\\.button_index == (JOY_BUTTON_[A-Z_]+):\\n(?:.|\\n)*?" + DELETER.replace("(", "\\(").replace(")", "\\)"))
	var m := arm_re.search(ge)
	assert_not_null(m, "CONTROL: located the pad arm that reaches %s" % DELETER)
	if m == null:
		return
	var btn: String = m.get_string(1)
	assert_eq(btn, "JOY_BUTTON_Y", "CONTROL: the pad delete is the north face button")
	## ⚠️ SCOPED TO THE LABEL, not to the file. My first version asserted `ge.contains(...)` — and the
	## CycleOp token six lines below satisfies that string, so restoring the exact shipped defect left
	## this arm GREEN (measured: Failing 1, and it was the other arm). A file-wide containment check
	## for a value the file uses twice cannot speak about either use.
	var a: int = ge.find("var help_label1 = Label.new()")
	var b: int = ge.find("add_child(help_label1)")
	assert_gt(a, -1, "CONTROL: located the delete legend")
	assert_gt(b, a, "CONTROL: the window closes after it opens")
	var label: String = ge.substr(a, b - a)
	assert_true(label.contains(":Delete"), "CONTROL: this window really is the one carrying the token")
	## ⚠️ FOLLOW ONE HELPER LEVEL. My first version searched the window alone, and cowir-controller's
	## fix — which builds the whole token in `_delete_token()` so "Del/" cannot dangle with no pad —
	## is BETTER than mine and this arm RED IT. A guard that fails the superior implementation of the
	## thing it defends is taxing correct work; measured on their tree before it was widened.
	var derivation: String = label
	var call_re := RegEx.new()
	call_re.compile("\\b(_[a-z_]+)\\(\\)")
	for c in call_re.search_all(label):
		var fn: String = "func %s(" % c.get_string(1)
		var fi: int = ge.find(fn)
		if fi > -1:
			var fj: int = ge.find("\nfunc ", fi + 10)
			derivation += ge.substr(fi, (fj - fi) if fj > -1 else 400)
	## Either family renderer is fine — what must not vary is WHICH raw index it renders.
	assert_true(derivation.contains("_for_index(%s)" % btn),
		"the delete caption must render the button the delete handler tests (%s)" % btn)
	assert_false(label.contains("hint_for_action(\"ui_menu\")"),
		"ui_menu is save-and-close — a delete caption deriving from it names the button that EXITS")

func test_no_caption_derives_from_an_action_its_own_chain_eats_first() -> void:
	## The CLASS. For every action a caption in this file names: if every one of its keyboard bindings
	## is claimed by an EARLIER arm of the same _input chain, its keyboard render is a key that does
	## something else — so that token must be pad-gated or it is a false caption. Pre-fix this reds
	## twice: `ui_menu` (Enter eaten by ui_accept, Escape by ui_cancel) and `battle_toggle_auto`
	## (Tab eaten by the row-toggle arm). Neither was reachable by a bracketed-token scan.
	var ge := _src(GRID_EDITOR)
	var i: int = ge.find("func _input(event: InputEvent)")
	assert_gt(i, -1, "CONTROL: located the input chain")
	var j: int = ge.find("\nfunc ", i + 10)
	var chain: String = ge.substr(i, (j - i) if j > -1 else ge.length() - i)
	assert_true(chain.contains(DELETER), "CONTROL: the sliced chain is the real one")

	var named_re := RegEx.new()
	named_re.compile("hint_for_action\\(\"([a-z_]+)\"\\)")
	var actions: Dictionary = {}
	for m in named_re.search_all(ge):
		actions[m.get_string(1)] = true
	assert_gt(actions.size(), 2, "CONTROL: captions name actions at all (%d)" % actions.size())

	var ungated: Array = []
	for act in actions:
		var own: int = chain.find("is_action_pressed(\"%s\")" % act)
		if own < 0:
			continue  # handled elsewhere; this arm only speaks about this chain
		var keys: Array = []
		for ev in InputMap.action_get_events(act):
			if ev is InputEventKey:
				keys.append(OS.get_keycode_string((ev as InputEventKey).keycode).to_upper())
		if keys.is_empty():
			continue  # pad-only binding: nothing to shadow
		var shadowed: int = 0
		for k in keys:
			var kre := RegEx.new()
			kre.compile("KEY_%s\\b" % k)
			var first: int = -1
			var km := kre.search(chain)
			if km != null:
				first = km.get_start()
			for other in actions:
				if other == act:
					continue
				var o: int = chain.find("is_action_pressed(\"%s\")" % other)
				if o > -1 and o < own and _binds_key(other, k):
					first = o if first < 0 else mini(first, o)
			if first > -1 and first < own:
				shadowed += 1
		if shadowed == keys.size():
			## Every keyboard route to this action is consumed before its own arm. Legal ONLY if the
			## caption never renders that keyboard half — i.e. the token is behind a pad check.
			for line in ge.split("\n"):
				if line.contains("hint_for_action(\"%s\")" % act) and not line.contains("_has_pad()"):
					ungated.append("%s (keys %s all eaten earlier)" % [act, str(keys)])
					break
	assert_eq(ungated.size(), 0,
		"a caption renders a keyboard key the chain hands to something else: " + str(ungated))

func _binds_key(action: String, key_upper: String) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and OS.get_keycode_string((ev as InputEventKey).keycode).to_upper() == key_upper:
			return true
	return false
