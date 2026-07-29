extends GutTest

## The battle hint bar is the most-read input string in the game — it is permanently on screen in
## every fight. It advertised "[+/-] Speed" and NOTHING in src/ bound +/- to battle speed: the only
## +/- handler anywhere is in AutogrindUI. A player following the on-screen instruction pressed a key
## that did nothing, in the one place the game explicitly tells you what the controls are.
##
## Real controls, measured 2026-07-28: JOY_BUTTON_Y (north/top face — physically X on the
## Nintendo-layout pads this game targets) and the ` key. Tab is battle_toggle_auto, despite a source
## comment that claimed Tab toggled speed.
##
## This is the "lie-in-the-label" class aimed at input: a hint that names a control the code does not
## implement is worse than no hint, because it sends the player to a dead key and they conclude the
## FEATURE is broken rather than the label.

const WIN98_PATH := "res://src/ui/Win98Menu.gd"
const BATTLE_PATH := "res://src/battle/BattleScene.gd"


func _read(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	assert_ne(text, "", "must be able to read %s" % path)
	return text


## The exact regression. Pinned by the literal token so a well-meaning "restore the +/- hint" edit
## has to also add the binding.
##
## Comment lines are skipped deliberately: the fix documents the old bad string in a comment at each
## site, and a naive whole-file scan flags its own explanation. Guarding CODE, not prose.
## WIDENED 2026-07-29. The original scanned only the two hint-bar files, because those were where
## the bug was. But player-facing control references also appear UNBRACKETED — "Press L to Defer",
## "Use R to queue actions" — a form my sweep pattern could not see at all, and there are ~19 of them
## across src/. A guard whose corpus is "the file the bug was in" cannot catch the same claim
## reappearing anywhere else, which is the whole reason a class-level ratchet exists.
func test_hint_bar_does_not_advertise_the_unbound_plus_minus_speed_control() -> void:
	for path in _all_gd_files():
		var offenders: Array[String] = []
		for line in _read(path).split("\n"):
			var stripped := line.strip_edges()
			if stripped.begins_with("#"):
				continue
			if _advertises_plus_minus_speed(stripped):
				offenders.append(stripped)
		if offenders.is_empty():
			continue
		# CONDITIONAL, not a ban. The offence is advertising +/- while nothing binds it — not the
		# token itself. Banning the string outright would go RED on a correct change: someone who
		# actually wires +/- to speed SHOULD be able to print the hint. Assert the relationship.
		assert_true(_plus_minus_toggles_speed(),
			"%s advertises +/- for battle speed. That is only honest if something binds it — and nothing does, so a player pressing +/- gets nothing. Either wire +/- to _toggle_battle_speed, or do not print it:\n%s" % [path, "\n".join(offenders)])


## Both files print the same bar. They drifted apart silently once already (the duplicated literal),
## so pin that a fix to one reaches the other.
func test_both_hint_bar_sites_agree() -> void:
	var win98 := _read(WIN98_PATH)
	var battle := _read(BATTLE_PATH)
	var expected := "[L] Defer  ·  [R] Advance  ·  [X] Speed  ·  [Select] Auto"
	assert_true(win98.contains(expected), "Win98Menu must print the corrected bar")
	assert_true(battle.contains(expected), "BattleScene must print the SAME bar — two copies of one string drift")


## [L], [R] and [Select] are InputMap actions and must actually carry a joypad binding, or the hint
## names a button that does nothing on a controller.
func test_hint_bar_actions_have_real_joypad_bindings() -> void:
	var named := {"[L] Defer": "battle_defer", "[R] Advance": "battle_advance", "[Select] Auto": "battle_toggle_auto"}
	for label in named:
		var action: String = named[label]
		assert_true(InputMap.has_action(action), "%s names action '%s' which must exist" % [label, action])
		var has_button := false
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton:
				has_button = true
		assert_true(has_button, "%s must map to a real joypad button, not keyboard only" % label)


## [X] is NOT an InputMap action — it is a raw button check in BattleScene. Assert the handler is
## really there, because a hint pointing at a raw check has nothing else guarding it.
## Pins the RELATIONSHIP, not the presence of three strings.
##
## The first version asserted `contains("JOY_BUTTON_Y")`, `contains("_toggle_battle_speed")` and
## `contains("KEY_QUOTELEFT")` separately. Mutation-tested 2026-07-29 and it is BLIND to the exact
## regression it exists for: repoint the JOY_BUTTON_Y arm at `_repeat_previous_actions()` and all
## three strings survive, the guard stays green, and the advertised [X] button no longer changes
## speed. A source-text pin is a claim about the code's SPELLING; the word doing the work in the old
## assertion was "handled", and nothing exercised it. (cowir-ai's class, cowir-music's Mordaine guard,
## same shape.)
func test_speed_toggle_is_actually_wired_to_the_advertised_button() -> void:
	var lines := _read(BATTLE_PATH).split("\n")
	var wired := false
	for i in lines.size():
		if lines[i].contains("JOY_BUTTON_Y") and _calls_within_block(lines, i, "_toggle_battle_speed("):
			wired = true
	assert_true(wired,
		"the [X] hint promises the north/top face toggles speed — JOY_BUTTON_Y must actually CALL _toggle_battle_speed, not merely appear in the same 390KB file")

	var kb_wired := false
	for i in lines.size():
		if lines[i].contains("KEY_QUOTELEFT") and _calls_within_block(lines, i, "_toggle_battle_speed("):
			kb_wired = true
	assert_true(kb_wired,
		"the keyboard half (` key) must call _toggle_battle_speed, same reasoning")


## The source comment claimed "Tab or ` key" for speed. Tab is battle_toggle_auto, so that comment
## sent any reader to the wrong control — the same lie one layer down from the player-facing string.
func test_tab_is_not_claimed_as_the_speed_key() -> void:
	assert_false(_read(BATTLE_PATH).contains("Battle speed toggle (Tab or"),
		"Tab is battle_toggle_auto; a comment claiming it toggles speed misroutes the next reader")
	var tab_action := ""
	for action in InputMap.get_actions():
		for event in InputMap.action_get_events(action):
			if event is InputEventKey and (event as InputEventKey).keycode == KEY_TAB:
				tab_action = action
	assert_eq(tab_action, "battle_toggle_auto", "Tab is expected to remain the autobattle toggle")

## Every .gd under src/ — the corpus is "anywhere a player-facing string can live", not "the file
## the bug happened to be in".
func _all_gd_files() -> Array[String]:
	var found: Array[String] = []
	var dirs: Array[String] = ["res://src"]
	while not dirs.is_empty():
		var current: String = dirs.pop_back()
		var dir := DirAccess.open(current)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			var full := "%s/%s" % [current, entry]
			if dir.current_is_dir():
				dirs.append(full)
			elif entry.ends_with(".gd"):
				found.append(full)
			entry = dir.get_next()
		dir.list_dir_end()
	# Positive control: an empty or tiny corpus makes the scan vacuously green.
	assert(found.size() > 50)
	return found

## True when some key in the +/- family actually reaches the speed toggle. Adjacency, same technique
## as the JOY_BUTTON_Y check: presence of both tokens somewhere in a 390KB file proves nothing.
func _plus_minus_toggles_speed() -> bool:
	for path in _all_gd_files():
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var line: String = lines[i]
			if not (line.contains("KEY_PLUS") or line.contains("KEY_MINUS") \
					or line.contains("KEY_EQUAL") or line.contains("KEY_KP_ADD")):
				continue
			if _calls_within_block(lines, i, "_toggle_battle_speed("):
				return true
	return false

## Does the dispatch arm opening at `start` CALL `needle` before its block ends?
##
## Scope, not a line count. The previous form scanned a fixed 4-line window, which is a
## COORDINATE: inserting four comment lines between the check and its call — behaviour entirely
## unchanged — made this guard go RED on correct code. Measured 2026-07-29. That is the standing
## pitfall about ratchets pinned to coincidental values, shipped in the same file where I had just
## fixed the other instance of it.
##
## A block ends at the first non-blank, non-comment line indented at or below the arm itself.
func _calls_within_block(lines: PackedStringArray, start: int, needle: String) -> bool:
	var base := lines[start].length() - lines[start].strip_edges(true, false).length()
	for j in range(start + 1, lines.size()):
		var line: String = lines[j]
		var bare := line.strip_edges()
		if bare.is_empty() or bare.begins_with("#"):
			continue
		var indent := line.length() - line.strip_edges(true, false).length()
		if indent <= base:
			return false
		if line.contains(needle):
			return true
	return false

## Does this line advertise +/- as a SPEED control, in any wording?
##
## The first version matched the literal "[+/-] Speed" — the exact phrasing that existed the day I
## found the bug. That is the INCIDENT vocabulary, not the property (cowir-story's framing, and
## cowir-sfx's: the bug report is a sample; the guard should assert the invariant the bug violated).
## Measured 2026-07-29: "Press +/- to change battle speed" with nothing bound sailed straight past
## it — the same defect, different words, guard green.
##
## The property is "a player-facing string offers +/- for speed". Both tokens on one line, so an
## unrelated +/- elsewhere in a file cannot trip it. Covers the Unicode minus too, because a
## designer writing UI text is more likely to type it than a programmer is.
func _advertises_plus_minus_speed(line: String) -> bool:
	if not line.to_lower().contains("speed"):
		return false
	return line.contains("+/-") or line.contains("+/\u2212") or line.contains("+ / -")
