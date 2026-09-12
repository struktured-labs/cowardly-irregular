extends GutTest

## The BYOK log line is one token away from writing a player's API key to disk.
##
## `GameState.llm_custom_api_key` is marked **SENSITIVE — never log, never print**
## (GameState:93). BYOK is desktop-only and the key persists in settings.json; the
## one place it could escape into a *log* is the config line LLMService emits when
## a custom endpoint is applied:
##
##     "[LLMService] BYOK applied: format=%s url=%s model=%s key=%s"
##
## Today that last field is `"<set>"` or `"<empty>"` — presence, never value. That
## is correct and it was correct before this file existed. **Nothing enforced it.**
##
## ⚠️ NO CURRENT DEFECT. Measured across the whole lane:
##     api_key readers in src/llm/     1 — the Authorization header (HTTPBackend:289)
##     prints/warnings carrying it     0
##     api_key or base_url in a prompt 0
##     CONTROL  the same scan finds 11 push_warning sites in LLMService
##
## This is a ratchet on an IRREVERSIBLE failure, which is the case for pinning a
## property that is already true. `user://logs/godot.log` persists on disk; a key
## written there is leaked for as long as the file exists, and no later fix
## un-writes it. The tempting edit is swapping `"<set>"` for the masked helper
## "just for debugging" — and a masked key still leaks length and both ends.
##
## Asserted on the RENDERED LINE rather than the source: a leak can arrive as a
## format change, a new field, a different helper, or a second log site, and only
## the text catches all four.

const LS := preload("res://src/llm/LLMService.gd")

## Distinctive enough that a substring search cannot match it by accident, and
## long enough that a masked form (first 4 + last 4) is also distinctive.
const FAKE_KEY := "sk-zzqq1234ABCDEFGHIJKLMNOP9876wxyz"


func _backend_with_key(key: String) -> LLMBackend:
	var be := HTTPBackend.new()
	add_child_autofree(be)
	be.api_format = "openai"
	be.base_url = "https://example.invalid/v1"
	be.model = "some-model"
	be.api_key = key
	return be


# ── the property ──────────────────────────────────────────────────────────────

func test_the_line_never_contains_the_key() -> void:
	## THE ARM.
	var line: String = LS.byok_log_line(_backend_with_key(FAKE_KEY))
	assert_eq(line.find(FAKE_KEY), -1,
		("the BYOK log line carries the raw api_key: %s. Fix in LLMService.byok_log_line — "
		+ "report PRESENCE only ('<set>' / '<empty>'). user://logs/godot.log persists on disk "
		+ "and no later change un-writes a key already logged.") % line)


func test_not_even_a_masked_key() -> void:
	## The stronger half, and the one a future edit reaches for: a masked key is
	## still the key's length and both of its ends.
	var line: String = LS.byok_log_line(_backend_with_key(FAKE_KEY))
	var head: String = FAKE_KEY.substr(0, 4)
	var tail: String = FAKE_KEY.substr(FAKE_KEY.length() - 4)
	assert_eq(line.find(head), -1,
		("the line carries the key's first 4 characters (%s) — a masked key is still key "
		+ "material. Report presence only: %s") % [head, line])
	assert_eq(line.find(tail), -1,
		"the line carries the key's last 4 characters (%s): %s" % [tail, line])


func test_presence_is_reported_both_ways() -> void:
	## CORRECT-WORK: the field must still say something useful, or the next reader
	## deletes it and loses the one signal that BYOK took effect at all.
	assert_true(LS.byok_log_line(_backend_with_key(FAKE_KEY)).find("key=<set>") != -1,
		"a configured key must report as <set>")
	assert_true(LS.byok_log_line(_backend_with_key("")).find("key=<empty>") != -1,
		"an absent key must report as <empty>")


func test_the_line_still_names_the_config_it_is_for() -> void:
	## CONTROL: a line that reported nothing would pass every arm above. The
	## non-secret fields are the reason the log exists.
	var line: String = LS.byok_log_line(_backend_with_key(FAKE_KEY))
	for expected in ["openai", "https://example.invalid/v1", "some-model", "BYOK applied"]:
		assert_true(line.find(expected) != -1,
			"the log line no longer names %s — it reports nothing and should not exist: %s"
				% [expected, line])


# ── nothing else in the lane may log it either ────────────────────────────────

func test_no_other_log_site_in_the_lane_interpolates_the_key() -> void:
	## A second log site is the other way this leaks, and it would not touch the
	## function above. Scans every print/warning in src/llm/ for the field name.
	var offenders: Array[String] = []
	for path in _lane_files():
		var src: String = FileAccess.get_file_as_string(path)
		var lineno: int = 0
		for raw in src.split("\n"):
			lineno += 1
			var line: String = raw
			var hash_at: int = line.find("#")
			if hash_at != -1:
				line = line.substr(0, hash_at)
			var logs: bool = line.find("print(") != -1 or line.find("push_warning(") != -1 \
				or line.find("push_error(") != -1 or line.find("printerr(") != -1
			if logs and line.find("api_key") != -1:
				offenders.append("%s:%d" % [path.get_file(), lineno])
	assert_eq(offenders, ([] as Array[String]),
		("these log sites interpolate api_key: %s. Fix: report presence ('<set>'/'<empty>') "
		+ "or drop the field. GameState:93 marks it SENSITIVE — never log, never print.")
			% ", ".join(offenders))


func test_the_log_site_scan_can_find_a_log_site() -> void:
	## POSITIVE CONTROL: the zero above is worth nothing unless the same scan
	## reports hits on the log calls that really are there.
	var found: int = 0
	for path in _lane_files():
		for raw in FileAccess.get_file_as_string(path).split("\n"):
			if raw.find("push_warning(") != -1:
				found += 1
	assert_gt(found, 5,
		"the scan finds almost no push_warning in src/llm/ — it is broken, not the lane")


func _lane_files() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open("res://src/llm")
	## The control is AFTER the null branch on purpose. A `return out` there skips
	## it in exactly the case it exists for — an unopenable directory yields an
	## empty corpus, and the offender arm then passes having scanned nothing.
	## Found by a mutation arm under-predicting: blinding the scan redded the
	## positive control and NOT this, because this assert was unreachable.
	if d != null:
		d.list_dir_begin()
		var n: String = d.get_next()
		while n != "":
			if n.ends_with(".gd"):
				out.append("res://src/llm/%s" % n)
			n = d.get_next()
		d.list_dir_end()
	assert_gt(out.size(), 5,
		"CONTROL: the lane scan found %d files — the scan is broken, not the lane" % out.size())
	return out
