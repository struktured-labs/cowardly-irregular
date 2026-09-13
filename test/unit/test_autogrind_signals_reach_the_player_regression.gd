extends GutTest

## Two bugs in two hours, one shape: an autogrind event whose ONLY surface was the console.
##
##   system_collapse    fired to a disconnected handler when the console was closed
##   meta_boss_spawned  same, and with NO counter it could not reach the Summary either
##
## Every AutogrindSystem signal has at most one listener, AutogrindUI, and _close_ui() disconnects
## all of them. Closing the console mid-grind is the normal way to watch the overworld. So "the
## console will show it" is not a delivery guarantee — it is a guarantee only while the player is
## looking at the thing they closed.
##
## Fixing instances one at a time does not stop the next signal from arriving with the same hole.
## This classifies EVERY signal and checks the classification against the source, both directions,
## so a new one cannot be added without someone deciding which bucket it is in.

const SYS := "res://src/autogrind/AutogrindSystem.gd"
const UI := "res://src/ui/autogrind/AutogrindUI.gd"
const SUMMARY := "res://src/ui/autogrind/AutogrindSummary.gd"

## Signal -> the evidence that it reaches the player WITHOUT the console. Either a stats key the
## end-of-session Summary renders, or "listener:<File.gd>" for a subscriber outside AutogrindUI.
const REACHES_PLAYER := {
	"grind_stopped": "listener:AutogrindController.gd",
	"region_cracked": "listener:AutogrindController.gd",
	## NOT a GameLoop subscription to THIS signal — that claim passed only because GameLoop
	## connects `_autogrind_controller.region_advanced`, a DIFFERENT object's signal of the same
	## name, and the old bare contains() could not tell them apart. AutogrindSystem's own
	## region_advanced has ZERO subscribers; the controller emits its own after calling
	## advance_to_next_region, and GameLoop listens to that. The event reaches the player; the
	## stated route did not. Both halves of the relay are checked below.
	"region_advanced": "relay:AutogrindController.gd",
	"region_rotation_suggested": "listener:GameLoop.gd",
	"corruption_threshold_crossed": "listener:GameLoop.gd",
	"system_collapse": "collapse_count",
	## The collapse toast lands and then the multiplier stops climbing for ten battles. Both edges
	## of that penalty were print()-only, so the console could not have shown them even when OPEN.
	## Justified by the subscription, not a counter — post_collapse_debuff_battles reaches the stats
	## dict but no UI renders it, which is how the whole penalty stayed invisible.
	"post_collapse_penalty_applied": "listener:GameLoop.gd",
	"post_collapse_penalty_expired": "listener:GameLoop.gd",
	"meta_boss_spawned": "meta_bosses_spawned",
	## Was "fatigue_events_triggered" — and that counter was TRUE about the count and FALSE about the
	## content. Six authored descriptions ("Inventory anomaly — items corrupted") reached NOBODY while
	## this file certified the signal as reaching the player. GameLoop now subscribes; the evidence is
	## the subscription, not the tally. This is the gap the payload rule below exists to close.
	"fatigue_event": "listener:GameLoop.gd",
	## NOT a subscription — my first draft claimed one and this file's own evidence check caught it.
	## The interrupt reaches the player by a different route: pre_battle_check() RETURNS a reason,
	## the controller calls stop_grind(reason), and GameLoop's grind_complete handler plays a stop
	## SFX and shows a notification carrying it. Evidence is that handler, not a connect.
	"interrupt_triggered": "notification:_show_grind_stop_notification",
}

## Signal -> why losing it while the console is closed costs the player nothing.
const CONSOLE_ONLY_BY_DESIGN := {
	"grind_started": "the player just started it; there is nothing to learn",
	"battle_completed": "routine per-battle; GameLoop builds its own battle summaries",
	"efficiency_increased": "incremental state, readable in full whenever the console reopens",
	"corruption_increased": "incremental state, same",
	"autogrind_rules_changed": "an internal refresh cue, not an event about the world",
}

## ⛔ A COUNTER PROVES THE EVENT COUNT SURVIVED. IT SAYS NOTHING ABOUT A PAYLOAD.
## `fatigue_event(event_type, description)` sat in REACHES_PLAYER with a counter as its evidence, and
## this file called it delivered. The count was delivered. The six descriptions were emitted into the
## void for as long as the signal existed. "Did the player learn it HAPPENED" and "did the player
## learn WHAT happened" are different questions and the buckets above only asked the first.
##
## So: a signal that DECLARES PARAMETERS and is justified by a COUNTER must say here why the payload
## is dispensable. Not permission to skip — the note IS the deliverable, and writing it is what makes
## someone look. A signal with no parameters needs no entry; a counter fully covers it.
const PAYLOAD_DISPENSABLE := {
	"meta_boss_spawned": "the player is about to FIGHT it — the generated name is on screen in the battle itself, so the tally is all the signal needs to carry",
}

## Declared but never emitted. Kept visible rather than deleted — a dead entry someone later wires
## up must be reclassified, and silence would let it ship with this defect built in.
const NEVER_EMITTED := {
	"autobattle_interrupted": "declared 2026, no emitter anywhere in src/",
}


func _source(path: String) -> String:
	var s: String = FileAccess.get_file_as_string(path)
	assert_ne(s, "", "control: %s must be readable or every assertion here is vacuous" % path)
	return s


func _declared_signals() -> Array:
	var out: Array = []
	for line in _source(SYS).split("\n"):
		var t: String = line.strip_edges()
		if t.begins_with("signal "):
			out.append(t.substr(7).split("(")[0].strip_edges())
	return out


func test_every_declared_signal_is_classified_both_ways() -> void:
	var declared: Array = _declared_signals()
	assert_gt(declared.size(), 5, "control: the source must actually yield signals — got %d" % declared.size())

	var classified: Array = []
	classified.append_array(REACHES_PLAYER.keys())
	classified.append_array(CONSOLE_ONLY_BY_DESIGN.keys())
	classified.append_array(NEVER_EMITTED.keys())

	var unclassified: Array = []
	for s in declared:
		if not classified.has(s):
			unclassified.append(s)
	assert_eq(unclassified.size(), 0,
		("these autogrind signals are unclassified — decide whether the player must learn of them " +
		"when the console is CLOSED, because that is the normal case: %s") % str(unclassified))

	var stale: Array = []
	for s in classified:
		if not declared.has(s):
			stale.append(s)
	assert_eq(stale.size(), 0, "classified but no longer declared — delete these: %s" % str(stale))


func test_each_must_reach_signal_actually_has_its_surface() -> void:
	## The classification is only worth the evidence behind it. A key naming a counter must have a
	## Summary that renders it; a key naming a listener must have that file subscribing.
	var summary: String = _source(SUMMARY)
	var missing: Array = []
	for sig in REACHES_PLAYER.keys():
		var evidence: String = str(REACHES_PLAYER[sig])
		if evidence.begins_with("notification:"):
			var fn: String = evidence.substr(13)
			var gl: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
			if not gl.contains("%s(reason)" % fn):
				missing.append("%s -> GameLoop never calls %s(reason)" % [sig, fn])
		elif evidence.begins_with("listener:"):
			var f: String = evidence.substr(9)
			var src: String = FileAccess.get_file_as_string("res://src/autogrind/%s" % f)
			if src == "":
				src = FileAccess.get_file_as_string("res://src/%s" % f)
			## OBJECT-QUALIFIED. A bare `<sig>.connect` is satisfied by any object carrying a signal
			## of that name — the controller mirrors four of these — so the unqualified form certified
			## region_advanced as reaching the player while AutogrindSystem's copy had no subscriber.
			if not src.contains("AutogrindSystem.%s.connect" % sig):
				missing.append("%s -> %s does not subscribe to AutogrindSystem.%s" % [sig, f, sig])
		elif evidence.begins_with("relay:"):
			## The system signal is unconsumed BY DESIGN and the event reaches the player through a
			## re-emit. Both halves required: the relay must emit its own, and GameLoop must take it.
			var rf: String = evidence.substr(6)
			var relay: String = FileAccess.get_file_as_string("res://src/autogrind/%s" % rf)
			var gl2: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
			if not relay.contains("%s.emit(" % sig):
				missing.append("%s -> %s never re-emits it" % [sig, rf])
			elif not gl2.contains("_autogrind_controller.%s.connect" % sig):
				missing.append("%s -> GameLoop does not subscribe to the relay's %s" % [sig, sig])
		else:
			if not summary.contains(evidence):
				missing.append("%s -> Summary never renders '%s'" % [sig, evidence])
	assert_eq(missing.size(), 0,
		"these signals are classified as reaching the player and the evidence is absent: %s" % str(missing))


## Signal -> its declared parameter list, "" when it takes none.
func _declared_signal_params() -> Dictionary:
	var out: Dictionary = {}
	for line in _source(SYS).split("\n"):
		var t: String = line.strip_edges()
		if not t.begins_with("signal "):
			continue
		var rest: String = t.substr(7)
		var open_paren: int = rest.find("(")
		if open_paren == -1:
			out[rest.strip_edges()] = ""
		else:
			out[rest.substr(0, open_paren).strip_edges()] = rest.substr(open_paren + 1, rest.rfind(")") - open_paren - 1).strip_edges()
	return out


## THE ARM THE FATIGUE BUG CAME THROUGH. A counter is evidence about the COUNT.
func test_a_counter_cannot_vouch_for_a_payload() -> void:
	var params: Dictionary = _declared_signal_params()
	assert_gt(params.size(), 5, "control: the parser must yield signals — got %d" % params.size())
	## Control on the PARSER, not just the count: a regression that returned "" for everything would
	## silently make every signal look payload-free and this whole arm vacuous.
	var with_params: int = 0
	for v in params.values():
		if str(v) != "":
			with_params += 1
	assert_gt(with_params, 3,
		"control: the parser found only %d signals with parameters — it is not reading argument lists" % with_params)

	var undeclared: Array = []
	for sig in REACHES_PLAYER.keys():
		var evidence: String = str(REACHES_PLAYER[sig])
		## A relay delivers the payload too: the controller re-emits WITH arguments and GameLoop's
		## handler declares all three. Note the relay's first argument is its OWN region_id, where the
		## system passes old_region — same value in practice, not the same expression, which is worth
		## knowing before anyone treats the two emits as interchangeable.
		if evidence.begins_with("listener:") or evidence.begins_with("notification:") \
				or evidence.begins_with("relay:"):
			continue  ## a subscriber/handler/relay receives the payload itself
		if str(params.get(sig, "")) == "":
			continue  ## no payload for a counter to fail to carry
		if not PAYLOAD_DISPENSABLE.has(sig):
			undeclared.append("%s(%s) -> '%s'" % [sig, params[sig], evidence])
	assert_eq(undeclared, [],
		("these carry a PAYLOAD and are justified only by a counter. A tally proves the event count " +
		"reached the player; it proves nothing about the arguments. Either point the evidence at a " +
		"listener that receives them, or add a PAYLOAD_DISPENSABLE note saying why they do not " +
		"need to arrive: %s") % [undeclared])

	## Reverse direction, so a note cannot outlive its reason — the same shape as the NEVER_EMITTED arm.
	var stale: Array = []
	for sig in PAYLOAD_DISPENSABLE.keys():
		if not REACHES_PLAYER.has(sig):
			stale.append("%s is not in REACHES_PLAYER" % sig)
		elif str(params.get(sig, "")) == "":
			stale.append("%s declares no parameters, so nothing needs excusing" % sig)
		elif str(REACHES_PLAYER[sig]).begins_with("listener:") or str(REACHES_PLAYER[sig]).begins_with("notification:"):
			stale.append("%s now has a real receiver — drop the excuse" % sig)
	assert_eq(stale, [], "PAYLOAD_DISPENSABLE entries that no longer describe anything: %s" % [stale])


func test_the_never_emitted_entries_are_still_never_emitted() -> void:
	## A suppression that outlived its reason suppresses nothing. If someone wires an emitter, this
	## fails and forces the signal into a real bucket.
	var sys_src: String = _source(SYS)
	var now_live: Array = []
	for sig in NEVER_EMITTED.keys():
		if sys_src.contains("%s.emit(" % sig):
			now_live.append(str(sig))
	assert_eq(now_live.size(), 0,
		"these are listed as never emitted but now HAVE an emitter — reclassify them: %s" % str(now_live))


func test_the_console_really_does_drop_them_all_on_close() -> void:
	## The premise. If _close_ui stopped disconnecting, this whole classification would be
	## unnecessary — and if it silently stopped, the guard above would be defending nothing.
	var ui: String = _source(UI)
	assert_true(ui.contains("_disconnect_autogrind_signals()"),
		"the console must still disconnect on close, or this file's reason for existing has changed")
	var declared: Array = _declared_signals()
	var dropped := 0
	for s in declared:
		if ui.contains("%s.disconnect" % s):
			dropped += 1
	assert_gt(dropped, 3,
		"control: the console must actually disconnect several signals (found %d) — a zero here would mean the premise is stale" % dropped)
