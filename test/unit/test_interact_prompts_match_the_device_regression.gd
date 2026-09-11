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


## Files whose prompt must derive. Listed rather than globbed so a new file is not silently
## exempted by a directory scan that happens to miss it.
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
