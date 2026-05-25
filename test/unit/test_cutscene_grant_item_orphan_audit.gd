extends GutTest

## Audit: cross-reference cutscene grant_item / give_item / update_item
## step item IDs against items.json. Pre-audit, 29 distinct item IDs
## granted across the W1-W5 fragment + orrery cutscenes had NO matching
## entry in items.json. Result: cutscene completes, item lands in
## inventory as a ghost (no name, no description, no use). Same silent-
## failure class as the original missing-dispatch bug — pinned here as
## a regression ratchet so:
##   - new orphans = test fails loud (catches authoring drift)
##   - existing orphans being closed = test continues to pass (no churn)
##
## KNOWN_ORPHAN_ITEMS is a deliberately-allowed allowlist of the current
## state (snapshot 2026-05-25 audit). As cowir-story authors entries
## for each item in items.json, the corresponding KNOWN_ORPHAN_ITEMS
## entry should be removed.

const ITEMS_JSON_PATH := "res://data/items.json"
const CUTSCENES_DIR := "res://data/cutscenes"

# Snapshot 2026-05-25 — 29 cutscene-granted items that have no items.json
# entry. Each is a key item or fragment from a story cutscene. Remove
# entries from this list as items.json gets authored.
const KNOWN_ORPHAN_ITEMS := {
	"annotated_blueprint": true,
	"arbiter_grade_fragment": true,
	"arbiters_recognition": true,
	"cogsworth_calibration_key": true,
	"compressed_data_object": true,
	"curator_budget_fragment": true,
	"enchanted_sweater": true,
	"fool_card": true,
	"life_coaching_summary": true,
	"luck_charm_minor": true,
	"old_guard_tally": true,
	"orrery_deviation_report": true,
	"orrery_pendant": true,
	"tempo_rush_fragment": true,
	"tempos_quarry": true,
	"the_carried_flame": true,
	"warden_routine_fragment": true,
	"world3_fragment_arbiter_steampunk": true,
	"world3_fragment_curator_steampunk": true,
	"world3_fragment_tempo_steampunk": true,
	"world3_fragment_warden_steampunk": true,
	"world4_fragment_arbiter_digital": true,
	"world4_fragment_curator_digital": true,
	"world4_fragment_tempo_digital": true,
	"world4_fragment_warden_digital": true,
	"world5_fragment_arbiter_abstract": true,
	"world5_fragment_curator_abstract": true,
	"world5_fragment_tempo_abstract": true,
	"world5_fragment_warden_abstract": true,
	# update_item step's transform target — currently a ghost, but the
	# cutscene transforms fool_card → wild_card which means wild_card also
	# needs to exist OR the transform writes a ghost over a ghost.
	"wild_card": true,
}


func _read_text(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func _load_known_items() -> Dictionary:
	var raw = _read_text(ITEMS_JSON_PATH)
	var parsed = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "items.json must parse as Dictionary")
	if parsed is Dictionary:
		return parsed
	return {}


func _collect_cutscene_item_refs() -> Dictionary:
	## Returns {item_id: [list of cutscene_basenames referencing it]}.
	## Walks every JSON file in data/cutscenes/ and extracts item ids
	## from grant_item / give_item / update_item steps. Includes the
	## update_item new_id target so the transform's destination is
	## also checked.
	var refs: Dictionary = {}
	var dir = DirAccess.open(CUTSCENES_DIR)
	if dir == null:
		return refs
	dir.list_dir_begin()
	var name = dir.get_next()
	while name != "":
		if name.ends_with(".json"):
			var path = CUTSCENES_DIR + "/" + name
			var content = _read_text(path)
			var parsed = JSON.parse_string(content)
			if parsed is Dictionary and parsed.has("steps"):
				for step in parsed["steps"]:
					if not step is Dictionary:
						continue
					var t = str(step.get("type", ""))
					if t == "grant_item" or t == "give_item":
						var id = str(step.get("item", ""))
						if id != "":
							refs[id] = refs.get(id, []) + [name]
					elif t == "update_item":
						# Both old item and new_id need to exist
						for key in ["item", "new_id"]:
							var id2 = str(step.get(key, ""))
							if id2 != "":
								refs[id2] = refs.get(id2, []) + [name]
		name = dir.get_next()
	return refs


func test_every_cutscene_granted_item_is_defined_or_listed_as_known_orphan() -> void:
	var refs: Dictionary = _collect_cutscene_item_refs()
	var known_items: Dictionary = _load_known_items()
	assert_gt(refs.size(), 0, "Test setup: should find at least some cutscene item refs")
	assert_gt(known_items.size(), 50, "Test setup: items.json should have many entries")

	var new_orphans: Array = []
	for item_id in refs:
		if known_items.has(item_id):
			continue
		if KNOWN_ORPHAN_ITEMS.has(item_id):
			continue
		new_orphans.append({
			"item": item_id,
			"sources": refs[item_id],
		})

	if not new_orphans.is_empty():
		var msg: String = "NEW orphan cutscene item refs detected (not in items.json AND not in KNOWN_ORPHAN_ITEMS):\n"
		for o in new_orphans:
			msg += "  - %s (referenced in: %s)\n" % [o.item, ", ".join(o.sources)]
		msg += "Either define the item in items.json OR add it to KNOWN_ORPHAN_ITEMS to track the gap."
		fail_test(msg)


func test_known_orphan_list_stays_pruned() -> void:
	## Inverse check: KNOWN_ORPHAN_ITEMS entries that now DO exist in
	## items.json should be removed from the list — keeping them around
	## tells future readers that the gap is still open when it isn't.
	## Forces orphan-list hygiene as items get authored.
	var known_items: Dictionary = _load_known_items()
	var stale_entries: Array = []
	for orphan in KNOWN_ORPHAN_ITEMS:
		if known_items.has(orphan):
			stale_entries.append(orphan)
	if not stale_entries.is_empty():
		fail_test("KNOWN_ORPHAN_ITEMS contains entries that NOW exist in items.json — remove them: %s" % [stale_entries])


func test_runtime_emits_warning_on_unknown_item() -> void:
	# Source pin: _add_item_to_party_leader must consult ItemSystem.get_item
	# and push_warning when the item is unknown. Catches anyone removing
	# the runtime safeguard.
	var text = _read_text("res://src/cutscene/CutsceneDirector.gd")
	var helper_idx = text.find("func _add_item_to_party_leader")
	assert_true(helper_idx > -1, "_add_item_to_party_leader helper must exist")
	var helper_end = text.find("\n\n\nfunc ", helper_idx)
	var body = text.substr(helper_idx, helper_end - helper_idx) if helper_end > -1 else text.substr(helper_idx, 1500)
	assert_true(body.find("ItemSystem.get_item(") > -1,
		"_add_item_to_party_leader must call ItemSystem.get_item to check item existence")
	assert_true(body.find("push_warning") > -1,
		"_add_item_to_party_leader must push_warning when item is unknown — silent ghost-add is what got us into this audit")
