extends GutTest

## Regression tests for PartyChatSystem + event-chat JSON files.
## Protects against three classes of bug:
##  1. REGISTRY entries without matching data/cutscenes/*.json files
##     (menu shows the chat but CutsceneDirector can't find content)
##  2. JSON files shipped without REGISTRY entries
##     (dead data, wasted merge)
##  3. Malformed REGISTRY rows missing required fields
##     (runtime KeyError when the UI reads title/world)


const CUTSCENE_DIR := "res://data/cutscenes"
const REQUIRED_FIELDS := ["title", "world", "unlock"]


func test_every_registry_entry_has_all_required_fields():
	# Lightly couples the menu UI contract to the registry: adding a
	# new row without a title silently breaks the PartyChatMenu label.
	for id in PartyChatSystem.REGISTRY.keys():
		var entry: Dictionary = PartyChatSystem.REGISTRY[id]
		for field in REQUIRED_FIELDS:
			assert_true(
				entry.has(field),
				"REGISTRY[%s] missing required field %s" % [id, field],
			)
		# Types matter too — world should be an int, unlock an Array.
		assert_true(entry["world"] is int, "REGISTRY[%s].world should be int" % id)
		assert_true(entry["unlock"] is Array, "REGISTRY[%s].unlock should be Array" % id)


func test_event_chat_registry_entries_have_json_files():
	# Every event_chat_* id in the registry must have a matching
	# data/cutscenes/<id>.json for CutsceneDirector to load.
	for id in PartyChatSystem.REGISTRY.keys():
		if not id.begins_with("event_chat_"):
			continue
		var path := "%s/%s.json" % [CUTSCENE_DIR, id]
		assert_true(
			FileAccess.file_exists(path),
			"event_chat %s is registered but %s does not exist" % [id, path],
		)


func test_event_chat_json_files_are_valid_cutscene_data():
	# CutsceneDirector expects each file to parse as a Dictionary with
	# a `steps` Array of typed step dicts. This catches a whole class
	# of "story agent shipped a JSON with a typo" bugs at test time
	# instead of on first player trigger.
	for id in PartyChatSystem.REGISTRY.keys():
		if not id.begins_with("event_chat_"):
			continue
		var path := "%s/%s.json" % [CUTSCENE_DIR, id]
		if not FileAccess.file_exists(path):
			continue  # already flagged by the prior test
		var f := FileAccess.open(path, FileAccess.READ)
		assert_not_null(f, "Failed to open %s" % path)
		if f == null:
			continue
		var text := f.get_as_text()
		f.close()
		var parsed = JSON.parse_string(text)
		assert_true(
			parsed is Dictionary,
			"%s must parse as a top-level JSON object" % path,
		)
		if not (parsed is Dictionary):
			continue
		assert_true(parsed.has("steps"), "%s missing required 'steps' array" % path)
		assert_true(parsed["steps"] is Array, "%s 'steps' must be an Array" % path)
		# Every step must be a dict with a 'type'.
		for i in parsed["steps"].size():
			var step = parsed["steps"][i]
			assert_true(
				step is Dictionary,
				"%s steps[%d] must be a Dictionary" % [path, i],
			)
			if step is Dictionary:
				assert_true(
					step.has("type") and step["type"] is String,
					"%s steps[%d] missing 'type' string" % [path, i],
				)


func test_event_chat_json_files_have_registry_entries():
	# Inverse check — flag orphaned JSON files that ship without a
	# registry entry (they'd never surface in the menu).
	var dir := DirAccess.open(CUTSCENE_DIR)
	if dir == null:
		pending("Cutscene directory not accessible")
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.begins_with("event_chat_") and fname.ends_with(".json"):
			var id := fname.trim_suffix(".json")
			assert_true(
				PartyChatSystem.REGISTRY.has(id),
				"data/cutscenes/%s exists but is not in PartyChatSystem.REGISTRY" % fname,
			)
		fname = dir.get_next()
	dir.list_dir_end()


func test_chat_unavailable_until_unlock_flags_set():
	# Regression for the is_available() logic: a chat should NOT be
	# available when the unlock flag is missing.
	var override := Node.new()
	override.set_script(null)
	override.set("game_constants", {})
	add_child_autofree(override)

	PartyChatSystem.game_state_override = override
	# Pick any event chat to probe — first_party_wipe is stable.
	assert_false(
		PartyChatSystem.is_available("event_chat_first_party_wipe"),
		"event_chat_first_party_wipe should be locked with empty flags",
	)

	# Setting the flag should flip it available.
	override.set("game_constants", {"event_flag_first_party_wipe": true})
	assert_true(
		PartyChatSystem.is_available("event_chat_first_party_wipe"),
		"event_chat_first_party_wipe should unlock when its flag is set",
	)

	# Marking viewed should hide it again.
	PartyChatSystem.game_state_override.game_constants["party_chat_viewed_event_chat_first_party_wipe"] = true
	assert_false(
		PartyChatSystem.is_available("event_chat_first_party_wipe"),
		"event_chat_first_party_wipe should hide after mark_viewed",
	)

	# Clean up so later tests see a fresh registry view.
	PartyChatSystem.game_state_override = null
