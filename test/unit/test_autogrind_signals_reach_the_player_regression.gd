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
	"region_advanced": "listener:GameLoop.gd",
	"region_rotation_suggested": "listener:GameLoop.gd",
	"corruption_threshold_crossed": "listener:GameLoop.gd",
	"system_collapse": "collapse_count",
	"meta_boss_spawned": "meta_bosses_spawned",
	"fatigue_event": "fatigue_events_triggered",
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
			if not src.contains("%s.connect" % sig):
				missing.append("%s -> %s does not subscribe" % [sig, f])
		else:
			if not summary.contains(evidence):
				missing.append("%s -> Summary never renders '%s'" % [sig, evidence])
	assert_eq(missing.size(), 0,
		"these signals are classified as reaching the player and the evidence is absent: %s" % str(missing))


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
