extends GutTest

## AutogrindSystem.check_fatigue_event authors SIX descriptions — "Inventory anomaly — items
## corrupted", "Reality fold — experience amplified!", "System interference — MP reserves
## fluctuating" — and emits them on `fatigue_event`. Measured before this fix: that signal had
## ZERO listeners anywhere in src/. Every description was emitted into the void.
##
## What the player got instead was GameLoop's own line, built from the COUNTER:
##
##     if AutogrindSystem.fatigue_events_triggered > 0:
##         ... "[FATIGUE #%d] Check system stability"
##
## ⛔ TWO DEFECTS IN ONE CONDITION. `> 0` is true for EVERY REMAINING BATTLE once the first event
## lands, so the line repeated after every battle for the rest of the session with a frozen number —
## while the block's own comment said "Log any fatigue event that fired THIS CYCLE". And the text was
## generic, so a player whose Mage lost 15% MP read the same words as one who gained 50% EXP.
##
## These arms drive AutogrindSystem's real signal. They do not instantiate GameLoop — it is the
## project's largest scene-bound node — so the console-facing half is asserted at the source level,
## and the SIGNAL half, which is where the bug lived, is asserted behaviourally.

var _sys

## Verbatim from check_fatigue_event. If an event type is added without a description, this reds.
const EVENT_TYPES := ["screen_glitch", "enemy_boost", "party_debuff", "mp_drain", "item_loss", "exp_surge"]


func before_each() -> void:
	AutogrindSystem._test_disable_persistence = true
	_sys = AutogrindSystem


func after_each() -> void:
	AutogrindSystem._test_disable_persistence = false


## THE ARM THAT WOULD HAVE CAUGHT IT: the signal must reach somebody, and carry the real text.
func test_the_fatigue_signal_carries_a_description_a_listener_can_use() -> void:
	var seen: Array = []
	var probe := func(event_type: String, description: String) -> void:
		seen.append({"type": event_type, "desc": description})
	_sys.fatigue_event.connect(probe)

	## Drive the real emitter rather than emitting by hand — emitting the signal myself would prove
	## only that Godot delivers signals, which was never in doubt.
	_sys.battles_completed = 999
	var fired := 0
	for _i in range(400):
		if not _sys.check_fatigue_event().is_empty():
			fired += 1
		if fired >= 6:
			break
	_sys.fatigue_event.disconnect(probe)

	gut.p("  drove the real emitter: %d events, %d delivered" % [fired, seen.size()])
	assert_gt(fired, 0, "CONTROL: no fatigue event fired in 400 attempts — the emitter never ran, so this proves nothing")
	assert_eq(seen.size(), fired, "an event fired without reaching the listener")
	for row in seen:
		assert_ne(str(row["desc"]).strip_edges(), "",
			"'%s' emitted an EMPTY description — the console would print the prefix and nothing else" % row["type"])
		assert_true(EVENT_TYPES.has(str(row["type"])),
			"unknown fatigue type '%s' — add it to EVENT_TYPES and give it a description" % row["type"])


## Every authored type must have its own words. This is the property the generic line destroyed:
## six distinct events collapsing to one sentence.
func test_every_event_type_has_its_own_description() -> void:
	var src := FileAccess.get_file_as_string("res://src/autogrind/AutogrindSystem.gd")
	var i: int = src.find("func check_fatigue_event")
	assert_gt(i, -1, "check_fatigue_event is gone")
	var body: String = src.substr(i, 1600)
	var descriptions := {}
	for t in EVENT_TYPES:
		var at: int = body.find('"%s":' % t)
		assert_gt(at, -1, "'%s' has no arm in check_fatigue_event" % t)
		var line: String = body.substr(at, 200)
		var d0: int = line.find('description = "')
		assert_gt(d0, -1, "'%s' sets no description" % t)
		var d: String = line.substr(d0 + 15, line.find('"', d0 + 15) - d0 - 15)
		descriptions[t] = d
	gut.p("  %d types, %d distinct descriptions" % [EVENT_TYPES.size(), descriptions.values().size()])
	var distinct := {}
	for d in descriptions.values():
		distinct[d] = true
	assert_eq(distinct.size(), EVENT_TYPES.size(),
		"two fatigue types share a description, so the console cannot tell them apart: %s" % [descriptions])


## THE SPAM. The console line must be gated on an event having fired, NOT on the session counter
## being non-zero — which is true forever after the first one.
func test_the_console_line_is_not_gated_on_the_session_counter() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var code_only := ""
	for line in src.split("\n"):
		code_only += line.split("#")[0] + "\n"
	assert_false(code_only.contains("if AutogrindSystem.fatigue_events_triggered > 0:"),
		"the console line is gated on the session COUNTER — true for every battle after the first event, so it repeats forever with a frozen number")
	assert_false(code_only.contains("Check system stability"),
		"the generic fatigue text is back — it replaces six authored descriptions with one sentence")


## And the description must be what gets printed, through a real listener.
func test_gameloop_listens_and_prints_the_authored_description() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true(src.contains("AutogrindSystem.fatigue_event.connect("),
		"GameLoop does not connect fatigue_event — the six descriptions reach nobody")
	var i: int = src.find("func _on_autogrind_fatigue_event")
	assert_gt(i, -1, "no fatigue handler")
	## ⛔ SKIP THE SIGNATURE LINE. `description` is a PARAMETER NAME, so `body.contains("description")`
	## over the whole function is satisfied by the declaration and says nothing about use. Measured:
	## a mutation that dropped the argument entirely scored GREEN, 5/5 — predicted Failing 1, got 0.
	var after_sig: int = src.find("\n", i)
	var body: String = src.substr(after_sig, 400)
	assert_true(body.contains("description"),
		"the handler's BODY never mentions `description` — it takes the argument and throws away the only thing that says what happened")

	## Cleared on a successful log, or the same line reprints next battle — the spam in another shape.
	var j: int = src.find("_pending_fatigue_line != \"\"")
	assert_gt(j, -1, "the pending line is never consumed")
	assert_true(src.substr(j, 400).contains("_pending_fatigue_line = \"\""),
		"the pending fatigue line is printed but never cleared, so it repeats every battle")


## The connect must be idempotent. Autogrind sessions start repeatedly in one run, and an unguarded
## connect would print the same line N times after the Nth session.
func test_the_connect_is_guarded_against_repeat_sessions() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var i: int = src.find("AutogrindSystem.fatigue_event.connect(")
	var window: String = src.substr(maxi(i - 220, 0), 320)
	assert_true(window.contains("is_connected(_on_autogrind_fatigue_event)"),
		"fatigue_event is connected without an is_connected guard — a second grind session doubles every fatigue line")
