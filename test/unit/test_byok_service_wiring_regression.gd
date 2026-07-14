extends GutTest

## tick 39: LLMService now applies the GameState BYOK fields to
## HTTPBackend at boot AND on demand (apply_byok_config public method
## the settings menu will call when the user toggles the switch).
##
## Pins:
##   - apply_byok_config exists with the right signature
##   - it reverts to localhost Ollama defaults when BYOK is off
##   - it does NOT log the raw API key — never, even masked
##   - the web build short-circuits early (no key handling in browser)
##   - the readiness flag is reset so the next probe re-evaluates the
##     new endpoint instead of trusting a stale ready=true

const LLM_SERVICE := "res://src/llm/LLMService.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _body_of(func_name: String) -> String:
	var src := _read(LLM_SERVICE)
	var idx := src.find("func " + func_name)
	assert_gt(idx, -1, func_name + " must exist")
	var next_fn := src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_apply_byok_config_is_public() -> void:
	var src := _read(LLM_SERVICE)
	# Settings menu (future tick) calls this. Must NOT be prefixed
	# with `_` (which would mark it private by GDScript convention).
	assert_true(src.contains("func apply_byok_config() -> bool"),
		"apply_byok_config must be a public method returning bool — settings menu calls it on every toggle/edit")


func test_build_backends_calls_apply_byok() -> void:
	# Without this, the user's persisted BYOK config won't take effect
	# until the next runtime apply — boot would always use Ollama
	# defaults.
	var body := _body_of("_build_backends")
	assert_true(body.contains("apply_byok_config()"),
		"_build_backends must call apply_byok_config so the persisted config takes effect at boot")


func test_byok_off_reverts_to_ollama_defaults() -> void:
	# Critical: toggling BYOK off must restore the localhost defaults.
	# Otherwise the user's HTTPBackend stays pointed at their cloud
	# URL forever — they'd see "no backend ready" after toggling off
	# because Ollama isn't reachable at the saved cloud URL.
	var body := _body_of("apply_byok_config")
	assert_true(body.contains("http://localhost:11434"),
		"apply_byok_config must revert base_url to the localhost Ollama default when BYOK is off")
	assert_true(body.contains("\"ollama\""),
		"apply_byok_config must revert api_format to 'ollama' when BYOK is off")
	assert_true(body.contains("\"llama3\""),
		"apply_byok_config must revert model to llama3 when BYOK is off")


func test_byok_apply_resets_readiness_flag() -> void:
	# After a config swap the backend's cached is_ready() answer is
	# stale — next call needs to re-probe the new endpoint, not trust
	# the old endpoint's ready=true.
	var body := _body_of("apply_byok_config")
	assert_true(body.contains("_ready_flag = false"),
		"apply_byok_config must reset the backend's readiness flag so the new endpoint is probed fresh")


func test_web_build_short_circuits() -> void:
	# Belt-and-suspenders: GameState.load_settings already skips BYOK
	# fields on web, so they stay empty. But apply_byok_config must
	# ALSO short-circuit on web — the field could still be non-empty
	# if a desktop settings.json was transplanted into the web pck.
	var body := _body_of("apply_byok_config")
	assert_true(body.contains("OS.has_feature(\"web\")"),
		"apply_byok_config must early-return on web — browser sandbox can't safely hold the key even if it's somehow present in memory")


func test_log_never_prints_raw_api_key() -> void:
	# The log helper must use '<set>' / '<empty>' sentinels, not the
	# actual key. CRITICAL safety check — this is the user's secret.
	var body := _body_of("_log_byok_applied")
	assert_true(body.contains("<set>") and body.contains("<empty>"),
		"_log_byok_applied must use <set>/<empty> sentinels for api_key, never the raw value")
	# Direct safety: the log helper must NOT include `api_key` as a
	# value-format placeholder fed by the raw field.
	assert_false(body.contains("key=%s\" % [str(http.api_key)"),
		"_log_byok_applied must NEVER pass the raw api_key into the format args")


func test_apply_does_nothing_without_byok_field_on_game_state() -> void:
	# Boot-edge: very early calls might happen before GameState is
	# ready or before the field exists. Must early-return false then,
	# not crash.
	var body := _body_of("apply_byok_config")
	assert_true(body.contains("\"llm_custom_backend_enabled\" in gs"),
		"apply_byok_config must check the field exists on GameState before reading it — boot-edge safety")
