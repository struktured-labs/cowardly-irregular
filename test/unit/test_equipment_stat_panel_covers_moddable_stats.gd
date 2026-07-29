extends GutTest

## `magic_defense` became a real stat on 2026-07-29 (it had been `defense * 0.5` inline), and the
## same day equipment gained the ability to modify ANY stat rather than a hardcoded six. The
## equipment screen did not get the memo:
##
##   comparison row   `for stat_name in all_stats:` — GENERIC, reads whatever keys stat_mods holds,
##                    names them via StatNames. It picked up MDF automatically.
##   STATS panel      a hand-written list. It did not.
##
## So a +40 M.DEF accessory printed "+40 MDF" as a delta, next to a panel where M.DEF appeared
## nowhere. Delta visible, total invisible — worse than omitting both, because the player is shown a
## bonus to a stat their character apparently does not have.
##
## THE GUARD IS DERIVED, NOT LISTED: every Combatant.MODDABLE_STATS entry must have a row. Add a
## stat to that const and this fails until the panel shows it — which is the actual defect class.
## A hand-maintained list of seven codes would have rotted exactly the way the panel did.

const EQUIP_PATH := "res://src/ui/EquipmentMenu.gd"


func _panel_source() -> String:
	var txt := FileAccess.get_file_as_string(EQUIP_PATH)
	assert_ne(txt, "", "must be able to read EquipmentMenu")
	# Only the stats-array literal, so an unrelated mention elsewhere cannot satisfy the check.
	var start := txt.find("var stats = [")
	assert_ne(start, -1, "the stats array literal must exist — if this moved, the guard needs updating, not deleting")
	# The array's CLOSING bracket, not the first "]" after the opening — that one ends row 1, so a
	# naive find() extracted a single line and reported every other stat missing. The first version
	# of this guard was red on a correct tree AND gave byte-identical output for two different
	# mutations, which is the tell that it was measuring nothing.
	var stop := txt.find("\n\t]", start)
	assert_ne(stop, -1, "could not find the array's closing bracket")
	var body := txt.substr(start, stop - start)
	# Positive control: the extracted region must contain more than one row.
	assert_gt(body.split("character.").size() - 1, 3,
		"extraction failed — the stats array should hold several `character.<stat>` reads, got: %s" % body)
	return body


func test_every_moddable_stat_has_a_row_in_the_equipment_panel() -> void:
	var combatant = load("res://src/battle/Combatant.gd")
	var moddable: Array = combatant.MODDABLE_STATS
	assert_gt(moddable.size(), 4, "positive control: MODDABLE_STATS must be a real list, not empty")

	var panel := _panel_source()
	var missing: Array[String] = []
	for stat in moddable:
		# The panel renders `character.<stat>`; that is the accessor a row must contain.
		if not panel.contains("character.%s" % stat):
			missing.append(stat)
	assert_eq(missing, [] as Array[String],
		"equipment is able to modify these stats and the comparison row will print a delta for them, but the STATS panel never shows a total: %s" % str(missing))


## The specific regression, by name.
func test_magic_defense_is_displayed() -> void:
	var panel := _panel_source()
	assert_true(panel.contains("character.magic_defense"),
		"M.DEF was the only MODDABLE_STAT with no row; a +40 M.DEF accessory showed a delta for a stat the panel did not list")
	assert_true(panel.contains("\"MDF\""),
		"must use the MDF short code — StatNames maps magic_defense to MDF precisely because a substr fallback yields MAG and collides with magic")


## The code the panel prints must be the one the comparison row prints, or the same stat appears
## under two names on one screen.
func test_panel_code_agrees_with_the_naming_authority() -> void:
	var stat_names = load("res://src/ui/StatNames.gd")
	assert_eq(stat_names.short_code("magic_defense"), "MDF",
		"StatNames is the authority for the short code; the panel literal must match what the comparison row renders")
