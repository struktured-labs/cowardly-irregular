extends GutTest

## tick 141 regression suite: sweep of `.get("name", <raw_id>)`
## patterns. When the data dict is empty (item/ability/passive/job
## not found in its system), the fallback used to leak the raw
## snake_case id. Now each call site prettifies the id at the
## `.get` default position so the player at least sees title-cased
## words instead of internal snake_case identifiers.
##
## Affected files:
##   - JobMenu: ability id ×2 (job_id + secondary_job_id moved to JobSystem in tick 335)
##   - AbilitiesMenu (4 sites): ability row + detail, passive row + detail
##   - PartyStatusScreen (1 site): equipment _resolve fallback

const JOB_MENU := "res://src/ui/JobMenu.gd"
const ABILITIES_MENU := "res://src/ui/AbilitiesMenu.gd"
const PARTY_STATUS := "res://src/ui/PartyStatusScreen.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── JobMenu ──────────────────────────────────────────────────────────────

## tick 335: the job_id/secondary_job_id fallback moved into JobSystem.get_job_display_name.
func test_job_display_name_prettifies_an_unknown_id() -> void:
	var out: String = JobSystem.get_job_display_name("some_unknown_id")
	assert_false(out.contains("_"),
		"fallback leaked raw snake_case to the player: '%s'" % out)
	assert_eq(out, "Some Unknown Id",
		"an unknown job id must render title-cased, not as a raw identifier")


## Guards the resolver being swapped for a bare prettifier: an ALIAS must reach real job data.
func test_job_display_name_resolves_data_rather_than_prettifying() -> void:
	var saved: int = int(GameState.current_world)
	GameState.current_world = 1
	var out: String = JobSystem.get_job_display_name("white_mage")
	GameState.current_world = saved
	assert_eq(out, "Cleric",
		"'white_mage' must resolve through the alias to real job data; got '%s'" % out)
	assert_ne(out, "White Mage",
		"prettifying the raw id instead of resolving it is the defect this file exists to catch")


func test_job_menu_ability_name_prettifies_id_in_two_sites() -> void:
	# Both _create_ability_row-style sites (current job abilities
	# preview AND the available-jobs list job_data abilities).
	var src := _read(JOB_MENU)
	# Site 1: current job ability preview.
	assert_true(src.contains("ability_label.text = ability.get(\"name\", ability_id.replace(\"_\", \" \").capitalize())"),
		"current-job ability preview must prettify ability_id fallback")
	# Site 2: target-job ability_names list.
	assert_true(src.contains("ability_names.append(ability.get(\"name\", ability_id.replace(\"_\", \" \").capitalize()))"),
		"available-job ability_names must prettify fallback")


## The labels must keep ROUTING through the resolver -- unwiring them re-opens the raw-id leak.
func test_job_menu_labels_route_through_the_resolver() -> void:
	var src := _read(JOB_MENU)
	# Floor is 1, not the current 5: a wrapper refactor is CORRECT and would trip a tighter
	# count. Blind spot accepted -- unwiring SOME sites passes; the arms above cover the resolver.
	assert_gt(src.count("JobSystem.get_job_display_name("), 0,
		"JobMenu no longer resolves display names anywhere -- the raw-id leak is re-openable")


# ── AbilitiesMenu ────────────────────────────────────────────────────────

func test_abilities_menu_row_name_prettifies_id() -> void:
	var src := _read(ABILITIES_MENU)
	assert_true(src.contains("name_label.text = data.get(\"name\", str(ability[\"id\"]).replace(\"_\", \" \").capitalize())"),
		"AbilitiesMenu row name labels must prettify ability id fallback")
	# Negative pin: the raw-id fallback must be gone.
	# (At least one of the two sites; using occurrence count.)
	var count: int = 0
	var search_from: int = 0
	while true:
		var found: int = src.find("data.get(\"name\", ability[\"id\"])", search_from)
		if found < 0:
			break
		count += 1
		search_from = found + 1
	assert_eq(count, 0,
		"old raw `data.get('name', ability['id'])` fallback must be gone — would leak snake_case")


func test_abilities_menu_passive_name_prettifies_id() -> void:
	var src := _read(ABILITIES_MENU)
	assert_true(src.contains("name_label.text = data.get(\"name\", str(passive[\"id\"]).replace(\"_\", \" \").capitalize())"),
		"AbilitiesMenu passive name labels must prettify passive id fallback")
	var count: int = 0
	var search_from: int = 0
	while true:
		var found: int = src.find("data.get(\"name\", passive[\"id\"])", search_from)
		if found < 0:
			break
		count += 1
		search_from = found + 1
	assert_eq(count, 0,
		"old raw `data.get('name', passive['id'])` fallback must be gone")


# ── PartyStatusScreen ────────────────────────────────────────────────────

func test_party_status_equipment_fallback_prettifies_id() -> void:
	# Tick 204 upgraded the prettifier to proper title-case via the
	# now-fixed _format_id helper (String.capitalize() only does the
	# first letter — see tick 186). Pin the new shape, which still
	# carries the original tick 141 invariant: the fallback must
	# never leak raw snake_case.
	var src := _read(PARTY_STATUS)
	assert_true(src.contains("item_name = info.get(\"name\", _format_id(item_id))"),
		"PartyStatusScreen equipment fallback must use _format_id (proper title case)")
	assert_false(src.contains("item_name = info.get(\"name\", item_id)\n"),
		"old raw item_id fallback must be gone")


# ── Sanity: existing canonical paths still in place ──────────────────────

func test_canonical_data_lookups_unchanged() -> void:
	# Negative regression: don't accidentally regress tick 132's
	# JobSystem.get_ability wiring in AbilitiesMenu's _get_ability_data.
	var src := _read(ABILITIES_MENU)
	assert_true(src.contains("JobSystem.get_ability(ability_id)"),
		"tick 132 JobSystem wiring must remain — fallback prettifier only fires when data is empty")
