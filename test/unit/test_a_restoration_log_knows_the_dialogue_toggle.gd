extends GutTest

## A log line announced a restoration that could not have happened.
##
## HTTPBackend's probe is a self-driven 30s timer (PROBE_INTERVAL_SEC) that nothing
## gates on llm_enabled, and on an unreachable->reachable transition it printed
## "dynamic dialogue restored." But LLMService.is_available() returns false whenever
## llm_enabled is false, and HTTPBackend held ZERO references to that flag. So with
## Dynamic Dialogue off — the DEFAULT on web (GameState:84), and a real player toggle
## on desktop (SettingsMenu:1367, persisted at SaveSystem:1406) — the log claimed a
## restoration while every generation path stayed scripted. The else-arm was wrong in
## the same way: "Falling back to scripted dialogue" when it was already scripted.
##
## Both arms belong to a deliberate silent-failure guard (struktured 2026-07-25), so the
## fix keeps the announcement and makes it accurate; it does not silence it. RuleComposer:41
## already reads the toggle correctly through /root/LLMService — the idiom existed, one
## surface used it and the other claimed the opposite.
##
## The file's own source guard (test_llm_backend_selfhealing_probe_regression:215) could not
## catch this: it pins that the WORDS "reachable again" and "unreachable" appear. A spelling
## pin certifies presence, never that the sentence is true.

const OFF_MARK := "stays off"
const ON_READY := "Dynamic dialogue restored."
const ON_LOST := "Falling back to scripted dialogue."

var _toggle_was: Variant = null


## Saved/restored around every arm so an abort cannot leak a flipped autoload to later files.
func before_each() -> void:
	var svc: Node = get_node_or_null("/root/LLMService")
	if svc != null and "llm_enabled" in svc:
		_toggle_was = svc.llm_enabled


func after_each() -> void:
	var svc: Node = get_node_or_null("/root/LLMService")
	if svc != null and "llm_enabled" in svc and _toggle_was != null:
		svc.llm_enabled = bool(_toggle_was)
	_toggle_was = null


func _source() -> String:
	return FileAccess.get_file_as_string("res://src/llm/HTTPBackend.gd")


# ── the derivation's values (behaviour, no tree needed: the helper is static) ──

func test_the_three_outcomes_are_three_distinct_sentences() -> void:
	var said := {}
	said[HTTPBackend.dialogue_consequence(true, true)] = 1
	said[HTTPBackend.dialogue_consequence(false, true)] = 1
	said[HTTPBackend.dialogue_consequence(true, false)] = 1
	assert_eq(said.size(), 3,
		"a recovery, a loss and a recovery-with-the-feature-off must not share one sentence")


func test_a_recovery_with_the_toggle_off_does_not_claim_restoration() -> void:
	var said: String = HTTPBackend.dialogue_consequence(true, false)
	assert_true(said.contains(OFF_MARK),
		"with the toggle off a reachable server must say the dialogue stays off, got: %s" % said)
	assert_false(said.to_lower().contains("restored"),
		"THE DEFECT: the server came back but dialogue is off, so nothing was restored: %s" % said)


func test_a_loss_with_the_toggle_off_does_not_claim_a_fallback_just_happened() -> void:
	var said: String = HTTPBackend.dialogue_consequence(false, false)
	assert_true(said.contains(OFF_MARK),
		"with the toggle off an unreachable server must say the dialogue stays off, got: %s" % said)
	assert_false(said.to_lower().contains("falling back"),
		"nothing fell back — dialogue was already scripted before the server went away: %s" % said)


func test_a_recovery_with_the_toggle_on_still_says_restored() -> void:
	assert_eq(HTTPBackend.dialogue_consequence(true, true), ON_READY,
		"with the feature on the shipped wording must be preserved, not reworded")


func test_a_loss_with_the_toggle_on_still_says_falling_back() -> void:
	assert_eq(HTTPBackend.dialogue_consequence(false, true), ON_LOST,
		"with the feature on the shipped wording must be preserved, not reworded")


# ── the toggle is read off the live service, not from a copy that can drift ──

func test_the_toggle_is_read_off_the_live_service() -> void:
	var svc: Node = get_node_or_null("/root/LLMService")
	assert_not_null(svc, "LLMService autoload must exist or every assert below is vacuous")
	assert_true("llm_enabled" in svc, "the flag must exist on the service or the read is inert")
	var b := HTTPBackend.new()
	add_child_autofree(b)
	svc.llm_enabled = false
	assert_false(b.dialogue_enabled(), "a disabled service must read as disabled")
	svc.llm_enabled = true
	assert_true(b.dialogue_enabled(), "an enabled service must read as enabled")


# ── source: the announcement must not re-inline a consequence it cannot know ──

func test_both_arms_read_one_derivation() -> void:
	var src: String = _source()
	assert_eq(src.count("var consequence: String = dialogue_consequence("), 1,
		"the consequence must be derived ONCE and read by both arms")
	for line in src.split("\n"):
		if not (line.contains("reachable again at") or line.contains("push_warning(\"[HTTPBackend] %s %s\"")):
			continue
		assert_false(line.to_lower().contains("restored") or line.to_lower().contains("falling back"),
			"an announcement arm must read the derivation, not hardcode a claim: %s" % line.strip_edges())


func test_the_sibling_transition_pins_still_hold() -> void:
	var src: String = _source()
	for token in ["availability_changed", "unreachable", "reachable again"]:
		assert_true(src.contains(token),
			"test_llm_backend_selfhealing_probe_regression:215 pins %s — this fix must not break it" % token)
