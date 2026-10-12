extends GutTest

## The detector for a DEAD AUDIO MIXER is reached from exactly one place, and its
## reachability was guarded by a file-wide substring match whose own message
## overclaimed.
##
## `SoundManager.audio_liveness_check()` is what notices the 2026-08-14 / .542 class:
## "playback position frozen at %.2fs while playing — game audio mixer is dead".
## That is the failure that froze struktured's game on 2026-09-25 (audio dead, input
## dead). It has ONE caller — `BattleScene._on_round_started_snap_home`, the handler
## connected to `BattleManager.round_started`.
##
## WHAT WAS GUARDING THAT, before this file:
##     test_battle_targeting_dim_regression:45
##       assert_true("SoundManager.audio_liveness_check()" in bs, "probe runs every battle round")
## The message claims a runtime property. The assertion is `in` over the whole of
## BattleScene.gd, so the string satisfies it from a comment, from a dead function, or
## from a handler nothing connects. Its LOGIC is well covered — four arms in
## test_the_liveness_check_does_not_call_a_fresh_bed_dead_regression, including a
## control that a genuinely still playback IS called dead. Only the reach was spelling.
##
## ⚠️ RESIDUAL LIMIT, stated rather than left to be discovered: this file cannot prove
## the signal FIRES at runtime. BattleScene's _ready builds UI that has no viewport
## under GUT (measured previously: "Cannot call method 'add_theme_font_size_override'
## on a null value"), so the round cannot be driven here. What it does prove is that
## every link of the chain exists AND that the call sits inside the handler the connect
## line actually names — which is what a substring match cannot distinguish.

const BS := "res://src/battle/BattleScene.gd"
const BM := "res://src/battle/BattleManager.gd"
const SM := "res://src/audio/SoundManager.gd"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const CALL := "SoundManager.audio_liveness_check()"
const SIGNAL_NAME := "round_started"


## Comment-stripped, so a comment mentioning the call cannot satisfy any arm below.
func _code(path: String) -> String:
	var c: String = GdSource.code_of(path)
	assert_gt(c.length(), 2000, "SCOPE control: %s read back %d chars of code" % [path, c.length()])
	return c


## The body of `fn` only — from its `func` line to the next top-level `func`.
func _body_of(code: String, fn: String) -> String:
	var lines: PackedStringArray = code.split("\n")
	var out: PackedStringArray = []
	var inside := false
	for l in lines:
		if l.begins_with("func ") or l.begins_with("static func "):
			if inside:
				break
			inside = l.begins_with("func %s(" % fn) or l.begins_with("static func %s(" % fn)
			continue
		if inside:
			out.append(l)
	return "\n".join(out)


## The handler name is READ OFF the connect line rather than typed here, so a rename
## that keeps the wiring intact does not red this file, and a rewiring to a DIFFERENT
## handler cannot keep it green.
func _connected_handler() -> String:
	var code: String = _code(BS)
	## BattleManager.round_started.connect(_on_whatever)
	var needle: String = "BattleManager.%s.connect(" % SIGNAL_NAME
	var at: int = code.find(needle)
	if at < 0:
		return ""
	var rest: String = code.substr(at + needle.length())
	var close: int = rest.find(")")
	return rest.substr(0, close).strip_edges() if close > 0 else ""


func test_the_symbols_this_file_drives_exist() -> void:
	## FLOOR, own frame: a missing helper aborts the arms below, and one with a prior
	## assert scores PASSING through the abort.
	## NOT a floor on GdSource: it is a const-preloaded script, so a missing `code_of`
	## is a PARSE error and run_tests.sh exits 3 (nothing ran) — louder than any assert
	## could be. CLAUDE.md's call-shape table says flooring it adds dead code, and my
	## first version of this arm proved it by failing to parse.
	assert_true(SoundManager.has_method("audio_liveness_check"),
		"SoundManager.audio_liveness_check is gone — the detector this file defends no longer exists")
	for p in [BS, BM, SM]:
		assert_true(FileAccess.file_exists(str(p)), "%s is gone" % p)


func test_the_detector_still_has_exactly_one_caller() -> void:
	## The premise the whole file rests on. If a second caller appears this arm reds and
	## the reach argument has to be re-made — which is the point, because a second caller
	## changes what "reachable" means.
	var sites: int = 0
	var dir := DirAccess.open("res://src")
	assert_not_null(dir, "SCOPE control: could not walk res://src")
	var stack: Array[String] = ["res://src"]
	while not stack.is_empty():
		var d: String = stack.pop_back()
		for sub in DirAccess.get_directories_at(d):
			stack.append("%s/%s" % [d, sub])
		for f in DirAccess.get_files_at(d):
			if not str(f).ends_with(".gd"):
				continue
			var p: String = "%s/%s" % [d, f]
			if p == SM:
				continue  # its own declaration
			sites += GdSource.code_of(p).count(CALL)
	assert_eq(sites, 1,
		"the detector has %d call sites in src/, not 1. This file's reach argument is about ONE caller; re-derive it." % sites)


func test_the_round_signal_is_actually_emitted() -> void:
	## Link 1. A connect to a signal nothing emits is wiring to nowhere, and no
	## substring match over BattleScene can see that.
	var bm: String = _code(BM)
	assert_true(bm.contains("%s.emit(" % SIGNAL_NAME),
		"BattleManager never emits %s, so the handler it is connected to cannot run" % SIGNAL_NAME)


func test_the_detector_sits_INSIDE_the_handler_that_is_connected() -> void:
	## Link 2+3, and the arm the old substring match could not express.
	var handler: String = _connected_handler()
	assert_ne(handler, "",
		"no `BattleManager.%s.connect(...)` found in BattleScene — the chain is broken at the connect, and a file-wide search for the call would still be green" % SIGNAL_NAME)

	var body: String = _body_of(_code(BS), handler)
	assert_gt(body.length(), 0,
		"the connected handler '%s' has no body in BattleScene — it is named by the connect line and does not exist" % handler)
	assert_true(body.contains(CALL),
		"the detector is NOT inside '%s', the handler the connect line actually names. It may still appear elsewhere in the file, which is exactly what the old `in bs` match accepted." % handler)


func test_CONTROL_the_scoping_really_scopes() -> void:
	## Without this, _body_of could be returning the whole file and every arm above
	## would pass for the wrong reason. A function that must NOT contain the call.
	var code: String = _code(BS)
	var handler: String = _connected_handler()
	var other: String = _body_of(code, "_ready")
	assert_gt(other.length(), 0, "CONTROL: _ready has no body, so the scoping is not being exercised")
	assert_false(other.contains(CALL),
		"CONTROL FAILED: the call appears in _ready's extracted body too, so _body_of is not scoping and the arm above proves nothing")
	assert_ne(other, _body_of(code, handler),
		"CONTROL FAILED: two different functions extracted the same body — _body_of returns the file, not a function")


func test_the_connection_is_released_symmetrically() -> void:
	## Not reach, but the other half of reach over a battle's lifetime: BattleScene is
	## freed and re-instantiated between battles, and a connection that outlives its
	## scene makes the NEXT battle's detector fire against a freed node.
	var code: String = _code(BS)
	assert_true(code.contains("BattleManager.%s.is_connected(" % SIGNAL_NAME),
		"the disconnect is not guarded by is_connected; a double-free path would error instead of skipping")
	assert_true(code.contains("BattleManager.%s.disconnect(" % SIGNAL_NAME),
		"BattleScene connects %s and never disconnects it — stale connections accumulate across battles" % SIGNAL_NAME)
