extends GutTest

## "UNREACHABLE (llama3)" told the player WHAT was unreachable and never WHERE.
##
## With BYOK the endpoint is user-configurable (`base_url` persists in settings.json), so
## the same message covers two very different failures: a stopped Ollama on the default
## localhost:11434, and a perfectly healthy server behind a mistyped URL. The player can
## act on the first and cannot even see the second.
##
## `HTTPBackend.get_availability_info()` has always returned `probe_url`, and
## `LLMService.get_backend_status()` has always passed it through — the subtitle simply
## discarded it. This pins that it is spent, not that it is available.
##
## Pins the RELATIONSHIP (the rendered string carries the endpoint the probe actually
## used) rather than the literal copy, so rewording stays green and dropping the
## diagnostic reds.

const SETTINGS_SRC := "res://src/ui/SettingsMenu.gd"


func _subtitle_body() -> String:
	var f := FileAccess.open(SETTINGS_SRC, FileAccess.READ)
	assert_not_null(f, "could not open SettingsMenu.gd")
	if f == null:
		return ""
	var src := f.get_as_text()
	f.close()
	var idx := src.find("func _get_llm_status_subtitle")
	assert_gt(idx, -1, "_get_llm_status_subtitle must exist")
	var next := src.find("\nfunc ", idx + 1)
	return src.substr(idx, next - idx) if next > -1 else src.substr(idx)


func test_unreachable_subtitle_spends_the_probe_url() -> void:
	var body := _subtitle_body()
	assert_ne(body, "", "subtitle function body was empty")
	assert_true(body.contains("probe_url"),
		("the UNREACHABLE readout must name the endpoint the probe used — with BYOK the "
		+ "URL is configurable, so 'unreachable' alone cannot separate a stopped server "
		+ "from a mistyped base_url"))


func test_the_retry_interval_is_still_named() -> void:
	# The self-heal is the other half of the message: the player must know it recovers
	# on its own rather than needing a restart (struktured 2026-07-25).
	var body := _subtitle_body()
	assert_true(body.contains("probe_interval_sec"),
		"the readout must still tell the player the probe retries on its own")


func test_the_reader_can_see_this_file_at_all() -> void:
	# Control: a body-extraction that silently returned "" would pass both asserts above
	# by vacuity if they were phrased as absence checks.
	var body := _subtitle_body()
	assert_gt(body.length(), 100, "extracted body is implausibly short")
	assert_true(body.contains("UNREACHABLE"), "known-present token missing from the body")
	assert_false(body.contains("Zzznotasubtitle"), "fabricated token found")
