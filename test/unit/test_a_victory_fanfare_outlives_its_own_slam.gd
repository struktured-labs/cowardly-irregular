extends GutTest

## The VICTORY banner's impact slam played on _battle_player — the same voice carrying the victory
## fanfare it lands on. Measured on struktured's 2026-10-12 log: victory_stinger 23 plays, and
## 23 of 23 were immediately followed by victory_slam on that channel. 100%, not a sample.
##
## ⛔ THE COST IS NOT UNIFORM AND IT IS WORST WHERE THE PLAYER ACTUALLY IS. The slam waits for the
## victory bed's downbeat (BattleResultsDisplay), but victory_medieval and victory_suburban have
## `agree: false` — no measurement survived their estimator spread (665/784 ms) — so
## seconds_until_victory_downbeat() answers -1.0, the await is SKIPPED, and both cues play in ONE
## frame. W1 and W2, the only worlds a player reaches today, never heard the fanfare at all.
##
## Energy lost to the cut, measured on the asset (50% of the stinger is spent by 50 ms):
##   no wait (medieval/suburban)  100.0%      116 ms (digital)      24.4%
##    34 ms (abstract)             63.7%      188 ms (victory)       6.5%
##    57 ms (industrial)           46.8%      243 ms (steampunk)     3.2%
##
## ✅ NO CLIPPING RISK, because the question is obvious and the raw number is alarming: summing the
## two files at unity peaks +3.01 dBFS at the 34 ms offset. Both voices run at SFX_BATTLE_BASE_DB,
## so the worst real case is -2.99 dBFS. The arithmetic is here so nobody re-derives the raw figure
## and reads it as a reason to revert.
##
## 🔑 ELEVENTH INSTANCE OF ONE CLASS, and the fix direction follows .693's rule rather than
## 09-11's: the displacer has ONE call site, so the displacer moves. _spawn_impact is the only
## caller, where _advance_dialogue's blip had many and the victim had to move instead.

const SOUND_MANAGER := "res://src/audio/SoundManager.gd"
const OVERLAY := "res://src/battle/VictoryOverlay.gd"
const DOWNBEATS := "res://data/victory_downbeats.json"
const MANIFEST := "res://data/sfx_manifest.json"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")

const SLAM := "victory_slam"
const FANFARE := "victory_stinger"


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _overlay_code() -> String:
	var code: String = GdSource.code_of(OVERLAY)
	assert_true(code.contains("func _spawn_impact"),
		"VOID: VictoryOverlay's code did not survive the comment strip — an over-strip and a correct strip are the same green")
	return code


## ⛔ THE FLOOR, derived from what this file actually reaches on SoundManager rather than hand-listed.
## Without it an arm whose first assert precedes its first SoundManager touch goes vacuous on a
## rename: the abort kills the function and a prior passing assert leaves the file green.
func test_every_sound_manager_symbol_this_file_reaches_exists() -> void:
	var src: String = GdSource.code_of("res://test/unit/test_a_victory_fanfare_outlives_its_own_slam.gd")
	assert_gt(src.length(), 500, "VOID: could not read my own source (%d chars)" % src.length())
	## ⛔ NEUTRALISE STRING LITERALS FIRST. Without this the derivation reads `SoundManager.gd`
	## out of my own path constants and reports a symbol named `gd` — the regex inventing a
	## subject from text shaped like member access, which CLAUDE.md warns is wrong in BOTH
	## directions. Caught by simulating this arm before running it, not by the run.
	## ⚠️ AND THE CLASS MUST EXCLUDE \n: [^"] is a NEGATED class, so it matches newlines and one
	## quote pair spanning two lines swallows the real code between them. My first version of
	## this line derived ZERO symbols for exactly that reason — the fix for the literal trap
	## introduced a second, quieter one, and only re-simulating caught it.
	var strings := RegEx.create_from_string("\"[^\"\\n]*\"")
	var code: String = strings.sub(src, "\"\"", true)
	var reached: Array[String] = []
	## ⛔ BOTH RECEIVERS. The runtime arm reaches SoundManager through a LOCAL `sm`, and a floor
	## deriving only `SoundManager.` is silent about every one of those — CLAUDE.md's
	## "a derived floor is scoped to the receiver its derivation names". Those reaches are
	## INSTANCE reaches, so they abort at runtime, and that arm has passing CONTROL asserts
	## above them: the abort would leave this file GREEN. Found by deriving the reaches, not
	## by reading the arms.
	var re := RegEx.create_from_string("(?:SoundManager|sm)\\.([A-Za-z_][A-Za-z0-9_]*)")
	for m in re.search_all(code):
		var name: String = m.get_string(1)
		if not reached.has(name):
			reached.append(name)
	assert_gt(reached.size(), 1, "VOID: the derivation found %d symbols, so this floor is about nothing" % reached.size())
	## ⛔ DECIDE MEMBERSHIP FROM THE SOURCE, NOT FROM THE LIVE OBJECT. `_sfx_manifest` is a
	## `static var` (SoundManager:152), and whether `in` or `get()` sees a static var through an
	## autoload instance is an engine semantic I cannot settle without a run — a floor that depends
	## on it can RED ON A CLEAN TREE, which is the failure I already fixed once in this arm. A
	## declaration scan has no such dependency and is verifiable outside the engine.
	var sm_src: String = GdSource.code_of(SOUND_MANAGER)
	assert_gt(sm_src.length(), 1000, "VOID: SoundManager's source did not survive the strip")
	var missing: Array[String] = []
	for name in reached:
		var decl := RegEx.create_from_string("(?m)^(?:static[ \t]+)?(?:var|func|const)[ \t]+%s\\b" % name)
		if decl.search(sm_src) == null and not SoundManager.has_method(name):
			missing.append(name)
	assert_eq(missing, [],
		"this file drives SoundManager symbols that no longer exist, so every arm touching them aborts and can score green: %s" % [missing])


func test_the_slam_has_its_own_voice_and_it_is_not_the_battle_channel() -> void:
	## ⛔ THE LOAD-BEARING ARM. _play_battle_on falls back to play_battle(sound_key) when its player
	## is null, so a field that is declared but never CREATED restores the defect in full silence —
	## the routing arm below would still pass.
	assert_true("_victory_player" in SoundManager,
		"SoundManager has no _victory_player, so play_victory_sfx falls back to _battle_player and the slam replaces the fanfare again")
	assert_not_null(SoundManager._victory_player,
		"_victory_player is declared but never instantiated — _play_battle_on's null arm sends the slam straight back to play_battle, which is the original bug")
	assert_true(SoundManager._victory_player != SoundManager._battle_player,
		"the victory voice IS the battle voice, so the slam still cuts whatever the fanfare is playing")


func test_the_overlay_routes_the_slam_to_that_voice() -> void:
	## The control for the OLD routing: play_battle("victory_slam") is what shipped, and it must
	## not be what the overlay calls.
	var code: String = _overlay_code()
	## The key is chosen by _slam_key() since the S-rank slam (2026-10-30), so the call takes a variable;
	## either form routes, and the selector's default is grounded at runtime rather than spelled.
	var routed_literal: bool = code.contains('play_victory_sfx("%s")' % SLAM)
	var routed_selected: bool = code.contains("play_victory_sfx(slam)") and code.contains("var slam := _slam_key()")
	assert_true(routed_literal or routed_selected,
		"VictoryOverlay no longer routes the slam through play_victory_sfx, so it is back on the shared battle voice")
	if routed_selected:
		var ov = load(OVERLAY).new()
		ov._one_shot_rank = ""
		assert_eq(ov._slam_key(), SLAM, "with no one-shot rank the overlay selects '%s', not the ordinary slam" % ov._slam_key())
		ov.free()
	assert_false(code.contains("play_battle(slam)"), "the selected slam is played through play_battle — the shipped defect, one variable over")
	assert_false(code.contains('play_battle("%s")' % SLAM),
		"the overlay plays the slam through play_battle again — that is the shipped defect verbatim, and it fails silently because the slam is still audible; only the fanfare under it dies")
	## ⛔ THE NAME IS NOT THE METHOD. The two asserts above certify SPELLING in the overlay's own
	## source and say nothing about whether the thing it names exists — rename play_victory_sfx in
	## SoundManager alone and both still pass while every victory errors at runtime. Simulating
	## this file's arms before running them is what surfaced the gap; the mutation would have
	## reported green.
	assert_true(SoundManager.has_method("play_victory_sfx"),
		"VictoryOverlay calls SoundManager.play_victory_sfx but SoundManager has no such method, so every victory raises at runtime while the routing asserts above stay green")


func test_the_slam_lands_on_its_own_voice_and_the_fanfare_survives_it() -> void:
	## ⛔ THE ARM THAT ACTUALLY DRIVES THE DEFECT. Every other arm reads SOURCE TEXT or node
	## identity, and both are blind to a RE-ROUTE: make _play_battle_on ignore its player argument
	## and _victory_player is still a non-null, distinct node, so the routing and identity asserts
	## pass while the slam is back on the fanfare's channel. This is the shape
	## test_a_storm_in_battle_is_heard_not_just_seen proved for the thunder, whose own comment says
	## it: "the dedicated voice must be the one holding the cue." Found by asking which mutant could
	## change the value each arm reads (cowir-ai), not by re-reading the arms.
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: the SoundManager autoload must be present")
	if sm == null:
		return
	assert_true(sm._sfx_manifest.has(SLAM), "CONTROL: %s must be in the manifest" % SLAM)
	assert_true(sm._sfx_manifest.has(FANFARE), "CONTROL: %s must be in the manifest" % FANFARE)

	## The fanfare first, exactly as BattleScene plays it: play_battle -> _battle_player.
	sm.play_battle(FANFARE)
	var held: AudioStream = sm._battle_player.stream
	assert_not_null(held,
		"CONTROL: play_battle left _battle_player empty, so there is no fanfare for the slam to cut and every assert below is about nothing")

	## ⚠️ WHY THIS CLEAR IS HERE, stated accurately because my first version of this comment named
	## the wrong clause: the two cues have DIFFERENT KEYS and the cooldown is per key, so the
	## fanfare's stamp CANNOT suppress the slam — the sequence in this arm needs no clear at all.
	## What it guards is cross-test hygiene: _sfx_cooldowns is an instance var on the autoload
	## (SoundManager:157, not static, but one instance per process), so a `victory_slam` stamp left
	## by any earlier test within SFX_MIN_INTERVAL_MS would suppress this play and the arm would
	## pass having asserted nothing. Defensive, and cheap — but not the mechanism I first claimed.
	sm._sfx_cooldowns.clear()
	sm.play_victory_sfx(SLAM)

	assert_not_null(sm._victory_player.stream,
		"play_victory_sfx left _victory_player empty — either %s failed to load, or the slam is being routed to a different player (an argument-ignoring _play_battle_on passes every other arm in this file)" % SLAM)
	assert_eq(sm._battle_player.stream, held,
		"the slam REPLACED the fanfare on _battle_player — this is the shipped defect, and it is the only arm here that would notice a re-route rather than a renamed symbol")


func test_the_fanfare_itself_stays_on_the_battle_voice() -> void:
	## SCOPE. Moving the fanfare too would make this file's whole premise stale, and the fix would
	## be defended by a note describing a routing nobody uses.
	var code: String = GdSource.code_of("res://src/battle/BattleScene.gd")
	assert_gt(code.length(), 1000, "VOID: BattleScene's code did not survive the strip")
	assert_true(code.contains("play_battle(BattleManager.victory_cue_for("),
		"the fanfare no longer reaches play_battle, so this file no longer describes the pair it guards — re-read which voice each cue uses before trusting any arm here")


func test_an_agreed_downbeat_is_still_shorter_than_the_fanfare() -> void:
	## ⚠️ THIS ARM GUARDS THE PREMISE, NOT A VALUE. It asserts only that the overlap is REAL — that
	## some agreed downbeat lands inside the fanfare. It does not pin any ms figure, because a
	## re-measurement is a correct change and a ratchet on 188 would red on it.
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DOWNBEATS))
	assert_true(parsed is Dictionary, "VOID: victory_downbeats.json did not parse, so this arm is about nothing")
	if not (parsed is Dictionary):
		return
	var rows: Dictionary = parsed as Dictionary
	assert_gt(rows.size(), 2, "VOID: %d downbeat rows, too few to say anything" % rows.size())
	var fanfare_len: float = _length_of(FANFARE)
	assert_gt(fanfare_len, 0.0, "VOID: %s did not decode, so no comparison is possible" % FANFARE)
	var agreed: Array = []
	var unmeasured: Array = []
	for k in rows.keys():
		var e = rows[k]
		if not (e is Dictionary):
			continue
		if not bool((e as Dictionary).get("agree", false)) or (e as Dictionary).get("downbeat_ms", null) == null:
			unmeasured.append(str(k))
			continue
		agreed.append(float((e as Dictionary)["downbeat_ms"]) / 1000.0)
	## Every row lands in exactly one bucket and they must sum, so a row cannot vanish unnoticed.
	assert_eq(agreed.size() + unmeasured.size(), rows.size(),
		"%d agreed + %d unmeasured != %d rows — a row is being discarded into a void" % [agreed.size(), unmeasured.size(), rows.size()])
	var inside := 0
	for w in agreed:
		if w < fanfare_len:
			inside += 1
	assert_gt(inside, 0,
		"no agreed downbeat now lands inside the %.2fs fanfare, and the unmeasured beds (%s) are the only remaining overlap — the premise of this file changed, so re-read whether the dedicated voice is still earning its place rather than deleting the arm" % [fanfare_len, unmeasured])


func test_both_cues_are_authored_at_all() -> void:
	## The VOID floor under every arm above: if either key leaves the manifest, the overlay's
	## `has(SLAM)` guard goes false, nothing plays, and a routing assertion is about dead code.
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(parsed is Dictionary and (parsed as Dictionary).has("sfx"),
		"VOID: the sfx manifest did not parse")
	if not (parsed is Dictionary):
		return
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {})
	for k in [SLAM, FANFARE]:
		assert_true(sfx.has(k), "%s has left the manifest, so this file guards a pair that cannot play" % k)
	assert_gt(_length_of(SLAM), 0.0, "%s does not decode" % SLAM)


func _length_of(key: String) -> float:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not (parsed is Dictionary):
		return -1.0
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {})
	var e = sfx.get(key, null)
	if not (e is Dictionary):
		return -1.0
	var res: String = str((e as Dictionary).get("file", ""))
	if res == "" or not ResourceLoader.exists(res):
		return -1.0
	## MEASURE WITH THE CONSUMER'S OWN ACCESSOR — the engine plays what get_length() describes.
	var stream = load(res) as AudioStream
	return stream.get_length() if stream != null else -1.0
