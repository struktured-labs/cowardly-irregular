extends GutTest

## LLMService._select_backend runs on every complete() call to re-probe
## backend readiness. When LLM is enabled but no backend is reachable
## (Ollama not running, HTTPBackend probe times out), the call used to
## push_warning every single time — so every NPC dialogue, boss strategy
## probe, and party-chat fetch spammed the same line.
##
## Fix: gate the warning behind a _no_backend_warned flag. Fire once,
## then reset the flag when a backend becomes ready again so a later
## outage gets its own one-shot warning.

const LLM_SERVICE_PATH := "res://src/llm/LLMService.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _body_of(func_name: String) -> String:
	var src := _read(LLM_SERVICE_PATH)
	var idx := src.find("func " + func_name)
	assert_gt(idx, -1, func_name + " must exist")
	var next_fn := src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_no_backend_warning_is_gated_by_flag() -> void:
	var body := _body_of("_select_backend")
	assert_true(body.contains("_no_backend_warned"),
		"warning must be guarded by _no_backend_warned so it doesn't fire every call")
	assert_true(body.contains("_no_backend_warned = true"),
		"the flag must be set after the warning fires")


func test_flag_resets_when_backend_comes_back() -> void:
	var body := _body_of("_select_backend")
	# When _active_backend IS set, the flag must reset so the NEXT outage
	# gets its own warning. Otherwise the first outage silences forever.
	assert_true(body.contains("_no_backend_warned = false"),
		"flag must reset when a backend becomes ready so later outages aren't silenced")


func test_flag_declared_as_member() -> void:
	var src := _read(LLM_SERVICE_PATH)
	assert_true(src.contains("var _no_backend_warned"),
		"_no_backend_warned must be declared as a member variable")
