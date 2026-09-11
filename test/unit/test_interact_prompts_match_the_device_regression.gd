extends GutTest

## The floating "[A] Examine" prompt is the MOST-SEEN control label in the game — it appears every
## time you walk up to anything in the overworld — and it was frozen in 14 files.
##
##     keyboard      the interact key is Z, there is no A button
##     Xbox          Confirm is the EAST face: Ⓑ, not Ⓐ
##     PlayStation   ○, not Ⓐ
##     Nintendo      Ⓐ — the one family the old literal was right for
##
## Same defect as the battle hint bar, the menu legends and the character-creation screen, at the
## highest exposure of any of them. Now derived through InputProfileManager.hint_for_action().
##
## 🔑 THREE PRIOR AUTHORS HIT THIS CLASS AND FIXED IT LOCALLY: PartyChatIndicator dropped its bare
## "[L]" at tick 470, CutsceneDirector has skip_prompt_text, and ReadableProp has close_glyph() —
## each with a comment explaining that a frozen cap names the wrong button on some pad. Three
## independent local fixes and no shared helper is why it regrew 14 times.
##
## ⚠️ SCOPE: src/exploration prompts. The scan looks for a literal in an ASSIGNMENT or RETURN, not
## anywhere in the file, because the surviving "[B]" in ReadableProp is inside a COMMENT describing
## the bug it already fixed — and a scan that flagged that would be reporting a fix as a defect.

const EXPLORATION := "res://src/exploration"


## Files whose prompt must derive. This list is the POSITIVE half only — "these known files still
## derive". It is NOT the corpus: a list cannot see a file that does not exist yet, and the negative
## arm below walks the directory instead.
##
## ⚠️ MY ORIGINAL JUSTIFICATION HERE WAS BACKWARDS. It read "listed rather than globbed so a new file
## is not silently exempted by a directory scan that happens to miss it" — but a LIST exempts every
## new file unconditionally. Measured 2026-09-11: a fresh Area2D in src/exploration with
## `_label.text = "[A] Examine probe"` passed this file GREEN at 4/4. Same shape as cowir-sfx's
## ambient guard, which scoped its corpus `begins_with("ambient_")` and was therefore blind to the
## six `weather_*` keys that were actually breaking the contract it defended.
const CONVERTED := [
	"BulletinBoard.gd", "MissingPackage.gd", "TallyWall.gd", "QuestExaminePoint.gd",
	"FireplaceSecret.gd", "AnnexLiberation.gd", "SwordInscription.gd", "CivicFrontDesk.gd",
	"CivicBackDoor.gd", "LockedDoorFlavor.gd", "VillageBar.gd", "WildflowerPatch.gd",
	"SavePoint.gd", "WanderingNPC.gd",
]


func _read(fname: String) -> String:
	var src := FileAccess.get_file_as_string("%s/%s" % [EXPLORATION, fname])
	assert_gt(src.length(), 50, "PRECONDITION: %s must be readable" % fname)
	return src


## THE RATCHET. A frozen cap may not come back in an assignment or a return.
func test_no_prompt_freezes_a_face_letter() -> void:
	var frozen := RegEx.create_from_string("(?:=|return)\\s*\"\\[(A|B)\\]")
	var offenders: Array[String] = []
	for fname in CONVERTED:
		var src := _read(fname)
		if frozen.search(src) != null:
			offenders.append(fname)
		if not src.contains("hint_for_action"):
			offenders.append("%s does not derive its prompt" % fname)
	assert_eq(offenders, [] as Array[String],
		"an interact prompt hardcodes a face letter — right on Nintendo, wrong on every other pad " +
		"and meaningless on a keyboard: %s" % [", ".join(offenders)])


## CONTROL: the scanner must be able to SEE a frozen literal, or the arm above is vacuous. Uses the
## real pattern against a synthetic line rather than trusting that zero offenders means it looked.
func test_the_frozen_scanner_can_fire() -> void:
	var frozen := RegEx.create_from_string("(?:=|return)\\s*\"\\[(A|B)\\]")
	assert_not_null(frozen.search('\t_label.text = "[A] Examine"'),
		"CONTROL: the pattern must match a frozen assignment")
	assert_not_null(frozen.search('\treturn "[B] Close"'),
		"CONTROL: and a frozen return")
	assert_null(frozen.search('## the old "[B]" named the wrong cap on Nintendo pads'),
		"CONTROL: it must NOT match a COMMENT — ReadableProp documents its own fix that way")


## The prompts must resolve differently per family, or deriving them achieved nothing.
func test_the_prompt_glyph_varies_by_device() -> void:
	var kb: String = InputProfileManager.hint_for_action("ui_accept")
	var xb: String = InputProfileManager.hint_for_action("ui_accept", "Xbox Wireless Controller")
	var nin: String = InputProfileManager.hint_for_action("ui_accept", "Nintendo Switch Pro Controller")
	assert_eq(kb, "Z", "with no pad the prompt must name the keyboard key")
	assert_ne(xb, nin, "Xbox and Nintendo must disagree, or the old literal was never wrong")
	assert_eq(nin, str(InputProfileManager.FACE_GLYPHS["nintendo"][1]),
		"Nintendo is the ONE family the frozen [A] matched — which is how it survived")


## SavePoint carries a second binding, and it varies too: R / RB / R1.
func test_the_warp_prompt_varies_by_device() -> void:
	var src := _read("SavePoint.gd")
	assert_true(src.contains("hint_for_action(\"battle_advance\")"),
		"the Warp half of the save prompt must derive as well")
	assert_eq(InputProfileManager.hint_for_action("battle_advance", "DualSense Wireless Controller"), "R1",
		"PlayStation calls the right shoulder R1, not R")

## THE DERIVED ARM. Walks src/exploration rather than trusting CONVERTED, so a file added next week
## is in the corpus the moment it exists.
func _exploration_scripts() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(EXPLORATION)
	assert_not_null(d, "PRECONDITION: %s must be walkable" % EXPLORATION)
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if not d.current_is_dir() and name.ends_with(".gd"):
			out.append(name)
		name = d.get_next()
	d.list_dir_end()
	out.sort()
	return out


## A frozen literal anywhere in CODE. The discriminator is "is this line a comment", which is what
## actually separates a defect from ReadableProp's note about the bug it already fixed — NOT
## "does it follow an equals sign", which was a PROXY for that and blind to every other authoring
## form. Measured: `_label.set_text("[A] ...")` passed the old pattern. Zero files in src/ use
## set_text today, so that gap was latent rather than live — recorded as a gap, not a discovery.
func _frozen_code_lines(src: String) -> Array[String]:
	var hits: Array[String] = []
	for raw in src.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("#"):
			continue
		if line.contains("\"[A]") or line.contains("\"[B]"):
			hits.append(line)
			continue
		# A hardcoded GLYPH is the same defect in a different costume — and it is the repair this
		# guard's own red INVITES: told "[A]" is wrong, the cheap fix is to paste the "proper"
		# symbol, which is Nintendo's and equally wrong on Xbox and PlayStation. Derived from
		# FACE_GLYPHS so a new family cannot open a hole here.
		for g in _all_face_glyphs():
			if line.contains("\"%s " % g) or line.contains("\"%s\"" % g):
				hits.append(line)
				break
	return hits


## Every distinct face glyph across all families, DEDUPLICATED. Ⓐ appears in both the Nintendo
## table (index 1) and the Xbox table (index 0), so a naive nested loop counts one line twice —
## it did, and the count assert caught it.
func _all_face_glyphs() -> Array[String]:
	var out: Array[String] = []
	for family in InputProfileManager.FACE_GLYPHS:
		for idx in InputProfileManager.FACE_GLYPHS[family]:
			var g: String = str(InputProfileManager.FACE_GLYPHS[family][idx])
			if not out.has(g):
				out.append(g)
	return out


## CONTROL: the walker must actually be walking, and must reach files the LIST does not name.
func test_the_walker_sees_more_than_the_list() -> void:
	var found := _exploration_scripts()
	assert_gt(found.size(), CONVERTED.size(),
		"the walker must reach MORE files than the hardcoded list, or it is the list with extra steps")
	assert_true(found.has("SavePoint.gd"), "CONTROL: a known member must appear")
	assert_false(found.has("ZzqNotAFile.gd"), "CONTROL: the walker can report a name absent")


## ANY file in the directory — listed or not — may not freeze a face letter in an assignment or
## return. This is the arm that catches the file nobody has written yet.
func test_no_exploration_file_freezes_a_face_letter() -> void:
	var offenders: Array[String] = []
	for fname in _exploration_scripts():
		var src := FileAccess.get_file_as_string("%s/%s" % [EXPLORATION, fname])
		if not _frozen_code_lines(src).is_empty():
			offenders.append(fname)
	assert_eq(offenders, [] as Array[String],
		"a file in src/exploration freezes a face letter in an assignment or return — right on " +
		"Nintendo, wrong on every other pad: %s" % [", ".join(offenders)])

## CONTROL for the line-level discriminator: it must catch EVERY authoring form and still exclude a
## comment. The old pattern matched only the first of these three.
func test_the_line_scanner_catches_every_authoring_form() -> void:
	assert_eq(_frozen_code_lines("\t_label.text = \"[A] Examine\"").size(), 1,
		"assignment form must be caught")
	assert_eq(_frozen_code_lines("\t_label.set_text(\"[A] Examine\")").size(), 1,
		"SETTER form must be caught — the old =/return pattern was blind to it")
	assert_eq(_frozen_code_lines("\treturn \"[B] Close\"").size(), 1, "return form must be caught")
	assert_eq(_frozen_code_lines("## the old \"[B]\" named the wrong cap on Nintendo pads").size(), 0,
		"CONTROL: a COMMENT must NOT be flagged — ReadableProp documents its own fix that way")
	assert_eq(_frozen_code_lines("\t_label.text = hint + \" Examine\"").size(), 0,
		"CONTROL: a derived line must not be flagged")

## THE THIRD PASS. Two arms above already shipped; this one exists because five lanes tonight found
## a SECOND defect in a file that had just survived the first check, and the named mechanism is that
## fixing a guard creates the belief you understand it. Looked again and the gap was the repair the
## red invites: paste the glyph instead of the letter.
func test_a_hardcoded_glyph_is_caught_too() -> void:
	var nin: String = str(InputProfileManager.FACE_GLYPHS["nintendo"][1])
	var ps: String = str(InputProfileManager.FACE_GLYPHS["playstation"][1])
	assert_eq(_frozen_code_lines("\t_label.text = \"%s Examine\"" % nin).size(), 1,
		"a frozen Nintendo glyph must be caught — it is wrong on Xbox and PlayStation exactly as [A] was")
	assert_eq(_frozen_code_lines("\t_label.text = \"%s Examine\"" % ps).size(), 1,
		"and a frozen PlayStation glyph, which is wrong everywhere else")
	assert_eq(_frozen_code_lines("\t_label.text = hint + \" Examine\"").size(), 0,
		"CONTROL: a derived line must still not fire")
	assert_eq(_frozen_code_lines("## the old \"%s\" named the wrong cap" % nin).size(), 0,
		"CONTROL: a glyph inside a COMMENT must not fire — the same exclusion the letters get")

## ⛔ THE DIRECTORY WAS THE WRONG CORPUS, and deriving the DEFAULT did not protect the OVERRIDES.
## LockedDoorFlavor and QuestExaminePoint declare `indicator_text` with a derived default — but a
## caller can set it explicitly, and two did, in a directory this file never scanned:
##
##     src/maps/interiors/TavernInterior.gd     locked.indicator_text   = "[A] Locked"
##     src/maps/dungeons/SteampunkMechanism.gd  junction.indicator_text = "[A] Trace the junction"
##
## Both shipped in .295 still saying [A] on every controller, while every other instance of the
## SAME CLASS derived correctly. The corpus has to follow the PROPERTY, not the folder — the
## consumer-derived rule, arriving via a fix of mine that created its own blind spot.
const SRC_ROOT := "res://src"


func _all_src_scripts() -> Array[String]:
	var out: Array[String] = []
	var stack: Array[String] = [SRC_ROOT]
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		d.list_dir_begin()
		var fname := d.get_next()
		while fname != "":
			var full := dir_path + "/" + fname
			if d.current_is_dir():
				if not fname.begins_with("."):
					stack.append(full)
			elif fname.ends_with(".gd"):
				out.append(full)
			fname = d.get_next()
		d.list_dir_end()
	out.sort()
	return out


## CONTROL: the recursive walk must reach BEYOND src/exploration, or it cannot see the defect it
## was written for.
func test_the_src_walk_reaches_other_directories() -> void:
	var all := _all_src_scripts()
	assert_gt(all.size(), 200, "PRECONDITION: the walk must reach the whole tree")
	assert_true(all.has("res://src/maps/interiors/TavernInterior.gd"),
		"CONTROL: it must reach src/maps — the directory the override defect lived in")
	assert_true(all.has("res://src/exploration/SavePoint.gd"), "CONTROL: and still src/exploration")


## NOBODY may set indicator_text to a frozen cap, in ANY directory. This is the arm the two
## overrides would have tripped.
func test_no_indicator_text_override_freezes_a_cap() -> void:
	var offenders: Array[String] = []
	for path in _all_src_scripts():
		for raw in FileAccess.get_file_as_string(path).split("\n"):
			var line: String = raw.strip_edges()
			if line.begins_with("#"):
				continue
			if not line.contains("indicator_text"):
				continue
			if not _frozen_code_lines(line).is_empty():
				offenders.append("%s :: %s" % [path.get_file(), line.substr(0, 60)])
	assert_eq(offenders, [] as Array[String],
		"a caller overrides indicator_text with a frozen cap — deriving the class DEFAULT does not " +
		"protect explicit assignments: %s" % [", ".join(offenders)])
