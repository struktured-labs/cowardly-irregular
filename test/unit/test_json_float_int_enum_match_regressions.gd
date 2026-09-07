extends GutTest

## tick 139 regression suite: a JSON-loaded numeric value is a
## FLOAT in GDScript, but `match` against int enum literals is
## type-strict — the arms never fire. This silent-failure class
## hit:
##   - ItemsMenu._get_item_color (fixed in tick 138)
##   - ItemsMenu._get_target_type_text (fixed here)
##   - JobMenu's job-row type tag (fixed here)
##
## All three rendered with the default-fallback path for every
## JSON-loaded entry because match never matched the enum int.
##
## This test sweeps all known int-enum-match sites for the
## coercion (`int(...)` at the match input), and pins coverage of
## every enum value present in the underlying data files.

const ITEMS_MENU := "res://src/ui/ItemsMenu.gd"
const JOB_MENU := "res://src/ui/JobMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _fn_body(path: String, name: String) -> String:
	var src := _read(path)
	var idx: int = src.find("func " + name)
	assert_gt(idx, -1, "%s must exist in %s" % [name, path])
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


# ── ItemsMenu._get_target_type_text ──────────────────────────────────────

func test_target_type_text_coerces_int() -> void:
	# Pin: the match input must be `int(target_type)` not raw target_type.
	# Without coercion, float-from-JSON would never match int arms.
	var body := _fn_body(ITEMS_MENU, "_get_target_type_text")
	assert_true(body.contains("var t: int = int(target_type)"),
		"_get_target_type_text must coerce target_type to int before match")
	assert_true(body.contains("match t:"),
		"match must use the coerced variable, not the raw float")


func test_target_type_text_handles_all_five_enum_values() -> void:
	# Pin: every TargetType enum value has an explicit branch.
	# Pre-tick-139 SINGLE_ENEMY and ALL_ENEMIES had no branches at
	# all — offensive items (bombs etc) read "Target: Unknown" even
	# after the coercion fix.
	var body := _fn_body(ITEMS_MENU, "_get_target_type_text")
	for tt in ["SINGLE_ALLY", "ALL_ALLIES", "SINGLE_ENEMY", "ALL_ENEMIES", "SELF"]:
		var qualified: String = "ItemSystem.TargetType." + tt
		assert_true(body.contains(qualified),
			"_get_target_type_text must explicitly mention '%s'" % qualified)


func test_target_type_text_returns_correct_string_for_each_enum() -> void:
	# Runtime cross-check: instantiate, call with each enum value,
	# verify the returned text. Pre-fix every call returned "Unknown"
	# for JSON-loaded items.
	var script_class = load(ITEMS_MENU)
	var inst: Node = script_class.new()
	add_child_autofree(inst)
	# Use float inputs (mimic JSON.parse).
	assert_eq(inst._get_target_type_text(0.0), "Single Ally",
		"target_type 0.0 must render 'Single Ally' (catches the float/int regression)")
	assert_eq(inst._get_target_type_text(1.0), "All Allies",
		"target_type 1.0 must render 'All Allies'")
	assert_eq(inst._get_target_type_text(2.0), "Single Enemy",
		"target_type 2.0 must render 'Single Enemy' (pre-tick-139 said 'Unknown')")
	assert_eq(inst._get_target_type_text(3.0), "All Enemies",
		"target_type 3.0 must render 'All Enemies' (pre-tick-139 said 'Unknown')")
	assert_eq(inst._get_target_type_text(4.0), "Self",
		"target_type 4.0 must render 'Self'")


func test_target_type_text_unknown_still_falls_back() -> void:
	var script_class = load(ITEMS_MENU)
	var inst: Node = script_class.new()
	add_child_autofree(inst)
	assert_eq(inst._get_target_type_text(99), "Unknown",
		"unknown target_type still falls back to 'Unknown'")


func test_target_type_runtime_check_via_real_item_data() -> void:
	# Cross-check against items.json — bomb_fragment has
	# target_type=2 (SINGLE_ENEMY). Pre-tick-139 it surfaced as
	# "Unknown". Pin the canonical resolution against real data.
	var item_sys = get_node_or_null("/root/ItemSystem")
	if item_sys == null or not item_sys.has_method("get_item"):
		pending("ItemSystem not available")
		return
	var data: Dictionary = item_sys.get_item("bomb_fragment")
	if data.is_empty():
		pending("bomb_fragment not in items.json — cannot cross-check")
		return
	var script_class = load(ITEMS_MENU)
	var inst: Node = script_class.new()
	add_child_autofree(inst)
	# Pass the raw value from JSON (likely a float).
	var text: String = inst._get_target_type_text(data.get("target_type", 0))
	assert_eq(text, "Single Enemy",
		"bomb_fragment must render 'Single Enemy' — was 'Unknown' before tick 139's coercion + enum-coverage fix")


# ── JobMenu job-row type tag ─────────────────────────────────────────────

func test_job_row_type_tag_coerces_int() -> void:
	# JobMenu _create_job_row's job_type match must coerce float→int.
	var src := _read(JOB_MENU)
	# Find the _create_job_row body.
	var idx: int = src.find("func _create_job_row")
	assert_gt(idx, -1, "_create_job_row must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	# Pin: int() coercion in the job_type assignment.
	assert_true(body.contains("var job_type: int = int(job_data.get(\"type\", 0))"),
		"_create_job_row must coerce job_type to int — without it, advanced (1) and meta (2) jobs silently rendered with no type tag")
	# Negative pin: the raw (untyped) get must NOT be present without coercion.
	assert_false(body.contains("var job_type = job_data.get(\"type\", 0)\n"),
		"raw uncoerced job_type assignment must be gone")


func test_job_row_type_tag_match_arms_unchanged() -> void:
	# Sanity: the match arms still produce the right tag for each
	# type. Don't regress the tag strings.
	var src := _read(JOB_MENU)
	var idx: int = src.find("func _create_job_row")
	assert_gt(idx, -1, "_create_job_row must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("type_tag = \" [ADV]\""),
		"advanced job tag must remain ' [ADV]'")
	assert_true(body.contains("type_tag = \" [META]\""),
		"meta job tag must remain ' [META]'")
	# Starter jobs (type 0) get no tag — pin no third arm.
	# (No specific assertion needed; absence is structural.)
