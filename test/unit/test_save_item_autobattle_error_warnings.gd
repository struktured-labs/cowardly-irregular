extends GutTest

## tick 181 regression: extends tick 180's print→push_warning
## sweep to SaveSystem / ItemSystem / AutobattleSystem error
## paths. Seven sites converted total.
##
## Highest player-visibility class fixed: SaveSystem load failures
## silently returned {} which the title-screen CONTINUE button
## treated as "no save" — player saw their save disappear with
## zero hint why. push_warning surfaces the underlying file/parse
## error to dev tooling.

const SAVE_SYSTEM := "res://src/save/SaveSystem.gd"
const ITEM_SYSTEM := "res://src/items/ItemSystem.gd"
const AUTOBATTLE_SYSTEM := "res://src/autobattle/AutobattleSystem.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── SaveSystem — 4 sites ────────────────────────────────────────────────

func test_save_write_failure_warns_with_error_code() -> void:
	var src := _read(SAVE_SYSTEM)
	assert_true(src.contains("push_warning(\"[SaveSystem] _write_save_file: could not open"),
		"_write_save_file must push_warning on file-open failure")
	# Pin: includes FileAccess error code for diagnosis.
	assert_true(src.contains("FileAccess.get_open_error()"),
		"write failure warning must include error code for diagnosis")
	# Negative: old print() error gone.
	assert_false(src.contains("print(\"Error: Could not open save file for writing"),
		"old print() error must be gone")


func test_save_read_failure_warns_with_error_code() -> void:
	var src := _read(SAVE_SYSTEM)
	assert_true(src.contains("push_warning(\"[SaveSystem] _read_save_file: could not open"),
		"_read_save_file must push_warning on file-open failure")
	assert_false(src.contains("print(\"Error: Could not open save file for reading"),
		"old print() error must be gone")


func test_save_parse_failure_warns_with_json_error() -> void:
	var src := _read(SAVE_SYSTEM)
	assert_true(src.contains("push_warning(\"[SaveSystem] _read_save_file: failed to parse"),
		"JSON parse failure must push_warning with json.get_error_message()")
	assert_true(src.contains("json.get_error_message()"),
		"parse failure warning must include json.get_error_message()")
	assert_false(src.contains("print(\"Error: Failed to parse save file JSON"),
		"old print() error must be gone")


func test_save_root_type_failure_warns() -> void:
	var src := _read(SAVE_SYSTEM)
	assert_true(src.contains("push_warning(\"[SaveSystem] _read_save_file: '%s' parsed but root is not a Dictionary"),
		"root-type mismatch must push_warning with the type")
	assert_false(src.contains("print(\"Error: Save file data is not a valid dictionary\")"),
		"old print() error must be gone")


# ── ItemSystem — 2 sites ────────────────────────────────────────────────

func test_use_item_unknown_id_warns() -> void:
	var src := _read(ITEM_SYSTEM)
	assert_true(src.contains("push_warning(\"[ItemSystem] use_item: item_id '%s' not found"),
		"use_item must push_warning on unknown item_id")
	assert_false(src.contains("print(\"Error: Item '%s' not found"),
		"old print() error must be gone")


func test_use_item_no_effects_warns() -> void:
	var src := _read(ITEM_SYSTEM)
	assert_true(src.contains("push_warning(\"[ItemSystem] use_item: item '%s' has no 'effects' field"),
		"use_item must push_warning on missing 'effects' field — authoring error in items.json")
	# Pin: warning explains it's an authoring error.
	assert_true(src.contains("authoring error in items.json"),
		"warning must reference items.json as the authoring source")
	assert_false(src.contains("print(\"Error: Item has no effects\")"),
		"old print() error must be gone")


# ── AutobattleSystem — 1 site ──────────────────────────────────────────

func test_autobattle_parse_failure_warns() -> void:
	var src := _read(AUTOBATTLE_SYSTEM)
	assert_true(src.contains("push_warning(\"[AutobattleSystem] failed to parse autobattle scripts JSON"),
		"autobattle parse failure must push_warning")
	assert_true(src.contains("falling back to defaults"),
		"warning must mention defaults fallback so player knows what happened")
	assert_false(src.contains("print(\"Error parsing autobattle scripts\")"),
		"old print() error must be gone")


# ── Cross-pin: tick 180 sites still warning ────────────────────────────

func test_tick_180_warnings_still_in_place() -> void:
	# Non-regression: don't accidentally lose tick 180's work.
	var js := _read("res://src/jobs/JobSystem.gd")
	assert_true(js.contains("push_warning(\"[JobSystem] assign_job"),
		"tick 180 JobSystem warning preserved")
	var es := _read("res://src/jobs/EquipmentSystem.gd")
	assert_true(es.contains("push_warning(\"[EquipmentSystem] equip_weapon"),
		"tick 180 EquipmentSystem warning preserved")
	var ps := _read("res://src/jobs/PassiveSystem.gd")
	assert_true(ps.contains("push_warning(\"[PassiveSystem] equip_passive"),
		"tick 180 PassiveSystem warning preserved")
