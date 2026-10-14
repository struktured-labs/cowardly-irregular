extends GutTest

## ⛔ USE A PARTY-WIDE, AoE OR SELF-TARGET ABILITY AND THE COMMAND MENU FORGETS WHERE YOU WERE.
## Found in struktured's own .684 session log, twice, named by the game itself:
##
##     212  [CMD MEM] Bard -> ability_menu / ability_battle_hymn (advance)
##     441  [CMD MEM] Skipping invalid ability memory 'ability_battle_hymn' for Bard
##     442  [CMD MEM] Submenu memory: {  }                     <- his position, gone
##     251/463/464  the same for Mage / ability_firaga
##
## 🔑 THE MECHANISM IS A COUPLING BETWEEN TWO FORMATS. The validator strips exactly
## `"ability_menu_"` and then asks `JobSystem.can_use_ability` about what is left. A row id of
## `ability_<id>` survives that strip UNCHANGED, so the question asked is about
## `"ability_battle_hymn"` — never a real ability id — and the answer is always no.
##
## ⚠️ WHICH ROWS: the ones carrying no target suffix. `_enemy_`/`_ally_`/`_dead_` rows already hit
## an elif that normalises them, which is why cure-on-an-ally and fire-on-an-enemy were remembered
## in the same session. AoE, `[All]`, self-target and unaffordable rows took the else and were not.
##
## ✅ Fixed at the STORE, not the validator, so all four branches emit one format. The arms below
## pin BOTH SIDES of the coupling: a future change to either one reds here rather than silently
## reintroducing the mismatch.

const MENU_PATH := "res://src/battle/BattleCommandMenu.gd"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")


func _code() -> String:
	return GdSource.code_of(MENU_PATH)


func test_the_source_is_readable() -> void:
	assert_gt(_code().length(), 1000, "PRECONDITION: the command menu's code half must be readable")


## SIDE ONE: no store branch may keep a raw row id. Derived over every assignment, so a fifth
## branch added later is covered without editing this file.
func test_no_store_branch_keeps_a_raw_row_id() -> void:
	var offenders: Array = []
	for line in _code().split("\n"):
		var l: String = str(line)
		if not l.contains("last_ability_selection ="):
			continue
		## The three legitimate forms: the suffix-strip, the normalising concat, and a guarded
		## fallback that only applies when there is no ability_id to normalise with.
		## ⚠️ `= ""` IS NOT ALLOWED HERE ANY MORE. It was, while the validator erased the memory
		## on a refusal; that erase is gone (see the arm below) and all six assignments in this file
		## are now store forms. Leaving the allowance in would let the erase return invisibly.
		var ok: bool = l.contains("ability_menu_") or l.contains(".substr(")
		if not ok:
			offenders.append(l.strip_edges())
	assert_eq(offenders, [],
		"every store of last_ability_selection must emit the ability_menu_ form — a raw row id "
		+ "survives the validator's strip and is rejected as an unknown ability: %s" % [offenders])


## ⛔ SECOND HALF: A TRANSIENT REFUSAL MUST NOT ERASE THE MEMORY. `can_use_ability` refuses for
## reasons that pass — `has_status("silence")` at JobSystem:761, and the MP cost at :766 — and the
## validator used to answer by blanking `last_ability_selection`. So a two-turn silence forgot the
## player's position permanently, and my normalisation above made that newly reachable for the
## party-wide abilities that previously never persisted at all.
##
## ⚠️ EVIDENCE DIFFERS FROM THE FIRST HALF, and I am not blurring them: the format mismatch is in
## HIS log twice, named by the game. This half is a code read — his session contains no
## silence-driven clear, so it is reachable rather than observed.
##
## ✅ Skipping without erasing is safe because the key is only ever APPLIED when this same check
## passes: an ability truly lost to a job change is skipped every turn and never used.
func test_a_refusal_skips_the_memory_without_erasing_it() -> void:
	var code: String = _code()
	var at: int = code.find("Skipping invalid ability memory")
	assert_gt(at, 0, "PRECONDITION: the refusal branch must still be findable")
	if at <= 0:
		return
	## Bounded at the next statement block, not a fixed width.
	var upto: int = code.find("if combatant.last_item_selection", at)
	assert_gt(upto, at, "PRECONDITION: the refusal branch must be bounded by the next field's check")
	if upto <= at:
		return
	var branch: String = code.substr(at, upto - at)
	assert_false(branch.contains('last_ability_selection = ""'),
		"a refusal must SKIP the memory for this turn, not erase it — silence and an MP shortfall "
		+ "both pass, and erasing makes a temporary condition permanent")


## SIDE TWO: the validator still strips exactly that prefix. If it ever strips something else, the
## store above is emitting the wrong format and this arm is the warning.
func test_the_validator_still_strips_that_exact_prefix() -> void:
	var code: String = _code()
	## assert_true, not assert_string_contains: on failure the latter prints the whole 4000-line
	## haystack and buries the reason. A guard whose red is unreadable costs the next reader more
	## than it saves.
	assert_true(code.contains('replace("ability_menu_", "")'),
		"the validator must still strip 'ability_menu_' — the store format above is chosen to "
		+ "match it, so a change here without a change there silently breaks the memory again")
	assert_true(code.contains("can_use_ability"),
		"and must still ask whether the remembered id is usable, which is what the strip feeds")


## THE DEFECT, as a control: the old raw form does not survive the strip, so the question the
## validator asks about it can never be answered yes. This is why normalising is the fix.
func test_the_raw_form_is_exactly_what_the_strip_cannot_fix() -> void:
	var raw := "ability_battle_hymn"
	var normalised := "ability_menu_battle_hymn"
	assert_eq(raw.replace("ability_menu_", ""), "ability_battle_hymn",
		"CONTROL: the raw form survives the strip with its prefix — this is the bug, verbatim")
	assert_eq(normalised.replace("ability_menu_", ""), "battle_hymn",
		"CONTROL: the normalised form yields the real ability id, which can_use_ability can answer")
	assert_ne(raw.replace("ability_menu_", ""), normalised.replace("ability_menu_", ""),
		"CONTROL: and the two forms are not interchangeable, which is the whole defect")
