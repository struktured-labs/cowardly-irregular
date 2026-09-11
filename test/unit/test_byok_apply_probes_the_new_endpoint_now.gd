extends GutTest

## Applying an LLM config marked the backend dead, then blocked the probe that
## would revive it — for up to 30 seconds.
##
## apply_byok_config() writes the new base_url/api_format/model onto HTTPBackend
## and zeroes `_ready_flag` so the next probe decides the new endpoint's fate.
## But it left `_last_probe_msec` at the OLD probe's timestamp, and
## _maybe_refresh_probe() refuses to start a probe while
## `now - _last_probe_msec < PROBE_INTERVAL_SEC`. Measured on the real path:
##
##     after boot probe   ready=true    probe_req=false
##     apply_byok_config  ready=FALSE   probe_req=false   <- _last_probe_msec stale
##     is_ready()         false, and it started NO probe  <- blocked up to 30s
##
## So every LLM call — dynamic NPC dialogue, boss intent, party combat lines,
## the Rule Composer — routed to fallbacks for the remainder of the interval,
## with the config correct and the server healthy.
##
## The window is PROBE_INTERVAL_SEC minus the age of the last probe, so applying
## a config right after a probe is the worst case and the one a Settings visit
## produces: open Settings, apply, nothing works, for half a minute.
##
## ⚠️ WHY IT SURVIVED — the workaround worked, so the diagnosis never had to.
## struktured reported "I had to enable/re-enable LLM for it to trigger"
## (2026-09-07). Re-toggling does NOT cure this: the second apply zeroes the
## flag again and `_last_probe_msec` is still stale. What cures it is the TIME
## spent toggling. The remedy people find is the one they were doing when the
## interval happened to elapse, which makes the real cause invisible and the
## superstition self-confirming.
##
## The "Test Connection" button was always correct — refresh_backend_availability
## bypasses the interval. Only APPLY was broken, and apply is the path you take
## when you actually change something.
##
## HERMETICITY: every backend here is detached (off-tree, so _ready() never runs)
## and points at a dead port, so no test depends on a local Ollama.

const DEAD_URL: String = "http://127.0.0.1:9"


## In-tree, because HTTPRequest.request() returns ERR_UNCONFIGURED off-tree — so a
## detached backend can never show that a probe STARTED, which is the observable
## every test here needs. base_url is a dead port, so nothing leaves the machine.
func _make_live() -> HTTPBackend:
	var be := HTTPBackend.new()
	be.base_url = DEAD_URL
	be.api_format = "ollama"
	add_child_autofree(be)
	return be


## Drive a resolved probe without touching the network.
func _resolve_probe(be: HTTPBackend, ok: bool) -> void:
	be._on_probe_completed(
		HTTPRequest.RESULT_SUCCESS if ok else HTTPRequest.RESULT_CANT_CONNECT,
		200 if ok else 0, PackedStringArray(), PackedByteArray())


# ── the defect ────────────────────────────────────────────────────────────────

func test_a_config_change_probes_immediately_instead_of_waiting_out_the_interval() -> void:
	var be := _make_live()
	_resolve_probe(be, true)   # resolves the probe _ready() started
	assert_true(be._ready_flag, "PREMISE: the old endpoint resolved as reachable")
	assert_eq(be._probe_request, null, "PREMISE: no probe in flight after one resolves")

	be.invalidate_and_reprobe()
	assert_false(be._ready_flag,
		"a new endpoint is unproven — the cached verdict must not carry over")
	assert_true(be._probe_request != null,
		"the probe must start NOW; zeroing the flag alone left the backend dead for up to PROBE_INTERVAL_SEC")


func test_the_interval_does_not_gate_a_config_change() -> void:
	## THE DISCRIMINATOR. _maybe_refresh_probe blocks inside the interval — that
	## is correct for routine staleness and wrong for "the endpoint just changed".
	var be := _make_live()
	_resolve_probe(be, true)
	var age: int = Time.get_ticks_msec() - be._last_probe_msec
	assert_true(age < int(be.PROBE_INTERVAL_SEC * 1000.0),
		"PREMISE: we are INSIDE the interval, which is when a Settings apply happens")

	be.is_ready()
	assert_eq(be._probe_request, null,
		"CONTROL: inside the interval the routine refresh must still decline — that behaviour is correct")

	be.invalidate_and_reprobe()
	assert_true(be._probe_request != null,
		"but an explicit config change must override the interval, or apply is a no-op for 30s")


func test_a_stale_in_flight_probe_cannot_report_on_the_new_endpoint() -> void:
	## The old endpoint's answer must not be attributed to the new one. Without
	## the disconnect, a probe already in flight against the PREVIOUS base_url
	## can complete afterwards and set _ready_flag for a server nobody asked about.
	var be := _make_live()
	var old_probe = be._probe_request
	assert_true(old_probe != null,
		"PREMISE: _ready() starts a probe, so one is in flight against the OLD endpoint")

	be.invalidate_and_reprobe()
	assert_false(old_probe.request_completed.is_connected(be._on_probe_completed),
		"the abandoned probe must be disconnected, or its late answer lands on the new config")


# ── it must still be a working backend ────────────────────────────────────────

func test_a_successful_probe_after_the_change_restores_availability() -> void:
	## CONTROL: this invalidates a verdict, it does not disable the backend.
	var be := _make_live()
	_resolve_probe(be, false)
	be.invalidate_and_reprobe()
	_resolve_probe(be, true)
	assert_true(be.is_ready(),
		"once the new endpoint answers 2xx the backend must be available again")


func test_a_failing_probe_after_the_change_leaves_it_unavailable() -> void:
	## CONTROL the other way: invalidating must not manufacture availability.
	var be := _make_live()
	_resolve_probe(be, true)
	be.invalidate_and_reprobe()
	_resolve_probe(be, false)
	assert_false(be._ready_flag,
		"an unreachable new endpoint must read unavailable, not inherit the old verdict")


func test_the_routine_refresh_path_is_untouched() -> void:
	## CONTROL: the 30s self-healing re-probe must still work as shipped.
	var be := _make_live()
	_resolve_probe(be, false)
	be._last_probe_msec = Time.get_ticks_msec() - int(be.PROBE_INTERVAL_SEC * 1000.0) - 1000
	be.is_ready()
	assert_true(be._probe_request != null,
		"past the interval the routine refresh must still fire — that is the 2026-07-25 self-heal")


# ── the wiring: the real config path must call it ─────────────────────────────

func test_apply_byok_config_forces_the_reprobe() -> void:
	## EXECUTION IS NOT SELECTION: the method existing proves nothing about
	## whether the Settings "apply" path reaches it. Both Settings screens and
	## boot call apply_byok_config, so that is the entry point that must do it.
	var src: String = FileAccess.get_file_as_string("res://src/llm/LLMService.gd")
	assert_false(src.is_empty(), "CONTROL: source must load")
	assert_true(src.contains("invalidate_and_reprobe"),
		"apply_byok_config must force the re-probe, not merely zero the flag")
