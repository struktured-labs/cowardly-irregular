extends GutTest

## tick 415: SaveSystem._get_party_summary drops the dead
## "customization" field.
##
## Pre-fix the field held the live CharacterCustomization
## RefCounted reference from the player_party member dict. JSON
## stringification turns RefCounted instances into null, so the
## field landed in saves as `"customization": null` — pure bloat.
## SaveScreen reads name/job_id/hp/max_hp only; nothing ever
## consumed customization from save metadata.
##
## Actual customization persistence happens through
## GameLoop._save_customizations writing to user://save_data.json
## (the global customization file). No consumer is impacted.

const SAVE_SYSTEM_PATH := "res://src/save/SaveSystem.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_field_removed() -> void:
	var src := _read(SAVE_SYSTEM_PATH)
	var fn_idx: int = src.find("func _get_party_summary")
	assert_gt(fn_idx, -1, "_get_party_summary must exist")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# The literal field write must be gone.
	assert_false(body.contains("\"customization\": member.get"),
		"customization field must be removed from _get_party_summary's summary entries")


func test_remaining_keys_intact() -> void:
	# Regression guard: don't accidentally remove other summary keys.
	var src := _read(SAVE_SYSTEM_PATH)
	var fn_idx: int = src.find("func _get_party_summary")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	for key in ["name", "level", "job", "job_id", "secondary_job_id", "hp", "max_hp"]:
		assert_true(body.contains("\"%s\":" % key),
			"_get_party_summary must still write the %s key" % key)
