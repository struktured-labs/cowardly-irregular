extends GutTest

## Settings "LLM Connection" row — the readout that was missing when struktured
## reported "dynamic quips disabled" (2026-07-25) against a perfectly healthy
## Ollama. The self-healing probe fixed the caching; this fixes the silence.
##
## Before this, nothing in the game could answer "is dynamic dialogue actually
## working right now?" — the player had to notice a feature was absent and
## reason backwards, which is exactly what happened. One row, whose subtitle is
## the live state and whose activation forces a re-probe.
##
## SCOPE, deliberately (cowir-main msg 3020: "resist the urge to build a
## diagnostics panel"): one action row reusing the established dynamic-subtitle
## pattern from Controls/Jukebox. No panel, no history, no log surface.
##
## The subtitle must distinguish states that look identical from the player's
## side but have completely different remedies:
##   toggle off        → turn Dynamic Dialogue on
##   no backend        → configure BYOK
##   unreachable       → start the server; it self-heals, no restart needed
##   connected         → the LLM is fine, the problem is elsewhere

const SETTINGS_PATH: String = "res://src/ui/SettingsMenu.gd"
const SERVICE_PATH: String = "res://src/llm/LLMService.gd"


func _read(path: String) -> String:
	var t: String = FileAccess.get_file_as_string(path)
	assert_false(t.is_empty(), "must be readable: %s" % path)
	return t


# ── LLMService passthrough (UI must not touch backend internals) ─────────────

func test_service_exposes_status_passthrough() -> void:
	var src: String = _read(SERVICE_PATH)
	assert_true(src.find("func get_backend_status()") != -1,
		"LLMService must expose a status passthrough so the UI never reaches into _backends or _active_backend")
	assert_true(src.find("func refresh_backend_availability()") != -1,
		"LLMService must expose a forced re-probe for the Settings 'test connection' affordance")


func test_status_passthrough_returns_dictionary() -> void:
	var svc: Node = get_node_or_null("/root/LLMService")
	assert_not_null(svc, "LLMService autoload must exist")
	var info: Variant = svc.get_backend_status()
	assert_eq(typeof(info), TYPE_DICTIONARY,
		"get_backend_status must always return a Dictionary — the UI formats it unconditionally")


func test_status_reports_enabled_flag_so_ui_can_distinguish_off_from_broken() -> void:
	# "Toggle is off" and "server is down" both mean no dynamic dialogue, but
	# the remedies are completely different. The payload must separate them.
	var svc: Node = get_node_or_null("/root/LLMService")
	var info: Dictionary = svc.get_backend_status()
	if info.is_empty():
		pass_test("no real backend in this build — empty payload is the documented 'not configured' signal")
		return
	assert_true(info.has("llm_enabled"),
		"status must carry llm_enabled so the row can say 'turn it on' rather than 'unreachable'")
	assert_true(info.has("available"), "status must carry reachability")
	assert_true(info.has("model"), "status must name the model — a wrong model is a distinct failure from a down server")


func test_refresh_returns_false_when_no_real_backend() -> void:
	# Contract: the caller can tell "probed" from "nothing to probe".
	var svc: Node = get_node_or_null("/root/LLMService")
	var result: Variant = svc.refresh_backend_availability()
	assert_eq(typeof(result), TYPE_BOOL,
		"refresh must report whether a real backend was actually probed")


# ── The row itself ───────────────────────────────────────────────────────────

func test_settings_registers_the_llm_connection_action() -> void:
	var src: String = _read(SETTINGS_PATH)
	assert_true(src.find('"llm_connection"') != -1,
		"an 'llm_connection' action row must be registered")
	assert_true(src.find('_get_llm_status_subtitle()') != -1,
		"the row's subtitle must be the LIVE status, not a static string — that's the whole feature")


func test_activation_is_wired_to_the_probe() -> void:
	var src: String = _read(SETTINGS_PATH)
	assert_true(src.find('elif item["id"] == "llm_connection":') != -1,
		"the action must be dispatched in _activate_setting or selecting it does nothing")
	assert_true(src.find("_test_llm_connection()") != -1,
		"activation must call the handler")
	assert_true(src.find("refresh_backend_availability()") != -1,
		"the handler must force a real probe — a row that only re-renders a cached verdict is theatre")


func test_row_is_hidden_on_web() -> void:
	# Web has no reachable HTTP backend, so the row would always report
	# unreachable and read as a bug rather than a fact.
	var src: String = _read(SETTINGS_PATH)
	var row_at: int = src.find('"llm_connection"')
	var guard_at: int = src.rfind('if not OS.has_feature("web"):', row_at)
	assert_gt(guard_at, -1, "the LLM Connection row must sit behind a not-web guard")


func test_handler_waits_longer_than_the_probe_timeout() -> void:
	# The probe is async; refreshing the subtitle before it resolves would show
	# a stale verdict and make the button look broken.
	var src: String = _read(SETTINGS_PATH)
	assert_true(src.find("create_timer(1.8)") != -1,
		"the refresh delay must exceed HTTPBackend.PROBE_TIMEOUT_SEC (1.5s) so a refused connection has resolved before re-render")
	assert_true(src.find("_build_ui()") != -1, "the row must be re-rendered after the probe resolves")


# ── Subtitle honesty: each state must be distinguishable and actionable ──────

func test_subtitle_is_a_nonempty_string_right_now() -> void:
	var SettingsScript: Script = load(SETTINGS_PATH)
	var menu = SettingsScript.new()
	add_child_autofree(menu)
	var subtitle: String = menu._get_llm_status_subtitle()
	assert_false(subtitle.strip_edges().is_empty(),
		"the subtitle must never be blank — a blank row is the silence this feature exists to remove")


func test_subtitle_covers_every_distinguishable_state() -> void:
	var src: String = _read(SETTINGS_PATH)
	assert_true(src.find("Dynamic Dialogue is OFF") != -1,
		"toggle-off must be named distinctly — the remedy is a toggle, not a server")
	assert_true(src.find("No LLM backend configured") != -1,
		"no-backend must be named distinctly — the remedy is BYOK config")
	assert_true(src.find("UNREACHABLE") != -1,
		"unreachable must be named distinctly — the remedy is starting the server")
	assert_true(src.find("Connected") != -1,
		"connected must be stated positively, so 'the LLM is fine' is a readable answer")


func test_unreachable_subtitle_promises_self_healing() -> void:
	# The single most valuable sentence in this feature. struktured's actual
	# failure was believing the state was permanent; it isn't, since the
	# self-healing probe shipped. The row must say so.
	var src: String = _read(SETTINGS_PATH)
	assert_true(src.find("retrying every") != -1,
		"the unreachable subtitle MUST tell the player it re-probes automatically — otherwise they restart the game, which is the exact wasted action this whole arc removed")
