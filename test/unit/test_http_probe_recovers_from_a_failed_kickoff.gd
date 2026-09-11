extends GutTest

## A malformed base_url disabled the LLM for the whole session, silently.
##
## struktured, 2026-09-07: "I had to enable/renable llm in debugger for it
## trigger." I diagnosed the BYOK half that day and never explained the toggle.
## This is the toggle.
##
## `_start_probe` calls HTTPRequest.request(); if that returns non-OK the request
## NEVER STARTS, so `_on_probe_completed` never fires and `_first_probe_done`
## stays false. `_maybe_refresh_probe` opens with `if not _first_probe_done:
## return` — so the re-probe can never run, and the backend is stuck unavailable
## until something rebuilds it. Re-applying the LLM config rebuilds it. That is
## the enable/re-enable.
##
## MEASURED before the fix, one frame and then 240 frames:
##   base_url ""            -> probed=false  STUCK FOREVER
##   base_url "not a url"   -> probed=false  STUCK FOREVER
##   valid URL, dead port   -> probed=true   retry armed, self-heals
##
## The third case is the discriminator: an unreachable SERVER always recovered,
## which is why this never looked like a bug. Only an unusable URL sticks — and
## a half-filled BYOK panel produces exactly that.
##
## The old comment said "leave _ready_flag false" as though that settled it, and
## the warning on the success path promises "Re-probing every 30s; no restart
## needed once it's up" — a promise this branch could not honour and which never
## printed here, because it lives inside the completion handler that never runs.

const HB := preload("res://src/llm/HTTPBackend.gd")

## Frames to let a real in-flight request fail and report. The dead-port control
## needs this; the invalid-URL cases resolve synchronously.
const SETTLE_FRAMES: int = 240


func _backend(url: String, fmt: String) -> Node:
	var b = HB.new()
	b.base_url = url
	b.api_format = fmt
	b.model = "llama3"
	add_child_autofree(b)
	return b


func _settled_info(url: String, fmt: String) -> Dictionary:
	var b := _backend(url, fmt)
	for _i in range(SETTLE_FRAMES):
		await get_tree().process_frame
	return b.get_availability_info()


# ── the defect ────────────────────────────────────────────────────────────────

func test_an_empty_base_url_still_arms_the_retry() -> void:
	var info: Dictionary = await _settled_info("", "openai")
	assert_true(bool(info.get("probed", false)),
		"a probe that could not START must still count as concluded, or _maybe_refresh_probe returns early forever and only re-applying the config recovers")


func test_a_malformed_base_url_still_arms_the_retry() -> void:
	var info: Dictionary = await _settled_info("not a url", "ollama")
	assert_true(bool(info.get("probed", false)),
		"a malformed base_url must not disable the LLM for the whole session")


func test_a_failed_kickoff_is_not_reported_as_available() -> void:
	## The fix must not overcorrect into claiming the backend works.
	var info: Dictionary = await _settled_info("", "openai")
	assert_false(bool(info.get("available", true)),
		"arming the retry must not mark an unusable backend available")


func test_the_retry_clock_starts_so_the_interval_can_elapse() -> void:
	## `probed` alone is not enough: _maybe_refresh_probe also compares against
	## _last_probe_msec, which only the completion handler used to set. Left at 0
	## the interval check would pass immediately and re-probe every single call.
	var info: Dictionary = await _settled_info("", "openai")
	var since: float = float(info.get("seconds_since_probe", -1.0))
	assert_gte(since, 0.0,
		"the probe clock must be started on a failed kick-off, not left at its initial value")
	assert_lt(since, float(info.get("probe_interval_sec", 30.0)),
		"and it must be recent, so the next re-probe waits the interval instead of firing every call")


# ── the discriminator ─────────────────────────────────────────────────────────

func test_an_unreachable_server_already_recovered_and_still_does() -> void:
	## CONTROL, and the reason this defect stayed hidden. A valid URL pointing at
	## a dead port always armed the retry — the common "Ollama isn't up yet" case
	## self-heals, so the feature looked fine. If this ever fails, the test above
	## is measuring the harness rather than the fix.
	var info: Dictionary = await _settled_info("http://127.0.0.1:59999", "ollama")
	assert_true(bool(info.get("probed", false)),
		"an unreachable server must arm the retry — this path was never broken")
	assert_false(bool(info.get("available", true)),
		"and must not be reported available")


func test_the_probe_url_is_built_from_the_format() -> void:
	## CONTROL for the cases above: proves the invalid inputs really do produce an
	## unusable URL, so those tests exercise the failed-kickoff path rather than
	## some other early return.
	var openai: Dictionary = await _settled_info("", "openai")
	assert_eq(str(openai.get("probe_url", "")), "/v1/models",
		"an empty base_url must yield a schemeless, unusable probe URL")
	var ollama: Dictionary = await _settled_info("not a url", "ollama")
	assert_eq(str(ollama.get("probe_url", "")), "not a url/api/tags",
		"a malformed base_url must yield an unusable probe URL")
