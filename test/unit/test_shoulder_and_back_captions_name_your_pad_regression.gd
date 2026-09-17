extends GutTest

## ⛔ HERMETIC ABOUT THE PROFILE, for the same reason as its sibling legend file. These arms derive
## per-family BUTTON NAMES from the live InputMap, so they inherit whatever `user://input/
## controls.json` holds. A remap test writes a "Custom" profile there and an interrupted run skips
## its cleanup, after which every later run in that sandbox reads it.
##
## Measured on a five-day sandbox carrying that file: Failing 1 here, Passing 11 in a fresh one.
## The shoulders resolve to FACE GLYPHS (Ⓐ / ○ / Ⓑ) instead of L / L1 / LB, because the stale
## profile binds them to face buttons and BUTTON_NAMES returns a glyph for those.
##
## ⚠️ I fixed the sibling file an hour before this one and did not check for others. One pin
## repaired one file; the contamination reaches every arm that derives a name from the InputMap.
var _saved_profile: String = ""


func before_all() -> void:
	_saved_profile = InputProfileManager.active_profile
	InputProfileManager.apply_profile("Standard")


func after_all() -> void:
	if _saved_profile != "":
		InputProfileManager.apply_profile(_saved_profile)


## CONTROL: the pinned profile must actually put the shoulders on shoulder buttons, or every
## per-family assertion below is asking about a binding the profile never made.
func test_control_the_pinned_profile_binds_the_shoulders() -> void:
	assert_eq(InputProfileManager.active_profile, "Standard",
		"before_all must leave Standard active, or these arms inherit the sandbox again")
	var xb := InputProfileManager.button_name_for_action("battle_defer", "Xbox Wireless Controller")
	assert_eq(xb, "LB",
		"Standard must bind battle_defer to a shoulder; got %s — a face button returns a GLYPH here, "
		% ("empty" if xb == "" else xb) + "which is exactly how a stale Custom profile shows up")


## Three footers named a button off ONE pad family's plastic and froze it for everyone.
## Handed over by @cowir-autogrind, who ran this lane's BUTTON_NAMES matcher wider than the lane's
## own corpus: 12 files hit, 11 were the WORD "Back" used as an action label beside an already
## correct %s, and the noise was hiding these.
##
## MEASURED per family before the fix (hint_for_action, headless, no pad vs three device names):
##   ui_cancel       keyboard X   xbox Ⓐ    nintendo Ⓑ   playstation ✕
##   battle_defer    keyboard L   xbox LB   nintendo L   playstation L1
##   battle_advance  keyboard R   xbox RB   nintendo R   playstation R1
##
##   PartyStatusScreen  "B/Esc: Back"  — correct on Nintendo ONLY. ⛔ THE WORST OF THE THREE, and
##     not merely unhelpful: Confirm sits on the EAST face, so on an Xbox pad ui_cancel IS Ⓐ and
##     "B" names Ⓑ, which is ui_ACCEPT. The caption told an Xbox player to press CONFIRM to go
##     back. On a PlayStation pad there is no "B" on the plastic at all.
##   OverworldMenu     "L/R: Leader"   — correct on Nintendo (and, by coincidence, on keyboard,
##     where battle_defer/battle_advance bind the L and R keys). Wrong on Xbox and PlayStation.
##   BossSelectorMenu  "L1/R1 page"    — correct on PlayStation only.
##
## WHY THIS LANE'S OWN FOOTER CLASSIFIER MISSED ALL THREE: it asked "is a keyboard key named?" and
## never "is the pad name right for this family?". "B/Esc: Back" names Esc, so it was filed KB+ok
## and never looked at again. The question a caption audit must ask is about the PAD half.

const PARTY_STATUS_PATH := "res://src/ui/PartyStatusScreen.gd"
const BOSS_SELECTOR_PATH := "res://src/ui/BossSelectorMenu.gd"
const OVERWORLD_MENU_PATH := "res://src/ui/OverworldMenu.gd"
const ABILITIES_MENU_PATH := "res://src/ui/AbilitiesMenu.gd"
const RADIAL_PICKER_PATH := "res://src/ui/RadialPicker.gd"

## Device names measured to resolve to the three families (face_family_for_device).
const XBOX := "Xbox 360 Controller"
const NINTENDO := "Nintendo Switch Pro Controller"
const PLAYSTATION := "PS5 Controller"


func _ipm():
	return InputProfileManager


## Depth-first by rendered TEXT, never by node path — the artifact is what the player reads, and a
## path assertion survives the caption being rewritten into a different node.
func _label_containing(root: Node, needle: String) -> Label:
	if root is Label and (root as Label).text.find(needle) > -1:
		return root as Label
	for child in root.get_children():
		var found := _label_containing(child, needle)
		if found:
			return found
	return null


func _stand_up_party_status() -> Node:
	var s = load(PARTY_STATUS_PATH).new()
	add_child_autofree(s)
	s.party = []
	s.focused_index = 0
	s._build_ui()
	return s


func _stand_up_boss_selector() -> Node:
	var s = load(BOSS_SELECTOR_PATH).new()
	add_child_autofree(s)
	return s


## ⛔ THE BEHAVIOURAL ARM, and the reason it is worth standing a whole screen up: with no pad
## connected hint_for_action("ui_cancel") returns "X" while the frozen caption said "B", so the
## RENDERED string discriminates. A source assert here would only prove the file mentions the
## helper; this presses nothing but it does read what the player reads.
func test_party_status_back_names_the_button_that_actually_cancels() -> void:
	var screen := _stand_up_party_status()
	var footer := _label_containing(screen, ": Back")
	assert_not_null(footer, "PartyStatusScreen must render a footer naming Back")
	if footer == null:
		return
	var derived: String = _ipm().hint_for_action("ui_cancel")
	assert_ne(derived, "", "precondition: ui_cancel must resolve to something nameable")
	assert_true(footer.text.find(derived) > -1,
		"footer must name the CURRENT device's cancel button (%s), got: %s" % [derived, footer.text])
	assert_eq(footer.text.find("B/Esc"), -1,
		"the frozen Nintendo token must be gone — on Xbox 'B' is ui_accept, i.e. Confirm")


func test_boss_selector_paging_names_the_shoulders_you_have() -> void:
	var screen := _stand_up_boss_selector()
	var subtitle := _label_containing(screen, "Select a boss")
	assert_not_null(subtitle, "BossSelectorMenu must render its DEBUG subtitle")
	if subtitle == null:
		return
	var defer_hint: String = _ipm().hint_for_action("battle_defer")
	var advance_hint: String = _ipm().hint_for_action("battle_advance")
	assert_true(subtitle.text.find(defer_hint) > -1 and subtitle.text.find(advance_hint) > -1,
		"subtitle must name the current device's page buttons (%s/%s), got: %s"
			% [defer_hint, advance_hint, subtitle.text])
	assert_eq(subtitle.text.find("L1/R1"), -1,
		"the frozen PlayStation token must be gone — those are LB/RB on Xbox, L/R on Nintendo")


## OverworldMenu gets a SOURCE arm and the reason is worth stating rather than hiding: its frozen
## token was "L/R", and battle_defer/battle_advance bind the L and R KEYS, so with no pad connected
## the derived string is byte-identical to the frozen one. Rendering cannot discriminate here at
## all — no pad can be faked headless — so the only falsifiable claim left is that the footer
## STATEMENT feeds those two actions through the helper.
func test_overworld_leader_row_derives_its_shoulder_tokens() -> void:
	var src := FileAccess.get_file_as_string(OVERWORLD_MENU_PATH)
	var at := src.find("footer.text = \"↑↓: Select")
	assert_gt(at, -1, "the overworld footer statement must still exist")
	if at < 0:
		return
	# Bounded at the statement's own end, never a fixed character window — the fix spans lines.
	var stop := src.find("footer.position", at)
	assert_gt(stop, at, "footer.position must follow the text assignment — that is the bound")
	var stmt := src.substr(at, stop - at)
	assert_true(stmt.find("hint_for_action(\"battle_defer\")") > -1,
		"Leader-back binds battle_defer (OverworldMenu:~703) and must be derived, not written out")
	assert_true(stmt.find("hint_for_action(\"battle_advance\")") > -1,
		"Leader-forward binds battle_advance (OverworldMenu:~712) and must be derived")
	assert_eq(stmt.find("L/R: Leader"), -1, "the frozen Nintendo pair must be gone")


## ⛔ THE SAME DEFECT, TWICE MORE, found by asking the CORRECTED question across src/ — "is the pad
## half right for this family?" rather than "is a keyboard key named?". The first question returns
## 70 candidate lines, almost all noise (docstrings saying "Start the battle", the BUTTON_NAMES
## table itself, "Back Row", "Share code"); these two survive it.
##   AbilitiesMenu   "A/Click: Equip  B/RClick: Back"  — the INVERTED pair, and worse than
##     PartyStatusScreen's single token: on an Xbox pad A is ui_cancel and B is ui_accept, so BOTH
##     halves pointed at the other one's action. Equip said Cancel; Back said Confirm.
##   RadialPicker    "[L1/R1]"  — frozen PlayStation paging, three lines ABOVE a hint that already
##     derives correctly. Same shape as OverworldMenu: a derived line and a frozen one side by side.
func test_abilities_menu_footer_names_the_buttons_that_equip_and_back_out() -> void:
	var src := FileAccess.get_file_as_string(ABILITIES_MENU_PATH)
	var at := src.find("var footer_text = ")
	assert_gt(at, -1, "the abilities footer statement must still exist")
	if at < 0:
		return
	var stop := src.find("var footer = Label.new()", at)
	assert_gt(stop, at, "the Label construction must follow — that is the statement block's end")
	var stmt := src.substr(at, stop - at)
	assert_true(stmt.find("cancel_hint") > -1 and stmt.find("accept_hint") > -1,
		"both footer variants must derive through hint_for_action, not name A and B")
	assert_eq(stmt.find("B/RClick"), -1,
		"on Xbox 'B' is ui_accept — this caption sent a player to Confirm when they wanted Back")
	assert_eq(stmt.find("A/Click"), -1,
		"…and 'A' is ui_cancel there, so Equip pointed at the cancel button")


## RadialPicker gets a SOURCE arm for a reason worth stating: it paints with draw_string() inside
## _draw(), so there is no Label in the tree to read. The rendered artifact is a canvas texture; a
## node-walk finds nothing, and pretending otherwise would give a green test reading an empty scene.
func test_radial_picker_page_indicator_names_your_shoulders() -> void:
	var src := FileAccess.get_file_as_string(RADIAL_PICKER_PATH)
	var at := src.find("var pg := ")
	assert_gt(at, -1, "the page indicator must still exist")
	if at < 0:
		return
	var stop := src.find("var pw :=", at)
	assert_gt(stop, at, "the width measurement must follow — that is the statement's end")
	var stmt := src.substr(at, stop - at)
	assert_true(stmt.find("hint_for_action(\"battle_defer\")") > -1
			and stmt.find("hint_for_action(\"battle_advance\")") > -1,
		"the shoulders that page (RadialPicker:~114/~118) must be derived, not written as L1/R1")
	assert_eq(stmt.find("L1/R1"), -1, "the frozen PlayStation pair must be gone")


## WHY the three literals were defects, pinned per family so this cannot decay into "someone
## preferred a different string". Each frozen token is right on exactly ONE family.
func test_each_frozen_token_was_correct_on_exactly_one_family() -> void:
	var cancel := {
		XBOX: _ipm().hint_for_action("ui_cancel", XBOX),
		NINTENDO: _ipm().hint_for_action("ui_cancel", NINTENDO),
		PLAYSTATION: _ipm().hint_for_action("ui_cancel", PLAYSTATION),
	}
	assert_eq(cancel[NINTENDO], "Ⓑ", "the old 'B' was a Nintendo name")
	assert_ne(cancel[XBOX], "Ⓑ", "…and on Xbox cancel is NOT Ⓑ")
	assert_ne(cancel[PLAYSTATION], "Ⓑ", "…nor on PlayStation")

	var defer := {
		XBOX: _ipm().hint_for_action("battle_defer", XBOX),
		NINTENDO: _ipm().hint_for_action("battle_defer", NINTENDO),
		PLAYSTATION: _ipm().hint_for_action("battle_defer", PLAYSTATION),
	}
	assert_eq(defer[NINTENDO], "L", "the overworld footer's old 'L' was a Nintendo name")
	assert_eq(defer[PLAYSTATION], "L1", "the boss selector's old 'L1' was a PlayStation name")
	assert_eq(defer[XBOX], "LB", "and neither family's token is what an Xbox player sees")


## ⛔ THE FINDING THAT MAKES "B/Esc: Back" A BUG AND NOT A TYPO. Confirm is the EAST face, so the
## letter B does not merely fail to help an Xbox player — it names the button that CONFIRMS.
func test_on_xbox_the_old_back_caption_named_the_confirm_button() -> void:
	assert_eq(_ipm().hint_for_action("ui_accept", XBOX), "Ⓑ",
		"on an Xbox pad Confirm is Ⓑ — this is what the frozen 'B' pointed at")
	assert_eq(_ipm().hint_for_action("ui_cancel", XBOX), "Ⓐ",
		"…while Back is Ⓐ, so the caption sent an Xbox player to the opposite action")


## THE CONTROL. Without it, "the footer contains the derived token" is unfalsifiable: a reader that
## returned the whole scene's text, or a hint that returned "", would satisfy every assert above.
## Both directions — the finder must FIND a planted caption and must MISS an absent one, and the
## three families' cancel tokens must be mutually distinct or the table arm proves nothing.
func test_the_probe_can_tell_a_frozen_caption_from_a_derived_one() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var planted := Label.new()
	planted.text = "←→: Switch member  B/Esc: Back"
	host.add_child(planted)
	var found := _label_containing(host, "B/Esc")
	assert_not_null(found, "the reader must FIND a frozen caption when one is present")
	assert_null(_label_containing(host, "L1/R1"),
		"…and must NOT report one that is absent, or every assert above is vacuous")

	var seen := {}
	for dev in [XBOX, NINTENDO, PLAYSTATION]:
		seen[_ipm().hint_for_action("ui_cancel", dev)] = true
	assert_eq(seen.size(), 3,
		"the three families must give three DIFFERENT cancel glyphs — if they collapsed to one, " +
		"a frozen caption would be indistinguishable from a derived one and this file is moot")


## ─────────────────────────────────────────────────────────────────────────────────────────────
## DERIVED CORPUS (2026-09-16). Everything above this line pins FIVE files named by hand, and that
## is how TutorialHints carried this exact defect through two sweeps and a lane declaring it clean:
## the class was guarded, the file was simply not in the list. A sixth surface reds nothing.
##
## So the corpus is now the tree. The rule is narrow on purpose — a family pad token in BUTTON
## POSITION inside a string the player reads — because the loose version returns ~70 lines of
## prose ("Back Row", "Share the code", "Select an ability") and a guard that cries wolf is one
## somebody silences.

## Each names a button exactly one family prints on the plastic. "Select" is on none of the three
## (Xbox Back · PlayStation Share · Switch Minus); "Start" is on none of the current three either
## (Xbox Menu · PlayStation Options). L/R is the Nintendo shoulder pair — LB/RB, L1/R1 elsewhere.
const FAMILY_PAD_TOKENS := ["L1", "R1", "L2", "R2", "LB", "RB", "LT", "RT",
	"L/R", "R/L", "Select", "Start", "Share", "Minus", "Plus"]

## Assignments a player actually reads. A token in a variable name or a dictionary key is not a
## caption, and neither is one in a comment — the scan strips those.
const UI_SINKS := [".text =", ".text +=", "draw_string(", "hint_text(", "tooltip_text ="]

## ⛔ DECLARED, NOT SKIPPED. MenuScene renders four "[L/R] Change Character" captions — the frozen
## Nintendo shoulder pair, on a screen whose own _input cycles the party on both shoulders. They
## are not fixed here because NOTHING REACHES THEM: MenuScene.tscn is referenced by no file and no
## uid, and MenuScene.gd is instantiated nowhere in src/ (measured 2026-09-16; three other test
## files record the same orphan independently). Deriving captions on a dead screen would be a
## change whose only effect is on a player who cannot get there.
## The arm below makes the exemption expire: the day anything instantiates it, this reds.
const DECLARED_ORPHANS := {
	"res://src/ui/MenuScene.gd": "orphan — MenuScene.tscn referenced by nothing, .gd instantiated nowhere in src/",
}


func _gd_files_under(dir_path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			out.append_array(_gd_files_under(full))
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return out


## A token counts only where it names a button: bracketed, followed by a colon, or after an
## imperative. "Select an ability" is the English verb and must never red.
func _frozen_tokens_in(text: String) -> Array:
	var found: Array = []
	for tok in FAMILY_PAD_TOKENS:
		if text.find("[%s]" % tok) > -1 or text.find("[%s " % tok) > -1:
			found.append(tok)
			continue
		if text.find("%s:" % tok) > -1 or text.find("%s :" % tok) > -1:
			found.append(tok)
			continue
		for verb in ["Press ", "Hold ", "Tap "]:
			if text.find(verb + tok) > -1:
				found.append(tok)
				break
	return found


func _scan_for_frozen_captions() -> Dictionary:
	var GdSource = load("res://test/unit/helpers/gd_source.gd")
	var result := {"offenders": [], "scanned": 0, "orphan_hits": []}
	for path in _gd_files_under("res://src"):
		var code: String = GdSource.code_of(path)
		if code == "":
			continue
		result["scanned"] += 1
		for line in code.split("\n"):
			var is_sink := false
			for sink in UI_SINKS:
				if line.find(sink) > -1:
					is_sink = true
					break
			if not is_sink:
				continue
			for tok in _frozen_tokens_in(line):
				var entry := "%s -> %s" % [path.get_file(), tok]
				if DECLARED_ORPHANS.has(path):
					result["orphan_hits"].append(entry)
				else:
					result["offenders"].append(entry)
	return result


## THE ARM THE HAND-LIST COULD NOT BE. Every .gd under src/, not five paths.
func test_no_reachable_caption_freezes_a_family_pad_token() -> void:
	var scan := _scan_for_frozen_captions()
	assert_gt(scan["scanned"], 200,
		"the scan must read the whole src/ tree; a short corpus passes vacuously")
	assert_eq(scan["offenders"], [],
		"these captions name a button one pad family prints, on a surface a player reaches: %s"
			% [scan["offenders"]])


## ANTI-VACUITY, both directions: the matcher must catch a button token and must ignore the verb.
## Without this, an empty offender list is equally consistent with a scan that matches nothing.
func test_the_matcher_catches_a_button_and_spares_the_verb() -> void:
	assert_eq(_frozen_tokens_in('hint.text = "[L/R] Change Character"'), ["L/R"],
		"a bracketed shoulder pair is a button caption and must be caught")
	# R1, not L1: the colon rule catches the token TOUCHING the colon, and in a pair caption that
	# is the right-hand one. Catching either is enough — the offender list is per line, so one hit
	# reds the caption. Pinned as measured rather than as I first assumed it would read.
	assert_eq(_frozen_tokens_in('footer.text = "L1/R1: Page"'), ["R1"],
		"a token followed by a colon is a button caption")
	assert_eq(_frozen_tokens_in('label.text = "Press Select to continue"'), ["Select"],
		"an imperative names a button — and no current pad family prints Select")
	assert_eq(_frozen_tokens_in('title.text = "Select an ability"'), [],
		"the English verb must never red; that is the noise that gets a guard silenced")
	assert_eq(_frozen_tokens_in('lbl.text = "Start the battle"'), [],
		"…nor a verb that happens to share a button name")


## THE EXEMPTION EXPIRES. MenuScene's four frozen captions are excused because nothing can reach
## them; if that stops being true the excuse must stop with it, rather than outliving its fact.
func test_the_declared_orphan_is_still_unreachable() -> void:
	var scan := _scan_for_frozen_captions()
	assert_ne(scan["orphan_hits"], [],
		"MenuScene's frozen captions must still be FOUND — if they were fixed, delete this "
		+ "declaration rather than leaving a note that no longer describes anything")

	for path in DECLARED_ORPHANS:
		var referenced: Array = []
		for candidate in _gd_files_under("res://src"):
			if candidate == path:
				continue
			var code: String = FileAccess.get_file_as_string(candidate)
			if code.find(path.get_file()) > -1 or code.find(path) > -1:
				referenced.append(candidate.get_file())
		assert_eq(referenced, [],
			"%s is no longer an orphan (%s reference it), so its captions are now reachable and "
			% [path.get_file(), referenced]
			+ "must be derived through InputProfileManager before this declaration is removed")
