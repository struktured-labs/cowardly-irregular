extends GutTest

## Regression coverage: every picker-exposed condition/action id MUST have a friendly
## formatter case in both AutogrindUI._format_condition AND AutogrindGridEditor._format_condition
## (same for actions). Pre-fix, 9 legitimate ids fell through to `_ : return type` and
## displayed as raw snake_case in struktured's autogrind editor — this is what "half-baked
## snake case rules" looked like (playtest report 2026-07-14).
##
## The picker/evaluator sync guard from task-#2 kept condition types authored right;
## THIS guard keeps them DISPLAYED right.

const AUTOGRIND_UI_PATH := "res://src/ui/autogrind/AutogrindUI.gd"
const GRID_EDITOR_PATH := "res://src/ui/autogrind/AutogrindGridEditor.gd"


func _extract_ids(src: String, marker_prefix: String) -> Array:
	## Pulls "id" values from an array-of-dict const block starting with marker_prefix
	## (e.g. "const CONDITION_TYPES = [").
	var start := src.find(marker_prefix)
	if start < 0:
		return []
	# Find the closing ] of that array
	var depth := 0
	var i := start + marker_prefix.length()
	var end := -1
	while i < src.length():
		var c := src[i]
		if c == "[":
			depth += 1
		elif c == "]":
			if depth == 0:
				end = i
				break
			depth -= 1
		i += 1
	if end < 0:
		return []
	var block := src.substr(start, end - start)
	var ids: Array = []
	var idx := 0
	while true:
		var q := block.find('"id": "', idx)
		if q < 0:
			break
		q += 7  # past `"id": "`
		var q_end := block.find('"', q)
		ids.append(block.substr(q, q_end - q))
		idx = q_end + 1
	return ids


func _handled_types_in_func(src: String, fn_name: String) -> Array:
	## Returns the list of match-arm literal strings in the named function
	## (i.e. every `"literal":` inside the func body).
	var start := src.find("func %s" % fn_name)
	if start < 0:
		return []
	var end := src.find("\nfunc ", start + 10)
	if end < 0:
		end = src.length()
	var body := src.substr(start, end - start)
	var out: Array = []
	var lines := body.split("\n")
	for line in lines:
		var stripped: String = line.strip_edges()
		if stripped.begins_with('"') and stripped.ends_with('":'):
			var literal := stripped.substr(1, stripped.length() - 3)
			# Skip the "_" wildcard and comparison-op literals — only match id-shaped strings
			if literal != "_" and not literal.begins_with("<") and not literal.begins_with(">") and not literal.begins_with("=") and not literal.begins_with("!"):
				out.append(literal)
	return out


func test_autogrind_ui_format_condition_covers_every_picker_id() -> void:
	var src: String = load(AUTOGRIND_UI_PATH).source_code
	var picker_ids := _extract_ids(src, "const CONDITION_TYPES = [")
	var handled := _handled_types_in_func(src, "_format_condition")
	assert_gt(picker_ids.size(), 0, "must find CONDITION_TYPES const")
	var missing: Array = []
	for id in picker_ids:
		if not (id in handled):
			missing.append(id)
	assert_eq(missing.size(), 0,
		"AutogrindUI._format_condition is missing friendly cases for picker-exposed ids — they'll render as raw snake_case in the editor: %s" % [missing])


func test_autogrind_ui_format_action_covers_every_picker_id() -> void:
	var src: String = load(AUTOGRIND_UI_PATH).source_code
	var picker_ids := _extract_ids(src, "const ACTION_TYPES = [")
	var handled := _handled_types_in_func(src, "_format_action")
	assert_gt(picker_ids.size(), 0, "must find ACTION_TYPES const")
	var missing: Array = []
	for id in picker_ids:
		if not (id in handled):
			missing.append(id)
	assert_eq(missing.size(), 0,
		"AutogrindUI._format_action is missing friendly cases for picker-exposed ids: %s" % [missing])


func test_grid_editor_format_condition_covers_same_ids_as_autogrind_ui() -> void:
	## The two pickers share the same authored id namespace — GridEditor's formatter
	## must cover everything AutogrindUI's picker exposes (drift-guard, same shape
	## as the picker-key-sync test in test_autogrind.gd).
	var ui_src: String = load(AUTOGRIND_UI_PATH).source_code
	var picker_ids := _extract_ids(ui_src, "const CONDITION_TYPES = [")
	var editor_src: String = load(GRID_EDITOR_PATH).source_code
	var handled := _handled_types_in_func(editor_src, "_format_condition")
	var missing: Array = []
	for id in picker_ids:
		if not (id in handled):
			missing.append(id)
	assert_eq(missing.size(), 0,
		"AutogrindGridEditor._format_condition is missing friendly cases (players see raw snake_case): %s" % [missing])


func test_grid_editor_format_action_covers_same_ids_as_autogrind_ui() -> void:
	var ui_src: String = load(AUTOGRIND_UI_PATH).source_code
	var picker_ids := _extract_ids(ui_src, "const ACTION_TYPES = [")
	var editor_src: String = load(GRID_EDITOR_PATH).source_code
	var handled := _handled_types_in_func(editor_src, "_format_action")
	var missing: Array = []
	for id in picker_ids:
		if not (id in handled):
			missing.append(id)
	assert_eq(missing.size(), 0,
		"AutogrindGridEditor._format_action is missing friendly cases: %s" % [missing])
