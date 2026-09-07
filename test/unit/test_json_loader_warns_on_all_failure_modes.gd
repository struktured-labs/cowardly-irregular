extends GutTest

## tick 165 regression: every JSON-data loader on the
## boot path (JobSystem, EquipmentSystem, PassiveSystem) must
## push_warning on EACH failure mode it tolerates:
##
##   - file not found
##   - FileAccess.open returned null
##   - JSON.parse error
##   - root is not the expected type (Dictionary)
##
## Pre-fix many loaders fell through silently on the open-fail and
## root-type-mismatch paths. Silent failure surfaces as missing
## data downstream (no aliases → save migration broken; no
## passives → equip menu empty) without any console trace.
##
## Symptoms that motivated this audit: an old save with
## white_mage / black_mage / thief job IDs would silently NOT
## migrate if job_aliases.json failed to parse — the player would
## see jobs reset to fighter defaults with zero indication of
## the cause.

const JOB_SYSTEM := "res://src/jobs/JobSystem.gd"
const EQUIPMENT_SYSTEM := "res://src/jobs/EquipmentSystem.gd"
const PASSIVE_SYSTEM := "res://src/jobs/PassiveSystem.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── JobSystem._load_job_aliases ─────────────────────────────────────────

func test_job_aliases_warns_on_file_missing() -> void:
	var src := _read(JOB_SYSTEM)
	# Find _load_job_aliases body.
	var idx: int = src.find("func _load_job_aliases")
	assert_gt(idx, -1, "_load_job_aliases must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	assert_true(body.contains("push_warning(\"[JobSystem] job_aliases.json not found"),
		"_load_job_aliases must push_warning when the file is missing — pre-fix this was a silent return")


func test_job_aliases_warns_on_file_open_fail() -> void:
	var src := _read(JOB_SYSTEM)
	var idx: int = src.find("func _load_job_aliases")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	assert_true(body.contains("push_warning(\"[JobSystem] job_aliases.json exists but FileAccess.open failed"),
		"_load_job_aliases must push_warning when FileAccess.open returns null")


func test_job_aliases_warns_on_parse_error() -> void:
	var src := _read(JOB_SYSTEM)
	var idx: int = src.find("func _load_job_aliases")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	assert_true(body.contains("push_warning(\"[JobSystem] job_aliases.json parse error:"),
		"_load_job_aliases must push_warning on JSON parse failure")


func test_job_aliases_warns_on_non_dictionary_root() -> void:
	var src := _read(JOB_SYSTEM)
	var idx: int = src.find("func _load_job_aliases")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	assert_true(body.contains("push_warning(\"[JobSystem] job_aliases.json parsed but root is not a Dictionary"),
		"_load_job_aliases must push_warning when root type is unexpected")


# ── EquipmentSystem._load_equipment_data ────────────────────────────────

func test_equipment_warns_on_file_open_fail() -> void:
	var src := _read(EQUIPMENT_SYSTEM)
	# Pre-fix the file-open-fail branch fell through to defaults
	# silently. Now must warn.
	assert_true(src.contains("push_warning(\"[EquipmentSystem] equipment.json exists but FileAccess.open failed"),
		"EquipmentSystem load must push_warning on FileAccess.open failure")


# ── PassiveSystem._load_passive_data ────────────────────────────────────

func test_passive_warns_on_file_open_fail() -> void:
	var src := _read(PASSIVE_SYSTEM)
	assert_true(src.contains("push_warning(\"[PassiveSystem] passives.json exists but FileAccess.open failed"),
		"PassiveSystem load must push_warning on FileAccess.open failure")


func test_passive_warns_on_non_dictionary_root() -> void:
	# Pre-fix PassiveSystem had NO Dictionary check at all — it
	# assigned json.data directly. An Array root would silently
	# break get_passive() downstream.
	var src := _read(PASSIVE_SYSTEM)
	assert_true(src.contains("push_warning(\"[PassiveSystem] passives.json parsed but root is not a Dictionary"),
		"PassiveSystem load must push_warning when root is not Dictionary (was missing this check pre-tick-165)")
	# Also pin: the Dictionary check exists in the code path.
	assert_true(src.contains("if not (json.data is Dictionary):"),
		"PassiveSystem must check root type before assigning to passives")


# ── Non-regression: existing warnings still present ─────────────────────

func test_equipment_existing_parse_error_warning_preserved() -> void:
	# Don't accidentally drop the pre-existing parse-error warning
	# while adding the file-open one.
	var src := _read(EQUIPMENT_SYSTEM)
	assert_true(src.contains("push_warning(\"[EquipmentSystem] equipment.json parse error:"),
		"existing parse-error warning must remain")


func test_equipment_existing_root_check_warning_preserved() -> void:
	var src := _read(EQUIPMENT_SYSTEM)
	assert_true(src.contains("push_warning(\"[EquipmentSystem] equipment.json parsed but root is not a Dictionary"),
		"existing root-check warning must remain")


func test_passive_existing_parse_error_warning_preserved() -> void:
	var src := _read(PASSIVE_SYSTEM)
	assert_true(src.contains("push_warning(\"[PassiveSystem] passives.json parse error:"),
		"existing parse-error warning must remain")


# ── Runtime sanity: loaders still produce non-empty data ────────────────

func test_runtime_loaders_populated_after_normal_boot() -> void:
	# Cross-check: with normal data files present, the loaders
	# still populate their tables. The tick 165 changes should be
	# purely additive (warnings + early-return on failure paths)
	# and not break the happy path.
	var js = Engine.get_main_loop().root.get_node_or_null("JobSystem")
	if js != null:
		assert_gt(int(js.jobs.size()), 0,
			"JobSystem.jobs must be populated after normal boot")
	var es = Engine.get_main_loop().root.get_node_or_null("EquipmentSystem")
	if es != null:
		assert_gt(int(es.weapons.size()), 0,
			"EquipmentSystem.weapons must be populated after normal boot")
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps != null:
		assert_gt(int(ps.passives.size()), 0,
			"PassiveSystem.passives must be populated after normal boot")
