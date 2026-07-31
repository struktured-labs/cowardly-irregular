extends GutTest

## Joins data/monsters.json to the manifest's monster_sheets — nothing did before.
## A monster with no sheet does not error: _get_monster_sprite_frames' `_:` arm renders it as a SLIME.
## Measured 2026-07-31 on b0035203: 98/98 resolve, 0/106 stale, so all 45 named procedural arms are unreachable.

const MONSTERS_PATH := "res://data/monsters.json"
const MANIFEST_PATH := "res://data/sprite_manifest.json"

## Art shipped ahead of its stat block — sheet registered, monsters.json entry pending.
const PRESHIPPED_SHEETS := ["the_coordinator", "the_director", "the_regulator"]


func _monsters() -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(MONSTERS_PATH))
	return raw if raw is Dictionary else {}


func _monster_sheets() -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not (raw is Dictionary):
		return {}
	return raw.get("monster_sheets", {})


## Mirrors load_monster_sprite_frames' own default so this measures what the loader measures.
func _sheet_path(sheet_id: String, sheet_data: Dictionary) -> String:
	return sheet_data.get("path", "res://assets/sprites/monsters/%s.png" % [sheet_id])


func test_every_monster_resolves_to_a_real_sheet() -> void:
	var monsters := _monsters()
	var sheets := _monster_sheets()
	# NAMED controls, not a size floor — a floor passes while the parse shape drifts.
	for known in ["slime", "goblin", "chancellor_mordaine"]:
		assert_true(monsters.has(known),
			"monsters.json must yield '%s' — if it does not, the parse shape drifted and every result below measures the wrong set" % [known])
		assert_true(sheets.has(known),
			"monster_sheets must yield '%s' — same reason" % [known])

	var unsheeted: Array = []
	for mid in monsters:
		if not sheets.has(mid):
			unsheeted.append("%s: no monster_sheets entry" % [mid])
			continue
		var p := _sheet_path(mid, sheets[mid])
		if not ResourceLoader.exists(p):
			unsheeted.append("%s: registered but %s is missing" % [mid, p])
	unsheeted.sort()
	assert_eq(unsheeted, [],
		"monster(s) with no loadable sheet — each renders as a SLIME through the default arm, with no error and no warning: %s" % [unsheeted])


func test_every_registered_sheet_path_exists() -> void:
	var sheets := _monster_sheets()
	assert_gt(sheets.size(), 50, "sanity: expected >50 monster sheets, found %d" % [sheets.size()])
	var broken: Array = []
	for sid in sheets:
		var p := _sheet_path(sid, sheets[sid])
		if not ResourceLoader.exists(p):
			broken.append("%s -> %s" % [sid, p])
	broken.sort()
	assert_eq(broken, [],
		"manifest entr(ies) name a missing PNG — load_monster_sprite_frames returns null and the monster falls silently to procedural: %s" % [broken])


## THE EXPIRY — without it PRESHIPPED_SHEETS becomes a note that waits, like KNOWN_HEAVY_TOP did.
func test_preshipped_sheets_are_still_awaiting_stat_blocks() -> void:
	var monsters := _monsters()
	var sheets := _monster_sheets()
	var landed: Array = []
	for sid in PRESHIPPED_SHEETS:
		assert_true(sheets.has(sid),
			"'%s' is recorded here as finished art awaiting a stat block — its manifest entry must still exist" % [sid])
		if monsters.has(sid):
			landed.append(sid)
	# COLLECT then assert once, so this still asserts when the list drains.
	assert_eq(landed, [],
		"stat block(s) landed for pre-shipped art — delete them from PRESHIPPED_SHEETS, the main join covers them now: %s" % [landed])
