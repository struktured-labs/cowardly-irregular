extends GutTest

## The one-shot "Dynamic dialogue unavailable" toast is gated on a WHITELIST of reason strings, and
## LLMService emits five distinct reasons. A reason missing from the whitelist is silence, which for
## a player reads as the feature being broken rather than unreachable.
##
## The gap this closes: with no Ollama, NullBackend is the active backend (it is always ready), so
## `complete`/`choose` fail with "request failed or cancelled" (whitelisted, toast fires) but
## `complete_json` fails with "backend cannot produce JSON" (was NOT whitelisted). A player whose
## only LLM feature is JSON-mode — Settings → LLM Boss Strategy on its own — got no notice at all.

const LLM_PATH := "res://src/llm/LLMService.gd"
const LOOP_PATH := "res://src/GameLoop.gd"

## Emitted by a HEALTHY backend that merely refused one response. Must stay quiet, or every
## schema-invalid reply tells the player their LLM is down.
const DELIBERATELY_QUIET: Array[String] = ["guard rejected response"]


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "expected %s to be readable" % p)
	return t


## Every reason string LLMService can emit, derived from its own emit sites.
func _emitted_reasons() -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.new()
	re.compile('inference_failed\\.emit\\([^,]+,\\s*"([^"]+)"')
	for m in re.search_all(_read(LLM_PATH)):
		var r: String = m.get_string(1)
		if not out.has(r):
			out.append(r)
	return out


## The whitelist the toast actually gates on, derived from GameLoop rather than restated.
func _whitelist() -> Array[String]:
	var src: String = _read(LOOP_PATH)
	var at: int = src.find("_AVAILABILITY_REASONS :=")
	assert_gt(at, -1, "CONTROL: the whitelist must exist to be read")
	var close: int = src.find("]", at)
	var out: Array[String] = []
	var re := RegEx.new()
	re.compile('"([^"]+)"')
	for m in re.search_all(src.substr(at, close - at)):
		out.append(m.get_string(1))
	return out


func test_every_emitted_reason_is_classified() -> void:
	## The ratchet: a new emit reason must be whitelisted or named quiet on purpose, never left to
	## default into silence.
	var emitted: Array[String] = _emitted_reasons()
	assert_gte(emitted.size(), 5,
		"CONTROL: derived only %d reasons from the emit sites — the derivation is broken" % emitted.size())
	var wl: Array[String] = _whitelist()
	var unclassified: Array[String] = []
	for r in emitted:
		if not wl.has(r) and not DELIBERATELY_QUIET.has(r):
			unclassified.append(r)
	assert_eq(unclassified, ([] as Array[String]),
		"these reasons reach the player as SILENCE — whitelist them or add them to DELIBERATELY_QUIET with a reason: %s" % ", ".join(unclassified))


func test_the_json_capability_failure_is_an_availability_failure() -> void:
	assert_true(_whitelist().has("backend cannot produce JSON"),
		"a JSON-only feature (Boss Strategy alone) stays silent when no backend is reachable")


func test_only_the_null_backend_can_produce_that_reason() -> void:
	## WHY the arm above is safe rather than noisy: the reason implies no real backend. If a real
	## backend ever declares supports_json() false, this reds and the whitelist needs rethinking.
	assert_true(_read("res://src/llm/HTTPBackend.gd").contains("func supports_json() -> bool:\n\t# Both Ollama and OpenAI-compat APIs support JSON-mode requests.\n\treturn true"),
		"HTTPBackend no longer unconditionally supports JSON, so the reason can now come from a HEALTHY backend")
	assert_true(_read("res://src/llm/NullBackend.gd").contains("func is_ready() -> bool:\n\treturn true"),
		"CONTROL: NullBackend must still be always-ready, which is why it becomes active with no server")


func test_a_healthy_backends_guard_rejection_stays_quiet() -> void:
	## CONTROL in the other direction: without this, whitelisting everything would pass the arms above.
	for r in DELIBERATELY_QUIET:
		assert_false(_whitelist().has(r),
			"'%s' comes from a WORKING backend refusing one response; toasting it tells the player their LLM is down when it is not" % r)
