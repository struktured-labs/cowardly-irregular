extends GutTest

## Source-lint regression: bans Engine.has_singleton("<autoload_name>") calls.
##
## In Godot 4, Engine.has_singleton() ONLY matches native engine singletons
## (Time, OS, Input, RenderingServer, etc.).  Autoloads registered via the
## project.godot [autoload] block are NOT engine singletons — they are nodes
## attached to the SceneTree root.  Every Engine.has_singleton("AutoloadName")
## call therefore returns FALSE silently, taking the failure branch even when
## the autoload is fully loaded and operational.
##
## This was the root cause of bug #2 in the LLM-integration audit: every gate
## guarding LLMService / GameState / SoundManager / EquipmentSystem / etc.
## bypassed the autoload entirely, so dynamic conversations could never reach
## the LLM, EventLog timestamps were always zero, and DialogueChoiceMenu's SFX
## never played.
##
## CORRECT pattern: look up autoloads via the scene tree root,
##     var svc: Node = get_node_or_null("/root/AutoloadName")
## or in static contexts,
##     var tree := Engine.get_main_loop() as SceneTree
##     var svc: Node = tree.root.get_node_or_null("AutoloadName") if tree else null
##
## The walker scans res://src and res://test recursively.  It skips comment
## lines (anything whose first non-whitespace character is "#") so the
## documented teaching comments left at fixed sites do not re-trigger the
## lint.  Each entry in ALLOWED_OCCURRENCES is a file path → list of dicts
## with {needle, reason} for any literal call we choose to keep — currently
## empty for src/, but populated for legacy test fixtures whose
## has_singleton guards were always-false in production yet still served a
## structural role in headless tests.

const RES_ROOTS: Array[String] = [
	"res://src",
	"res://test",
]

## Allowlist: filename (basename) → Array of allowed { needle, reason } dicts.
## Each call-site must satisfy at least one allowed pattern to escape the lint.
## Keep this list TINY — every entry is technical debt.
const ALLOWED_OCCURRENCES: Dictionary = {
	# Legacy test fixtures predating the Wave A audit.  These tests use
	# Engine.has_singleton as a "skip if the singleton happens to be present"
	# guard — broken in production code, but harmless inside GUT because the
	# branch they protect is the LLM-on path that has no headless coverage.
	# Fixing them is tracked separately from Wave A and out of scope here.
	# 2026-09-16: the last two entries retired. Both calls were gone from code —
	# test_llm_infra.gd keeps the needle only inside a ## line, test_dynamic_conversation.gd
	# has none at all — so each was exempting a call that could return unnoticed. Found by
	# the arm below rather than by hand, which is the difference from tick 261.
	# Tick 261: test_llm_integration.gd no longer needs the allowlist
	# entry — all 8 dead gates were replaced with the
	# _llm_actually_reachable() helper (proper autoload + is_available
	# probe). cowir-ai sharpening 2 in msg 1884.
}

const VIOLATION_NEEDLE: String = "Engine.has_singleton("

## Files to skip outright (basename match).  The lint test itself trips on its
## own self-references — both inside string literals (allowlist needles, error
## messages) and in this very explanatory line.
const SKIP_FILES: Array[String] = [
	"test_no_engine_has_singleton.gd",
]


func test_no_engine_has_singleton_in_project_code() -> void:
	var violations: Array = []
	for root in RES_ROOTS:
		_walk(root, violations)

	if violations.is_empty():
		assert_true(true, "No banned Engine.has_singleton() calls found.")
		return

	var lines: Array[String] = []
	lines.append("Found %d Engine.has_singleton() call(s) outside the allowlist:" % violations.size())
	for v in violations:
		lines.append("  %s:%d  %s" % [v["path"], v["line_no"], v["line_text"].strip_edges()])
	lines.append("")
	lines.append("FIX: Replace each call with the SceneTree-root autoload lookup pattern:")
	lines.append("    var svc: Node = get_node_or_null(\"/root/AutoloadName\")")
	lines.append("(Engine.has_singleton matches NATIVE singletons only — not autoloads.)")
	lines.append("If the call is intentional, add it to ALLOWED_OCCURRENCES with a stated reason.")

	fail_test("\n".join(lines))


func _walk(path: String, violations: Array) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue
		var full: String = "%s/%s" % [path, entry]
		if dir.current_is_dir():
			_walk(full, violations)
		elif entry.ends_with(".gd") and not (entry in SKIP_FILES):
			_scan_file(full, violations)
		entry = dir.get_next()
	dir.list_dir_end()


func _scan_file(path: String, violations: Array) -> void:
	var content: String = FileAccess.get_file_as_string(path)
	if content == "" or not content.contains(VIOLATION_NEEDLE):
		return

	# Compute basename once for allowlist lookup.
	var basename: String = path.get_file()
	var allowed_list: Array = ALLOWED_OCCURRENCES.get(basename, [])

	## strip_comments is LINE-PRESERVING, which this arm requires: it reports path:line_no, so the
	## index must still address the real file. code_of would also drop docstrings and shift it.
	## The private `find("#")` this replaces cut on a hash inside a string literal, hiding any
	## violation after it — an assert-EMPTY scan goes silent on that rather than red.
	var lines_split: PackedStringArray = content.split("\n")
	var code_split: PackedStringArray = GdSource.strip_comments(content).split("\n")
	for i in lines_split.size():
		var raw_line: String = lines_split[i]
		if i >= code_split.size() or not code_split[i].contains(VIOLATION_NEEDLE):
			continue

		# Check allowlist.
		if _is_allowed(code_split[i], allowed_list):
			continue

		violations.append({
			"path":      path,
			"line_no":   i + 1,
			"line_text": raw_line,
		})


func _is_allowed(line: String, allowed_list: Array) -> bool:
	for entry in allowed_list:
		if not (entry is Dictionary):
			continue
		var needle: String = str(entry.get("needle", ""))
		if needle != "" and line.contains(needle):
			return true
	return false


func test_an_allowlist_entry_still_names_a_live_occurrence() -> void:
	## A licence that outlives its fact: an entry here exempts a call that no longer
	## exists, so re-introducing that call is silently permitted. Measured 2026-09-16 —
	## BOTH llm-lane entries were stale, and the tick-261 note above records that the
	## only previous retirement was spotted by hand. Both triggers: the file goes, or
	## the call goes.
	## NO floor on the allowlist SIZE: empty is the goal state, not a vacuous one. The
	## corpus floor below is the one that matters — it is what would read as "clean".
	var found: Dictionary = {}
	for root in RES_ROOTS:
		_index_by_basename(root, found)
	assert_gt(found.size(), 100,
		"FLOOR: the walk must find the corpus, or every entry below reads as merely absent")
	var stale: Array = []
	for basename in ALLOWED_OCCURRENCES:
		var b: String = str(basename)
		if not found.has(b):
			stale.append("%s: the file it names is gone" % b)
			continue
		var content: String = FileAccess.get_file_as_string(str(found[b]))
		for entry in (ALLOWED_OCCURRENCES[basename] as Array):
			if not (entry is Dictionary):
				continue
			var needle: String = str((entry as Dictionary).get("needle", ""))
			if not _needle_is_live(content, needle):
				stale.append("%s: '%s' no longer occurs as code" % [b, needle])
	assert_eq(stale, [],
		"these entries exempt a call that no longer exists — delete them, or the call returns unnoticed: %s"
			% str(stale))


func _index_by_basename(path: String, out: Dictionary) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full: String = "%s/%s" % [path, entry]
			if dir.current_is_dir():
				_index_by_basename(full, out)
			elif entry.ends_with(".gd"):
				out[entry] = full
		entry = dir.get_next()
	dir.list_dir_end()


func _needle_is_live(content: String, needle: String) -> bool:
	## The same rule _scan_file applies: a needle inside a leading or trailing comment
	## is not an occurrence, so a retired call surviving in prose does not excuse itself.
	if needle == "":
		return false
	for code_line in GdSource.strip_comments(content).split("\n"):
		if code_line.contains(needle):
			return true
	return false
