extends GutTest

## Regression test for the cached-boot-probe outage (struktured, 2026-07-25).
##
## BUG: HTTPBackend probed the LLM server exactly once, in _ready(), and
## is_ready() returned that boot-time verdict for the entire session. If the
## game launched in ANY window where Ollama wasn't yet reachable — machine
## boot, an Ollama restart, a few seconds' race — every LLM feature went
## silently dead for the whole run: dynamic NPC dialogue, boss taunts, party
## combat lines, Rule Composer. No in-game signal, and it stayed dead even
## after the server came up healthy seconds later. Only a restart cured it.
##
## Reported as "dynamic quips disabled" while Ollama was verifiably healthy
## (server alive, llama3 pulled, /api/tags returning 200 in <1ms) — a healthy
## backend with a dead client.
##
## FIX (shape credited to cowir-battle's cycles 12-14 stale-read family, msg 2916):
## don't cache the verdict — cache last-known-result + a timestamp and re-probe
## on a cheap interval. is_ready() kicks the refresh, so a permanent
## session-wide failure becomes self-healing within one interval.
##
## Plus the silent-failure half (cowir-main msg 2924 requirement 2): every
## reachability transition now logs AND emits availability_changed, so the
## state can never change unannounced again.
##
## HERMETICITY NOTE: a live Ollama listens on the real default base_url on
## some dev machines (it did on the machine this bug was found). Every test
## here points base_url at a dead port and drives _on_probe_completed
## directly, so results never depend on whether a local LLM happens to be up.

const DEAD_URL: String = "http://127.0.0.1:9"

# Godot's HTTPRequest.RESULT_SUCCESS, spelled out so the intent is readable.
const RESULT_OK: int = HTTPRequest.RESULT_SUCCESS
const RESULT_CANT_CONNECT: int = HTTPRequest.RESULT_CANT_CONNECT


## Off-tree backend: _ready() never fires, so no real probe is ever issued.
## Lets us drive the state machine deterministically.
func _make_detached() -> HTTPBackend:
	var be := HTTPBackend.new()
	be.base_url = DEAD_URL
	be.api_format = "ollama"
	return be


func _resolve_probe(be: HTTPBackend, ok: bool) -> void:
	var code: int = 200 if ok else 0
	var result: int = RESULT_OK if ok else RESULT_CANT_CONNECT
	be._on_probe_completed(result, code, PackedStringArray(), PackedByteArray())


# ── THE REGRESSION: recovery after a failed boot probe ───────────────────────

func test_boot_probe_failure_leaves_backend_unavailable() -> void:
	var be := _make_detached()
	autofree(be)
	_resolve_probe(be, false)
	assert_false(be.is_ready(),
		"a failed boot probe must leave the backend unavailable — that part was always correct")


func test_backend_recovers_after_server_comes_up() -> void:
	# THE bug. Boot probe fails (Ollama not up yet), server comes up, next
	# probe must flip ready true. Pre-fix this was impossible without a restart.
	var be := _make_detached()
	autofree(be)
	_resolve_probe(be, false)
	assert_false(be.is_ready(), "precondition: dead after the failed boot probe")
	_resolve_probe(be, true)
	assert_true(be.is_ready(),
		"REGRESSION: a later successful probe MUST restore availability — the boot verdict must never be permanent")


func test_backend_degrades_when_server_goes_away() -> void:
	# The mirror case: healthy at boot, server dies mid-session.
	var be := _make_detached()
	autofree(be)
	_resolve_probe(be, true)
	assert_true(be.is_ready(), "precondition: ready after a good boot probe")
	_resolve_probe(be, false)
	assert_false(be.is_ready(),
		"a failing probe must drop availability so callers route to fallbacks")


func test_recovery_survives_multiple_flaps() -> void:
	var be := _make_detached()
	autofree(be)
	for i in range(3):
		_resolve_probe(be, false)
		assert_false(be.is_ready(), "flap %d: down" % i)
		_resolve_probe(be, true)
		assert_true(be.is_ready(), "flap %d: back up — no latch may accumulate" % i)


# ── Visibility: the state must never change unannounced ──────────────────────

func test_availability_changed_emitted_on_boot_resolution() -> void:
	var be := _make_detached()
	autofree(be)
	watch_signals(be)
	_resolve_probe(be, false)
	assert_signal_emitted(be, "availability_changed",
		"observers must learn the boot verdict — Settings panel can't display what it isn't told")


func test_availability_changed_emitted_on_recovery() -> void:
	var be := _make_detached()
	autofree(be)
	_resolve_probe(be, false)
	watch_signals(be)
	_resolve_probe(be, true)
	assert_signal_emitted_with_parameters(be, "availability_changed", [true])


func test_availability_changed_emitted_on_degradation() -> void:
	var be := _make_detached()
	autofree(be)
	_resolve_probe(be, true)
	watch_signals(be)
	_resolve_probe(be, false)
	assert_signal_emitted_with_parameters(be, "availability_changed", [false])


func test_no_signal_when_state_is_unchanged() -> void:
	# Re-probing every 30s must not spam observers while nothing is changing.
	var be := _make_detached()
	autofree(be)
	_resolve_probe(be, true)
	watch_signals(be)
	_resolve_probe(be, true)
	_resolve_probe(be, true)
	assert_signal_emit_count(be, "availability_changed", 0,
		"steady state must stay quiet — only transitions are events")


# ── The interval gate ────────────────────────────────────────────────────────

func test_no_reprobe_before_the_interval_elapses() -> void:
	var be := _make_detached()
	autofree(be)
	_resolve_probe(be, false)
	var _ignored: bool = be.is_ready()
	assert_null(be._probe_request,
		"a fresh result must not trigger a re-probe — that would hammer the server on every is_ready() call")


func test_reprobe_starts_once_the_result_is_stale() -> void:
	# In-tree so HTTPRequest.request() is legal; DEAD_URL keeps it off any real server.
	var be := _make_detached()
	add_child_autofree(be)
	_resolve_probe(be, false)
	be._last_probe_msec = Time.get_ticks_msec() - int(HTTPBackend.PROBE_INTERVAL_SEC * 1000.0) - 1000
	var _ignored: bool = be.is_ready()
	assert_not_null(be._probe_request,
		"REGRESSION: once the result is stale, is_ready() must kick a fresh probe — this is the self-healing hook")


func test_boot_probe_in_flight_does_not_stack_a_second_probe() -> void:
	var be := _make_detached()
	autofree(be)
	# _first_probe_done is false until the boot probe resolves.
	var _ignored: bool = be.is_ready()
	assert_null(be._probe_request,
		"no re-probe may be issued while the boot probe is still outstanding")


func test_refresh_availability_bypasses_the_interval() -> void:
	var be := _make_detached()
	add_child_autofree(be)
	_resolve_probe(be, false)
	be.refresh_availability()
	assert_not_null(be._probe_request,
		"an explicit refresh (Settings 'test connection') must probe immediately, ignoring the interval")


# ── Observability surface ────────────────────────────────────────────────────

func test_availability_info_reports_unprobed_state() -> void:
	var be := _make_detached()
	autofree(be)
	var info: Dictionary = be.get_availability_info()
	assert_false(bool(info.get("probed", true)), "before any probe resolves, probed must be false")
	assert_eq(float(info.get("seconds_since_probe", 0.0)), -1.0,
		"seconds_since_probe must be the -1 sentinel until a probe has actually resolved")


func test_availability_info_reports_live_state() -> void:
	var be := _make_detached()
	autofree(be)
	_resolve_probe(be, true)
	var info: Dictionary = be.get_availability_info()
	assert_true(bool(info.get("available", false)), "available must mirror the last probe result")
	assert_true(bool(info.get("probed", false)), "probed must be true once a probe has resolved")
	assert_eq(str(info.get("probe_url", "")), DEAD_URL + "/api/tags",
		"probe_url must show the endpoint actually being checked, so a misconfigured base_url is visible")
	assert_gte(float(info.get("probe_interval_sec", 0.0)), 1.0,
		"the panel needs the interval to explain how quickly recovery is detected")


# ── Source pins ──────────────────────────────────────────────────────────────

func test_source_is_ready_refreshes_rather_than_caching() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/llm/HTTPBackend.gd")
	assert_true(src.find("_maybe_refresh_probe()") != -1,
		"is_ready() must consult the refresh hook — regression: silent revert to a permanently cached verdict")
	assert_true(src.find("PROBE_INTERVAL_SEC") != -1,
		"the re-probe interval must exist as a named constant")


func test_source_announces_every_transition() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/llm/HTTPBackend.gd")
	assert_true(src.find("availability_changed") != -1,
		"transitions must be observable via signal, not just logged")
	assert_true(src.find("unreachable") != -1 and src.find("reachable again") != -1,
		"both directions must log — a silent recovery is as unhelpful as a silent failure")
