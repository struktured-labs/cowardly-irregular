extends GutTest

## tick 212: audit that every cutscene id returned by
## GameLoop._get_pending_story_cutscene has a matching entry in
## _CUTSCENE_COMPLETION_FLAGS.
##
## Without this audit, a new cutscene added to the story gate
## (Elder Theron path, boss intro, spotlight reveal) but forgotten
## in the completion map plays once, then plays AGAIN on the next
## gate check — infinite loop, no error message. Same class of
## silent failure as the 2026-05-20 Elder Theron bug that
## introduced _CUTSCENE_COMPLETION_FLAGS in the first place.
##
## This test walks the source code statically — no runtime cutscene
## playback. A new return value with no map entry FAILS at CI time.
##
## Bonus tick 212: _play_story_cutscene now push_warns when the
## map lookup returns empty, so any cutscene that slips past CI
## still surfaces loudly in the editor logs.

const GAME_LOOP := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Audit ──────────────────────────────────────────────────────────────

func test_every_pending_return_is_mapped() -> void:
	var src := _read(GAME_LOOP)

	# Extract _get_pending_story_cutscene body.
	var fn_idx: int = src.find("func _get_pending_story_cutscene")
	assert_gt(fn_idx, -1, "_get_pending_story_cutscene must exist")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var pending_body: String = src.substr(fn_idx, next_fn - fn_idx)

	# Extract all `return "world..."` ids.
	var pending_ids: Array[String] = []
	var cursor: int = 0
	while true:
		var ret_idx: int = pending_body.find("return \"world", cursor)
		if ret_idx < 0:
			break
		var quote_start: int = pending_body.find("\"", ret_idx)
		var quote_end: int = pending_body.find("\"", quote_start + 1)
		var id: String = pending_body.substr(quote_start + 1, quote_end - quote_start - 1)
		if not (id in pending_ids):
			pending_ids.append(id)
		cursor = quote_end + 1

	assert_gt(pending_ids.size(), 30,
		"sanity: must find > 30 cutscene return values (got %d)" % pending_ids.size())

	# Extract _CUTSCENE_COMPLETION_FLAGS body.
	var map_idx: int = src.find("const _CUTSCENE_COMPLETION_FLAGS")
	assert_gt(map_idx, -1, "_CUTSCENE_COMPLETION_FLAGS const must exist")
	# Walk to matching `}` ignoring inner braces.
	var map_end: int = src.find("\n}", map_idx)
	assert_gt(map_end, -1)
	var map_body: String = src.substr(map_idx, map_end - map_idx)

	# Extract keys: lines like `\t"world1_chapter1": ...` or `\t"world2_..." : ...`.
	var map_keys: Array[String] = []
	cursor = 0
	while true:
		var key_idx: int = map_body.find("\"world", cursor)
		if key_idx < 0:
			break
		var quote_end: int = map_body.find("\"", key_idx + 1)
		var key: String = map_body.substr(key_idx + 1, quote_end - key_idx - 1)
		# Confirm this is a KEY (followed by ":") not a VALUE.
		var after_quote: int = quote_end + 1
		var colon_idx: int = map_body.find(":", after_quote)
		# Distance to next quote — a key has ":" before the next "\"".
		var next_quote: int = map_body.find("\"", after_quote)
		if colon_idx > -1 and (next_quote < 0 or colon_idx < next_quote):
			if not (key in map_keys):
				map_keys.append(key)
		cursor = quote_end + 1

	assert_gt(map_keys.size(), 30,
		"sanity: _CUTSCENE_COMPLETION_FLAGS must have > 30 keys (got %d)" % map_keys.size())

	# Every pending id must have a map entry. Report missing as a list.
	var missing: Array[String] = []
	for id in pending_ids:
		if not (id in map_keys):
			missing.append(id)
	assert_eq(missing.size(), 0,
		"every _get_pending_story_cutscene return value must have a _CUTSCENE_COMPLETION_FLAGS entry — missing: %s" % str(missing))


# ── Loud-warning surface ──────────────────────────────────────────────

func test_play_story_cutscene_warns_on_missing_flag() -> void:
	# Pin: _play_story_cutscene push_warns when the map lookup yields
	# empty — without this, a future cutscene added to the gate but
	# forgotten in the map plays AND loops forever silently.
	var src := _read(GAME_LOOP)
	assert_true(src.contains("missing from _CUTSCENE_COMPLETION_FLAGS"),
		"_play_story_cutscene must push_warning on missing map entry")
	# AND the warning message must mention the loop bug (so devs
	# immediately understand the symptom).
	assert_true(src.contains("loop bug"),
		"warning must reference the loop bug consequence")


func test_warn_uses_cutscene_id_in_message() -> void:
	# The warning must include the cutscene_id so devs can trace it.
	var src := _read(GAME_LOOP)
	assert_true(src.contains("missing from _CUTSCENE_COMPLETION_FLAGS — flag NOT set"),
		"warning message must clearly state flag was NOT set")


# ── Map keys still contain canonical entries ───────────────────────────

func test_map_contains_w1_critical_cutscenes() -> void:
	# Don't regress the critical W1 cutscene paths (high-traffic).
	var src := _read(GAME_LOOP)
	for id in ["world1_prologue", "world1_chapter1", "world1_chapter3",
			"world1_chapter4", "world1_rat_king_defeat", "world1_mordaine_defeat"]:
		assert_true(src.contains("\"" + id + "\":"),
			"_CUTSCENE_COMPLETION_FLAGS must still contain '%s'" % id)


func test_map_contains_w6_ending() -> void:
	# Pin the narrative closer — its absence would mean the game's
	# completion state never persists.
	var src := _read(GAME_LOOP)
	assert_true(src.contains("\"world6_ending\":"),
		"_CUTSCENE_COMPLETION_FLAGS must contain 'world6_ending' (narrative closer)")


# ── Cross-pin: existing regression test ────────────────────────────────

func test_existing_cutscene_flag_regression_test_present() -> void:
	# Sanity: the original cutscene flag regression test is still
	# in the suite (don't accidentally delete it).
	var path := "res://test/unit/test_cutscene_completion_flag_regression.gd"
	assert_true(FileAccess.file_exists(path),
		"test_cutscene_completion_flag_regression.gd must still exist (original regression)")
