extends GutTest

## Every DragonCave subclass must route to a music area key SoundManager
## actually matches (2026-07-28).
##
## The four W1 dragon caves never overrode `_get_music_area_id()`, so they
## inherited "cave" -> _start_dungeon_music("medieval") and all four played
## the generic dungeon bed. Meanwhile SoundManager carried four dedicated
## arms ("fire_dragon_cave" etc.) and two composed tracks sat on disk
## (dungeon_dragon_fire 139s, dungeon_dragon_ice 178s) that NOTHING reached
## on the normal path — the only live route was GameLoop._stop_autogrind,
## which passes _current_map_id, so the bespoke themes played solely if you
## started and then stopped an autogrind session inside the cave.
##
## The second half matters as much as the first: play_area_music's default
## arm is _start_overworld_music(), NOT a cave fallback. So a subclass
## returning an unmatched key plays OVERWORLD music inside a dungeon — worse
## than the bug being fixed. That is why this asserts the key RESOLVES
## rather than merely asserting each subclass overrides.

const DUNGEON_DIR := "res://src/maps/dungeons/"
const SOUND_MANAGER := "res://src/audio/SoundManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


## Area keys SoundManager's play_area_music match actually handles, parsed
## from the source rather than listed here — a maintained copy would drift
## the first time someone adds a dungeon.
func _matched_area_keys() -> Array:
	var src := _read(SOUND_MANAGER)
	var start := src.find("func play_area_music")
	assert_true(start > -1, "play_area_music must exist")
	## The bound DELIBERATELY spans two functions: play_area_music defers to
	## _start_area_music_deferred, and the match arms live in the latter. A
	## "tidier" structural bound at the next top-level func cuts the parse at
	## the end of the first one and excludes every arm — tried 2026-07-29, three
	## tests went red immediately.
	##
	## The residual premise, stated rather than asserted: this assumes nothing
	## is inserted between the dispatch and _start_overworld_music. If something
	## is, the parse WIDENS and unresolvable keys start resolving — the guard
	## degrades into a weaker guard rather than a failing one. Reaching a false
	## pass needs two simultaneous changes (an inserted func carrying a quoted
	## key, AND a dungeon returning that exact key), so it is recorded here
	## rather than defended: the cheap structural fix is wrong, and a correct
	## one costs more than the risk.
	var body := src.substr(start)
	var keys: Array = []
	var re := RegEx.new()
	re.compile('"([a-z0-9_]+)"[,:]')
	for m in re.search_all(body):
		keys.append(m.get_string(1))
	return keys


## Does the manifest carry a real, playable entry for this track?
func _manifest_has(track_id: String) -> bool:
	var raw: String = FileAccess.get_file_as_string("res://data/music_manifest.json")
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return false
	var tracks = parsed.get("tracks", parsed)
	if not tracks.has(track_id):
		return false
	return str(tracks[track_id].get("file", "")) != ""


func _dungeon_scripts() -> Array:
	var out: Array = []
	var d := DirAccess.open(DUNGEON_DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".gd"):
			out.append(f)
		f = d.get_next()
	return out


func test_ready_actually_routes_through_the_hook() -> void:
	## The hole in this file's first version, found 2026-07-29 by mutation:
	## every other test here pins SOURCE TEXT. Deleting DragonCave._ready's
	## `SoundManager.play_area_music(_get_music_area_id())` — a plausible
	## "cleanup" refactor — broke dungeon music completely and left all three
	## checks GREEN, because the overrides and the arms are all still spelled
	## correctly. A source pin is a claim about spelling; this file meant to
	## claim behaviour.
	var src := _read(DUNGEON_DIR + "DragonCave.gd")
	var idx := src.find("func _ready")
	assert_true(idx > -1, "DragonCave must define _ready")
	assert_true(src.find("play_area_music(_get_music_area_id())") > -1,
		"DragonCave._ready must feed _get_music_area_id() to play_area_music — without this call every override in this file is dead and the caves fall silent or inherit whatever was playing")


func test_each_dragon_cave_key_resolves_at_runtime() -> void:
	## Behavioural half: the subclasses' keys are fed to the REAL SoundManager
	## and must actually select an area. Text checks can only prove an arm is
	## spelled somewhere; this proves the key reaches it.
	var sm := get_node_or_null("/root/SoundManager")
	if sm == null:
		assert_not_null(sm, "SoundManager unavailable — a skip here reports GREEN having tested nothing")
		return
	var prev: Dictionary = sm.capture_music_state() if sm.has_method("capture_music_state") else {}
	for f in ["FireDragonCave.gd", "IceDragonCave.gd", "LightningDragonCave.gd", "ShadowDragonCave.gd"]:
		var script = load(DUNGEON_DIR + f)
		assert_not_null(script, "%s must load" % f)
		var inst = script.new()
		var key: String = str(inst._get_music_area_id())
		inst.free()
		sm.play_area_music(key)
		await get_tree().create_timer(0.35).timeout
		## Assert the STREAM that ended up on the player, not _current_area.
		## _current_area is assigned from the argument BEFORE the dispatch runs,
		## so `play_area_music("total_garbage")` sets it to "total_garbage" and
		## an equality check against the key passes for ANY string — including
		## one that misses every arm. That was this test's first form, and it
		## proved nothing. The loaded stream is the only thing that differs
		## between "hit the dragon arm" and "fell through to the overworld".
		var stream = sm._music_player.stream if sm._music_player else null
		assert_not_null(stream, "%s: nothing is playing after play_area_music(\"%s\")" % [f, key])
		if stream == null:
			continue
		var playing_path: String = str(stream.resource_path)
		## Expect the SPECIFIC track, derived from the manifest. Accepting
		## "dungeon_dragon OR dungeon_medieval" for every cave — this test's
		## previous form — was vacuous for exactly the defect it exists to
		## catch: Fire and Ice falling back to the generic medieval bed IS the
		## bug that was fixed here, and the loose form passed on it.
		##
		## Lightning and Shadow have no composed track yet, so dungeon_medieval
		## is their CORRECT result. That expectation is derived rather than
		## listed, so it self-destructs: the day those OGGs land, this demands
		## their own track without anyone remembering to come back.
		var own_track: String = "dungeon_dragon_" + key.replace("_dragon_cave", "")
		var expected: String = own_track if _manifest_has(own_track) else "dungeon_medieval"
		assert_true(playing_path.find(expected) > -1,
			"%s routed to \"%s\" and should be playing %s, but the player is on %s. Either the key missed every arm (falling to _start_overworld_music — overworld music inside a dungeon) or it fell back to the generic bed, which is the original defect" % [f, key, expected, playing_path])
	if not prev.is_empty() and sm.has_method("restore_music_state"):
		sm.restore_music_state(prev)


func test_dragon_cave_areas_still_resolve_to_the_medieval_battle_suffix() -> void:
	## Second-order coupling, found after the routing fix shipped: making the
	## caves override _get_music_area_id() changed _current_area from "cave" to
	## "fire_dragon_cave" — and _get_current_world_suffix() reads _current_area
	## to pick BATTLE music. It stayed correct only because that match already
	## carried the four dragon ids, written before anything ever set them.
	## Drop them from that arm and every fight inside a dragon cave takes the
	## default suffix instead of medieval.
	var sm := get_node_or_null("/root/SoundManager")
	if sm == null:
		assert_not_null(sm, "SoundManager unavailable — a skip here reports GREEN having tested nothing")
		return
	var prev: Dictionary = sm.capture_music_state() if sm.has_method("capture_music_state") else {}
	## The cache must be poisoned first. _get_current_world_suffix's default arm
	## returns the CACHED _current_world_suffix, which is "medieval" at rest —
	## so asserting "medieval" against a clean cache passes whether the dragon
	## arm matched or fell through, and cannot tell the two apart. Seeding a
	## DIFFERENT suffix makes the assertion mean what it says.
	var cached_before: String = str(sm._current_world_suffix)
	for key in ["fire_dragon_cave", "ice_dragon_cave", "lightning_dragon_cave", "shadow_dragon_cave"]:
		sm._current_world_suffix = "abstract"
		sm._current_area = key
		assert_eq(str(sm._get_current_world_suffix()), "medieval",
			"\"%s\" must resolve to the medieval battle suffix — the dungeon-music override feeds this, so a missing arm here gives dragon-cave battles the wrong world's music" % key)
	sm._current_world_suffix = cached_before
	if not prev.is_empty() and sm.has_method("restore_music_state"):
		sm.restore_music_state(prev)


func test_positive_control_parser_sees_the_dispatch() -> void:
	## A sweep that silently parsed nothing would make every assertion below
	## vacuously true.
	var keys := _matched_area_keys()
	assert_gt(keys.size(), 15,
		"parsed too few area keys from play_area_music — the parser broke, so an empty offender list proves nothing")
	assert_true(keys.has("fire_dragon_cave"),
		"positive control: the fire dragon arm must be visible to the parser")
	assert_gt(_dungeon_scripts().size(), 8, "expected to find the dungeon scripts on disk")


func test_every_dungeon_music_key_resolves() -> void:
	var keys := _matched_area_keys()
	var offenders: Array = []
	for f in _dungeon_scripts():
		var src := _read(DUNGEON_DIR + f)
		var idx := src.find("func _get_music_area_id")
		if idx == -1:
			continue  # no override — handled by test_non_medieval_dungeons_must_override
		var body := src.substr(idx, 220)
		var re := RegEx.new()
		re.compile('return\\s+"([a-z0-9_]+)"')
		var m := re.search(body)
		if m == null:
			continue
		var key := m.get_string(1)
		if not keys.has(key):
			offenders.append("%s returns \"%s\" — unmatched, so play_area_music falls to _start_overworld_music() and plays OVERWORLD music inside a dungeon" % [f, key])
	assert_eq(offenders, [], "\n".join(offenders))


## Dungeons whose inherited "cave" default is CORRECT, each on its own merits
## rather than as an exemption: both are World 1 and medieval, which is exactly
## what "cave" resolves to. A W2+ dungeon can never qualify.
const MEDIEVAL_BY_LOCATION := {
	"WhisperingCave.gd": "W1 medieval cave — \"cave\" is its true area",
	"CastleHarmonia.gd": "W1 medieval — inherits the medieval bed correctly",
	"DragonCave.gd": "the base class itself; defines the default",
	"BossTrigger.gd": "not a placed map",
}


func test_non_medieval_dungeons_must_override_the_music_key() -> void:
	## The hole that let the Calibrant arena through (2026-08-05).
	##
	## test_every_dungeon_music_key_resolves `continue`s past any file with no
	## override, on a comment saying the dragon-cave test covers it. That test
	## covers the four NAMED W1 caves. A NEW DragonCave subclass with no
	## override was therefore covered by nothing — and cowir-main's VertexApex,
	## the World 6 abstract-world finale, landed in exactly that gap: it
	## inherits "cave", which plays the generic cave bed AND resolves to the
	## "medieval" battle suffix. The last fight of a six-world game scored to
	## World 1.
	##
	## The predicate is not "must override" — it is "a dungeon outside medieval
	## World 1 must SAY where it is." The four entries above pass because they
	## genuinely are medieval, not because they are listed; a W2+ dungeon cannot
	## join them by being added to the dict, because the assertion below is what
	## fails and the dict only documents the four that were already correct.
	var offenders: Array = []
	for f in _dungeon_scripts():
		if MEDIEVAL_BY_LOCATION.has(f):
			continue
		var src := _read(DUNGEON_DIR + f)
		if src.find("func _get_music_area_id") > -1:
			continue
		offenders.append("%s has no _get_music_area_id() override, so it inherits \"cave\" — the generic cave bed, and the MEDIEVAL battle suffix. Every non-medieval dungeon in the game overrides (industrial_dungeon, abstract_dungeon, digital_dungeon, steampunk_dungeon, suburban_dungeon, the four dragon caves); if this one is genuinely W1 medieval, add it to MEDIEVAL_BY_LOCATION with the reason" % f)
	assert_eq(offenders.size(), 0, "\n".join(offenders))


func test_the_medieval_exemptions_are_all_really_medieval() -> void:
	## Keeps the dict above from becoming a silencer. Every entry must still be
	## a file that exists and still lack an override — an entry that has since
	## gained one is stale and must be pruned, exactly the decay that left the
	## orphan-music allowlist 100% dead while reporting green.
	for f in MEDIEVAL_BY_LOCATION:
		var path: String = DUNGEON_DIR + f
		assert_true(FileAccess.file_exists(path),
			"MEDIEVAL_BY_LOCATION names %s, which no longer exists — prune it" % f)
		if not FileAccess.file_exists(path):
			continue
		if f == "DragonCave.gd":
			continue  # the base class DEFINES the default; it necessarily has one
		var src: String = FileAccess.get_file_as_string(path)
		assert_true(src.find("func _get_music_area_id") == -1,
			"%s now overrides _get_music_area_id, so its MEDIEVAL_BY_LOCATION entry is stale — remove it, or the entry will silently excuse a future regression" % f)


func test_w1_dragon_caves_route_to_their_own_theme() -> void:
	## The regression proper. Each must override, and to its own arm.
	var expected := {
		"FireDragonCave.gd": "fire_dragon_cave",
		"IceDragonCave.gd": "ice_dragon_cave",
		"LightningDragonCave.gd": "lightning_dragon_cave",
		"ShadowDragonCave.gd": "shadow_dragon_cave",
	}
	var keys := _matched_area_keys()
	for f in expected:
		var src := _read(DUNGEON_DIR + f)
		assert_true(src.find("func _get_music_area_id") > -1,
			"%s must override _get_music_area_id — inheriting \"cave\" plays the generic medieval bed and its own composed theme never reaches the player" % f)
		assert_true(src.find('return "%s"' % expected[f]) > -1,
			"%s must route to \"%s\"" % [f, expected[f]])
		assert_true(keys.has(expected[f]),
			"SoundManager must carry an arm for \"%s\"" % expected[f])
