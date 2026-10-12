extends GutTest

## data/victory_downbeats.json was measured 2026-08-17 "so the overlay's title slam could land ON
## the downbeat". The slam was built the next day and never read it: 0 src/ consumers, 0 mentions
## of `downbeat` in the victory path, while the guard beside the pack kept the numbers honest
## against re-encodes. struktured authorised the wire 2026-10-12.
##
## Two of the seven beds have NO agreed downbeat (spread_ms 665 medieval / 784 suburban), and
## medieval is W1's — so "unmeasured keeps today's timing" is the common case, not the edge, and
## it gets a direction of its own below.

const VO := preload("res://src/battle/VictoryOverlay.gd")
const DOWNBEATS := "res://data/victory_downbeats.json"
const SELF_PATH := "res://test/unit/test_the_victory_slam_waits_for_the_downbeat.gd"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## An agreed bed, and a bed whose estimators disagreed — both derived, so a re-measure moves them.
var _agreed := ""
var _unmeasured := ""
var _saved_results: Dictionary = {}
var _saved_serial: int = 0


class FakeScene extends Node:
	func _tier() -> int:
		return 0


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _rows() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DOWNBEATS))
	return (parsed if parsed is Dictionary else {}) as Dictionary


func before_each() -> void:
	_saved_results = BattleManager._battle_results
	_saved_serial = int(BattleManager.battle_serial)
	_agreed = ""
	_unmeasured = ""
	for k in _rows().keys():
		var r: Dictionary = _rows()[k]
		if bool(r.get("agree", false)) and r.get("downbeat_ms", null) != null:
			if _agreed == "":
				_agreed = str(k)
		elif _unmeasured == "":
			_unmeasured = str(k)


func after_each() -> void:
	## In after_each, not inline: an aborting assert would otherwise strand BattleManager's
	## results on every other file in the same process.
	BattleManager._battle_results = _saved_results
	BattleManager.battle_serial = _saved_serial
	var sm: Node = _sm()
	if sm != null:
		sm.stop_music()


func test_an_agreed_bed_reports_its_measured_downbeat() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	assert_ne(_agreed, "", "CONTROL: no bed has an agreed downbeat — every arm below would be vacuously -1.0")
	var want: float = float(_rows()[_agreed]["downbeat_ms"]) / 1000.0
	sm.play_music(_agreed, true)
	var got: float = sm.seconds_until_victory_downbeat()
	## Derived from the pack, not a pinned constant: the wait is the measured offset less however
	## far the bed has already played, so it may be under `want` and must never exceed it.
	assert_gt(got, 0.0,
		"%s has an agreed downbeat of %.3fs and the wait came back %.4f — the slam will not wait, so it lands off the beat" % [_agreed, want, got])
	assert_lte(got, want,
		"the wait (%.4f) exceeds the measured offset (%.3f) for %s — playback position is not being subtracted" % [got, want, _agreed])
	assert_gt(got, want - 0.25,
		"the wait (%.4f) is far below the measured offset (%.3f) — the bed had already played past the downbeat before the overlay asked" % [got, want])


func test_a_bed_whose_estimators_disagreed_does_not_wait() -> void:
	## The W1 case. A 665ms spread means the tool does not trust its own answer, and a slam synced
	## to an untrusted downbeat lands visibly off — worse than today. -1.0 is the honest result.
	var sm: Node = _sm()
	if sm == null:
		return
	assert_ne(_unmeasured, "", "CONTROL: every bed now has an agreed downbeat — this arm has no subject, delete it")
	var r: Dictionary = _rows()[_unmeasured]
	assert_true(not bool(r.get("agree", false)) or r.get("downbeat_ms", null) == null,
		"CONTROL: %s was picked as unmeasured but reads agree=%s downbeat_ms=%s" % [_unmeasured, r.get("agree"), r.get("downbeat_ms")])
	sm.play_music(_unmeasured, true)
	assert_eq(sm.seconds_until_victory_downbeat(), -1.0,
		"%s has no agreed downbeat and still produced a wait — the slam would sync to a number the measurement tool rejected" % [_unmeasured])


func test_the_wait_accounts_for_how_far_the_bed_has_played() -> void:
	## Deterministic via seek, on purpose. The timing version of this arm read 0.0027s of progress
	## on one run and 0.0933s on another for the same bed, so it would have been flaky in a fold.
	var sm: Node = _sm()
	if sm == null:
		return
	var want: float = float(_rows()[_agreed]["downbeat_ms"]) / 1000.0
	var seek_to: float = want * 0.5
	sm.play_music(_agreed, true)
	sm._music_player.seek(seek_to)
	var got: float = sm.seconds_until_victory_downbeat()
	assert_almost_eq(got, want - seek_to, 0.02,
		"seeked %.3fs into %s, whose downbeat is at %.3fs, so the wait should be about %.3fs and came back %.4f — the playback position is not being subtracted, and the overlay would hold a fixed delay however late it asked" % [seek_to, _agreed, want, want - seek_to, got])


func test_the_lookup_follows_the_BED_not_the_REQUEST() -> void:
	## The real game path. play_music("victory") is generic: _current_music stays "victory" while
	## the bed loaded is victory_<world>. The pack holds BOTH keys with DIFFERENT answers — row
	## `victory` agrees at 188ms, row `victory_medieval` does not agree at all — so a lookup keyed
	## off the request returns a wait for a bed that is not playing. Every other arm here uses
	## exact=true and cannot tell the two strategies apart.
	var sm: Node = _sm()
	if sm == null:
		return
	var rows: Dictionary = _rows()
	assert_true(rows.has("victory"), "CONTROL: the generic row must exist for this arm to discriminate")
	sm.play_music("victory")
	var bed: String = ""
	if sm._music_player != null and sm._music_player.stream != null:
		bed = str(sm._music_player.stream.resource_path).get_file().get_basename()
	assert_ne(bed, "", "CONTROL: nothing loaded, so this arm cannot compare bed against request")
	if bed == "victory":
		pass_test("the world resolved to the generic bed, so request and bed agree here — nothing to discriminate")
		return
	var request_row: Dictionary = rows.get("victory", {})
	var bed_row: Dictionary = rows.get(bed, {})
	var request_would_wait: bool = bool(request_row.get("agree", false)) and request_row.get("downbeat_ms", null) != null
	var bed_should_wait: bool = bool(bed_row.get("agree", false)) and bed_row.get("downbeat_ms", null) != null
	if request_would_wait == bed_should_wait:
		pass_test("request row and bed row (%s) happen to agree on whether to wait — no discrimination available" % bed)
		return
	var got: float = sm.seconds_until_victory_downbeat()
	assert_eq(got > 0.0, bed_should_wait,
		"play_music(\"victory\") loaded %s, whose row says wait=%s, but the answer was %.4f — the lookup is following _current_music (\"victory\") instead of the bed actually playing" % [bed, bed_should_wait, got])


func test_a_bed_that_is_not_a_victory_fanfare_does_not_wait() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	assert_false(_rows().has("battle_medieval"), "CONTROL: battle_medieval must stay absent from the pack")
	sm.play_music("battle_medieval", true)
	assert_eq(sm.seconds_until_victory_downbeat(), -1.0,
		"a non-victory bed produced a downbeat wait — the lookup is matching something it should not")


func test_a_procedural_bed_does_not_wait() -> void:
	## The guard I wrote for a shape I had not driven. No bed resolves procedurally on a complete
	## install — all six keys I probed load a real file — but a generator stream carries no
	## resource_path, and the accessor keys off that path. Built with SoundManager's OWN production
	## constructor rather than a hand-rolled stand-in, so this is a faithful input, not a fixture
	## of the subject (cowir-ai's point: I had derived every mutation from code I wrote rather than
	## from shapes it could meet).
	##
	## ⚠️ This arm pins the BEHAVIOUR, not a line. It stayed green when the explicit empty-path
	## guard was removed, because "" basenames to "" and no row is keyed by it — so the guard was
	## redundant and is gone. The arm still reds if the lookup ever starts answering for a bed that
	## is not playing, which is the thing worth defending.
	var sm: Node = _sm()
	if sm == null:
		return
	sm.play_music(_agreed, true)
	assert_gt(sm.seconds_until_victory_downbeat(), 0.0, "CONTROL: a real wait must be pending before we swap the stream")
	var gen = sm._procedural_generator_for(sm._music_player, 44100)
	assert_not_null(gen, "CONTROL: the production generator constructor returned nothing")
	sm._music_player.stream = gen
	assert_eq(str(sm._music_player.stream.resource_path), "", "CONTROL: a generator must carry no resource_path, which is what the guard keys on")
	assert_eq(sm.seconds_until_victory_downbeat(), -1.0,
		"a procedural bed produced a downbeat wait — the accessor is reading a row for a file that is not playing, because an empty resource_path fell through to the lookup")


func test_silence_does_not_wait() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	sm.stop_music()
	assert_eq(sm.seconds_until_victory_downbeat(), -1.0,
		"nothing is playing and a wait was still reported — the overlay would hold for a bed that does not exist")


func test_build_itself_no_longer_holds() -> void:
	## The hold was INSIDE build() in the first version of this change, which left a node named
	## VictoryResults in the tree empty for up to 243ms while 14 src sites key on its presence
	## (cowir-battle/cowir-main, 2026-10-12). build() must be a plain function again: with an
	## agreed bed playing it has to produce its children synchronously.
	var sm: Node = _sm()
	if sm == null:
		return
	assert_true(BattleJuice.flag("victory_flourish"),
		"CONTROL: victory_flourish is off, so nothing below would hold even if build() still did")
	var fake := FakeScene.new()
	add_child_autofree(fake)
	sm.play_music(_agreed, true)
	assert_gt(sm.seconds_until_victory_downbeat(), 0.0, "CONTROL: a hold must be pending for this arm to mean anything")
	var ov = VO.new()
	fake.add_child(ov)
	ov.build({"char_results": []}, fake)
	var built: int = ov.get_child_count()
	ov.queue_free()
	assert_gt(built, 0,
		"build() returned having built nothing while a downbeat hold was pending — the wait is back inside build(), so an empty VictoryResults node can enter the tree")


func test_no_empty_results_node_ever_enters_the_tree() -> void:
	## The invariant the restructure buys, driven rather than read: during the hold there must be
	## NO VictoryResults node at all, and when it arrives it must already be populated.
	var sm: Node = _sm()
	if sm == null:
		return
	BattleManager._battle_results = {"char_results": []}
	var fake := FakeScene.new()
	add_child_autofree(fake)
	var brd := BattleResultsDisplay.new(fake)

	sm.play_music(_agreed, true)
	assert_gt(sm.seconds_until_victory_downbeat(), 0.0, "CONTROL: no hold pending, so the window below does not exist")
	brd.show_victory_results()
	var during: Node = fake.get_node_or_null("VictoryResults")
	var during_desc: String = "absent" if during == null else "present with %d children" % during.get_child_count()
	assert_null(during,
		"a VictoryResults node is %s DURING the downbeat hold — 14 src sites read its presence as 'results are showing', and a confirm press in that window lands on an empty overlay" % during_desc)
	await get_tree().create_timer(0.5, true, false, true).timeout
	var arrived: Node = fake.get_node_or_null("VictoryResults")
	assert_not_null(arrived, "the overlay never arrived after the hold — the wait swallowed the victory screen")
	if arrived != null:
		assert_gt(arrived.get_child_count(), 0, "the overlay arrived EMPTY after the hold")
		arrived.free()

	## And with nothing held it must be there at once, which is today's behaviour unchanged.
	sm.stop_music()
	sm.play_music(_unmeasured, true)
	brd.show_victory_results()
	var immediate: Node = fake.get_node_or_null("VictoryResults")
	assert_not_null(immediate, "with no agreed downbeat the overlay must appear immediately, as it does on main")
	if immediate != null:
		assert_gt(immediate.get_child_count(), 0, "the overlay appeared EMPTY with no hold pending")
		immediate.free()


func test_agree_and_a_number_arrive_together() -> void:
	## BOTH directions, and the second one is why the accessor checks `agree` at all.
	##
	## Today they are REDUNDANT: every agree=false row also has downbeat_ms null, so bypassing the
	## agree check still returns -1.0 on the null. Measured — mutating the agree check away leaves
	## this file 9/9 green, and I am not faking a row to manufacture a red. What this arm does
	## instead is pin the invariant that MAKES them redundant, so the day a re-measure emits a
	## value it does not trust, this reds and says the agree check just became load-bearing.
	var missing_number: Array = []
	var untrusted_number: Array = []
	for k in _rows().keys():
		var r: Dictionary = _rows()[k]
		var agrees: bool = bool(r.get("agree", false))
		var has_number: bool = r.get("downbeat_ms", null) != null
		if agrees and not has_number:
			missing_number.append(str(k))
		if not agrees and has_number:
			untrusted_number.append(str(k))
	assert_gt(_rows().size(), 0, "CONTROL: the pack read back empty")
	assert_eq(missing_number.size(), 0,
		"rows claim agree=true with no downbeat_ms, so the overlay would wait on a null: %s" % str(missing_number))
	assert_eq(untrusted_number.size(), 0,
		"rows carry a downbeat_ms the measurement does NOT agree on: %s — the accessor's `agree` check is now the only thing keeping the slam off an untrusted number, and it needs a test that fails without it" % str(untrusted_number))


func test_every_member_this_file_reaches_for_still_exists() -> void:
	## DERIVED from this file's own source so it cannot go stale against the reaches above it.
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	var stripped := ""
	for l in GdSource.code_of(SELF_PATH).split("\n"):
		if not l.strip_edges().begins_with("#"):
			stripped += l + "\n"
	var reached := {}
	var re := RegEx.create_from_string("\\bsm\\.([A-Za-z_][A-Za-z0-9_]*)")
	for m in re.search_all(stripped):
		reached[m.get_string(1)] = true
	assert_gt(reached.size(), 0, "CONTROL: derived no sm. reaches — the scan is broken")
	for name in reached.keys():
		assert_true(sm.has_method(str(name)) or sm.get(str(name)) != null,
			"SoundManager has no member `%s`, which this file drives" % [str(name)])
	assert_true(VO.new().has_method("build"), "VictoryOverlay.build is gone — every reach arm above is about it")
