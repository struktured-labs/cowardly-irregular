extends GutTest

## tick 346: SpriteUtils._load_job_visuals push_warns on each of 3
## post-existence failure modes instead of silently leaving
## _job_visuals empty.
##
## Pre-fix the function had 3 silent failure paths:
##   - FileAccess.open returns null → silent return
##   - json.parse != OK → silent return (the `if` branch fall-through)
##   - parse OK but root is not a Dictionary → silent return
##
## All 3 silently exited the load and _job_visuals stayed empty. Then
## every job rendered with its sprite loader's hard-coded fallback
## color/outfit/headgear, and the dev had no clue the visual data was
## actually missing. Symptom: "every Cleric is showing as Fighter
## colors" — but the real cause was jobs.json wasn't parsing.
##
## Same loud-fail pattern as ticks 322, 323, 344.

const SPRITE_UTILS_PATH := "res://src/battle/sprites/SpriteUtils.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: 3 push_warning calls in _load_job_visuals ───────────

func test_loader_has_three_warnings() -> void:
	var src := _read(SPRITE_UTILS_PATH)
	var fn_idx: int = src.find("static func _load_job_visuals")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nstatic func ", fn_idx + 1)
	if next_fn < 0:
		next_fn = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	var warning_count: int = body.count("push_warning(")
	assert_gte(warning_count, 3,
		"_load_job_visuals must push_warning on each of 3 failure modes. Found: %d" % warning_count)


# ── Source pin: each failure mode named in warning ──────────────────

func test_each_failure_mode_named() -> void:
	var src := _read(SPRITE_UTILS_PATH)
	var fn_idx: int = src.find("static func _load_job_visuals")
	var next_fn: int = src.find("\nstatic func ", fn_idx + 1)
	if next_fn < 0:
		next_fn = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("FileAccess.open(jobs.json) failed"),
		"file-open warning must identify the failure mode")
	assert_true(body.contains("parse error"),
		"parse-error warning must identify the failure mode")
	assert_true(body.contains("root is not a Dictionary"),
		"non-Dict-root warning must identify the failure mode")


# ── Source pin: parse_result captured before file.close() ───────────

func test_parse_result_captured_before_close() -> void:
	# Refactored to extract the parse_result var so file.close() happens
	# once (was inside the `if ... == OK` arm only — would have
	# leaked open on failure paths pre-refactor).
	var src := _read(SPRITE_UTILS_PATH)
	var fn_idx: int = src.find("static func _load_job_visuals")
	var next_fn: int = src.find("\nstatic func ", fn_idx + 1)
	if next_fn < 0:
		next_fn = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("var parse_result: int"),
		"parse_result must be captured to a var so file.close() runs deterministically")


# ── Behavioral: happy path still loads ──────────────────────────────

func test_real_load_populates_visuals() -> void:
	# Run _load_job_visuals via SpriteUtils. The real jobs.json should
	# parse and populate _job_visuals for at least the canonical starter
	# jobs (fighter, cleric, mage, rogue, bard).
	if SpriteUtils == null:
		# SpriteUtils is a static-only class; access via class_name.
		pass
	# Defer to the class-level call rather than instantiating.
	# Call the static loader — Godot allows class_name.method() syntax.
	SpriteUtils._load_job_visuals()
	# Verify _job_visuals has at least one starter job key.
	assert_true(SpriteUtils._job_visuals.has("fighter") or SpriteUtils._job_visuals.has("cleric"),
		"happy path must populate _job_visuals with at least one starter job (sanity check that the fix doesn't break the load on a valid jobs.json)")
