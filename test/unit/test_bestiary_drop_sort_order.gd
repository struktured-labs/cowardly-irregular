extends GutTest

## tick 195: BestiaryMenu._format_drops now explicitly sorts the
## drop list by chance-DESC with name-ASC tiebreak. Pre-fix the
## display walked file order — drops happened to be roughly
## sorted in monsters.json but it wasn't enforced. A reorder in
## the data file would shuffle the bestiary UI.
##
## Why chance-DESC: matches the autobattle-planning mental model
## ("most likely outcome first"). Tied chances sort alphabetically
## by display name for cross-save / cross-player determinism.
##
## Why not just rely on json order: Scriptweaver custom monsters,
## hot-reload during testing, story-team edits, and merge churn
## all conspire to randomize file order over time. An explicit
## sort means the bestiary stays stable regardless.

const BESTIARY_MENU := "res://src/ui/BestiaryMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _fmt_body() -> String:
	var src := _read(BESTIARY_MENU)
	var fn_idx: int = src.find("func _format_drops")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	return src.substr(fn_idx, next_fn - fn_idx) if next_fn > -1 else src.substr(fn_idx)


# ── Explicit sort exists ──────────────────────────────────────────────

func test_sort_custom_lambda_present() -> void:
	var body := _fmt_body()
	assert_true(body.contains("rows.sort_custom(func(a, b):"),
		"_format_drops must call sort_custom on the row collection")


func test_chance_desc_primary_key() -> void:
	# Pin: primary sort by chance, DESCENDING (a.chance > b.chance).
	var body := _fmt_body()
	assert_true(body.contains("if a.chance != b.chance:\n\t\t\treturn a.chance > b.chance"),
		"primary sort key must be chance-DESC")


func test_name_asc_tiebreak() -> void:
	# Pin: tied chances → tiebreak by display name ascending.
	var body := _fmt_body()
	assert_true(body.contains("return a.name < b.name"),
		"tiebreak must be name-ASC for cross-save determinism")


# ── Pipeline structure: collect → sort → render ────────────────────────

func test_rows_collected_before_sort() -> void:
	# Pin: rows are gathered into a list before sorting (separation
	# of data-prep from rendering keeps the helper unit-testable).
	var body := _fmt_body()
	var rows_init_idx: int = body.find("var rows: Array = []")
	var sort_idx: int = body.find("rows.sort_custom")
	assert_gt(rows_init_idx, -1, "rows array must be initialized")
	assert_gt(sort_idx, -1, "sort_custom must be called")
	assert_lt(rows_init_idx, sort_idx, "rows must be populated before sort")


func test_rendering_happens_after_sort() -> void:
	# Pin: parts list (the final rendered fragments) is built from
	# the SORTED rows, not the raw drops array.
	var body := _fmt_body()
	var sort_idx: int = body.find("rows.sort_custom")
	var parts_loop_idx: int = body.find("for r in rows:")
	var append_idx: int = body.find("parts.append(\"%s %d%%\" % [r.name, pct])")
	assert_gt(sort_idx, -1)
	assert_gt(parts_loop_idx, -1, "must iterate sorted rows when rendering")
	assert_gt(append_idx, -1, "must format each row into the parts list")
	assert_lt(sort_idx, parts_loop_idx, "rendering loop comes after sort")


func test_row_shape_includes_name_for_tiebreak() -> void:
	# Pin: row Dictionary stores resolved name (not just id) so the
	# sort can use the DISPLAY name as the tiebreak, not the raw id.
	# A monster's drop entry could be "rare_gem" — display name
	# might be "Rare Gem" — sorting by display matches what the
	# user reads.
	var body := _fmt_body()
	assert_true(body.contains("rows.append({\"item\": item, \"chance\": chance, \"name\": _resolve_item_display_name(item)})"),
		"row must include resolved name field for tiebreak")


# ── Filtering preserved ───────────────────────────────────────────────

func test_empty_item_skip_preserved() -> void:
	# Existing safety: drops entries with empty "item" field are skipped.
	var body := _fmt_body()
	assert_true(body.contains("if item == \"\":\n\t\t\tcontinue"),
		"empty-item skip preserved (pre-existing safety)")


func test_non_dict_skip_preserved() -> void:
	# Existing safety: non-Dictionary entries skipped (defensive
	# against malformed JSON).
	var body := _fmt_body()
	assert_true(body.contains("if not d is Dictionary:\n\t\t\tcontinue"),
		"non-Dictionary skip preserved")


# ── Output shape preserved ────────────────────────────────────────────

func test_output_format_unchanged() -> void:
	# Pin: "Drops: A 50%, B 15%" format unchanged. Only the order
	# changes, not the rendering shape.
	var body := _fmt_body()
	assert_true(body.contains("\"Drops: %s\" % (\", \".join(parts) if parts.size() > 0 else \"—\")"),
		"display format 'Drops: A, B, C' preserved (em-dash for empty)")
	assert_true(body.contains("\"%s %d%%\" % [r.name, pct]"),
		"per-drop format 'Name %d%%' preserved")


func test_pct_calculation_preserved() -> void:
	# Pin: chance (0.0-1.0) → integer percent (0-100) via round.
	var body := _fmt_body()
	assert_true(body.contains("var pct: int = int(round(r.chance * 100.0))"),
		"chance-to-percent calculation preserved (rounded)")


# ── One-shot reward still appended ────────────────────────────────────

func test_one_shot_reward_preserved() -> void:
	# Pin: rare bonus (one_shot_reward) still appended as the
	# trailing "(One-shot: <item>)" segment, distinct from the
	# percentage drops.
	var body := _fmt_body()
	assert_true(body.contains("if one_shot != null and str(one_shot) != \"\":"),
		"one_shot guard preserved")
	assert_true(body.contains("(One-shot: %s)"),
		"one-shot trailing format preserved")


# ── Cross-pins to prior bestiary ticks ────────────────────────────────

func test_tick_135_resolver_still_used() -> void:
	# Tick 135's ItemNameResolver-wrapping helper still in place.
	var body := _fmt_body()
	assert_true(body.contains("_resolve_item_display_name(item)"),
		"tick 135 _resolve_item_display_name preserved as the name resolver")


func test_tick_194_silhouette_preserved() -> void:
	# Non-regression: don't lose tick 194's silhouette in the sort change.
	var src := _read(BESTIARY_MENU)
	assert_true(src.contains("_detail_sprite.modulate = Color.WHITE if defeated else SILHOUETTE_COLOR"),
		"tick 194 silhouette modulate preserved")
