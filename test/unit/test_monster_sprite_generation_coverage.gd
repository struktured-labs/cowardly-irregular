extends GutTest

## MonsterSprites (5,733 lines) + MonsterSpritesExtra (1,704) had ZERO tests naming either
## file — the 4th-largest source in the game, generating the art a player stares at every
## battle. It is pure static generation with no scene tree, so it is unusually testable for
## its size; nothing was stopping this except nobody having done it.
##
## Creator names are DISCOVERED FROM SOURCE, not listed here: a hand-written roster silently
## stops covering whatever gets added next, which is the failure mode this file exists to end.

const SRC_MAIN := "res://src/battle/sprites/MonsterSprites.gd"
const SRC_EXTRA := "res://src/battle/sprites/MonsterSpritesExtra.gd"
## Static funcs can't be reached through the class_name — and preload() of a script that
## DECLARES a class_name resolves to that class at parse time, so it fails identically.
## Runtime load() returns a Resource whose type the parser doesn't know, which is what
## allows has_method()/call() on the static surface.
const REQUIRED_ANIMS := ["idle", "attack", "hit", "defeat"]


var _main_script = null
var _extra_script = null


func before_all() -> void:
	_main_script = load(SRC_MAIN)
	_extra_script = load(SRC_EXTRA)


func _creators_in(path: String) -> Array:
	var out: Array = []
	var re := RegEx.create_from_string("static func (create_\\w+_sprite_frames)")
	for m in re.search_all(FileAccess.get_file_as_string(path)):
		out.append(m.get_string(1))
	return out


func _all_creators() -> Array:
	var a := _creators_in(SRC_MAIN)
	a.append_array(_creators_in(SRC_EXTRA))
	return a


func _cache_keys_in(path: String) -> Array:
	var out: Array = []
	var src := FileAccess.get_file_as_string(path)
	for pat in ["_get_cached_sprite\\(\\s*\"([^\"]+)\"", "_build_standard_frames\\(\\s*\"([^\"]+)\""]:
		var re := RegEx.create_from_string(pat)
		for m in re.search_all(src):
			out.append(m.get_string(1))
	return out


func test_the_discovery_finds_a_real_roster() -> void:
	## CONTROL: every assertion below is vacuous if discovery returns nothing.
	var creators := _all_creators()
	assert_gt(creators.size(), 30, "discovered a real creator roster (%d)" % creators.size())
	assert_true("create_slime_sprite_frames" in creators, "and it contains a known member")


func test_every_generator_produces_a_usable_sheet() -> void:
	## The behavioural arm. A generator that silently yields an empty SpriteFrames renders
	## nothing in battle and nothing errors — exactly the silent-failure class this repo
	## treats as worse than a crash.
	var creators := _all_creators()
	var broken: Array = []
	var checked := 0
	for name in creators:
		var owner = _main_script if _main_script.has_method(name) else _extra_script
		if not owner.has_method(name):
			broken.append("%s: no such static method" % name)
			continue
		var frames = owner.call(name)
		checked += 1
		if frames == null:
			broken.append("%s: returned null" % name)
			continue
		for anim in REQUIRED_ANIMS:
			if not frames.has_animation(anim):
				broken.append("%s: missing '%s'" % [name, anim])
			elif frames.get_frame_count(anim) <= 0:
				broken.append("%s: '%s' has zero frames" % [name, anim])
	assert_gt(checked, 30, "CONTROL: actually generated sheets (%d)" % checked)
	assert_eq(broken.size(), 0, "generators producing unusable sheets: " + str(broken))


func test_cache_keys_are_unique_so_two_monsters_cannot_share_a_sprite() -> void:
	## Both creators route through _SU._get_cached_sprite. A copy-pasted key makes two
	## DIFFERENT monsters render identically — silently, and only visible on screen.
	var keys := _cache_keys_in(SRC_MAIN)
	keys.append_array(_cache_keys_in(SRC_EXTRA))
	assert_gt(keys.size(), 30, "CONTROL: found a real key set (%d)" % keys.size())
	var seen: Dictionary = {}
	var dupes: Array = []
	for k in keys:
		if seen.has(k):
			dupes.append(k)
		seen[k] = true
	assert_eq(dupes.size(), 0, "cache keys shared by more than one monster: " + str(dupes))


func test_every_creator_has_a_key_and_the_key_matches_it() -> void:
	## A key that doesn't name its own monster is the copy-paste half-done: unique, so the
	## uniqueness arm stays green, and pointing at the wrong cache entry.
	var creators := _all_creators()
	var keys := _cache_keys_in(SRC_MAIN)
	keys.append_array(_cache_keys_in(SRC_EXTRA))
	assert_eq(creators.size(), keys.size(),
		"every creator has exactly one cache key (creators %d, keys %d)" % [creators.size(), keys.size()])
	## BOTH DIRECTIONS. Forward alone is blind to a creator LOSING its key: a mutation that
	## repoints mall_cop's key at skate_punk leaves 44==44 and every key still resolving,
	## while mall_cop silently caches under another monster's entry. Measured 2026-08-22 —
	## predicted this arm would catch it, it did not, and that is why the reverse exists.
	var mismatched: Array = []
	for k in keys:
		var expected := "create_%s_sprite_frames" % k
		if not expected in creators:
			mismatched.append("key '%s' has no creator named '%s'" % [k, expected])
	assert_eq(mismatched.size(), 0, "keys not matching their creator: " + str(mismatched))

	var keyless: Array = []
	for c in creators:
		var want: String = str(c).replace("create_", "").replace("_sprite_frames", "")
		if not want in keys:
			keyless.append("%s has no cache key named '%s'" % [c, want])
	assert_eq(keyless.size(), 0, "creators whose own key is missing: " + str(keyless))


func test_no_monster_falls_through_to_the_default_sprite() -> void:
	## BattleScene resolves a monster as: world-variant sheet -> base sheet -> a `match
	## monster_id` arm -> the DEFAULT, which returns a slime. So a monster added with neither
	## a sheet nor an arm renders as a slime, silently, and only on screen.
	## That is not hypothetical: the Ogre and Barbarian Raider shipped exactly that way on
	## 2026-08-22 and were caught by a merged-tree gate rather than at authoring time.
	var mons = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var list = mons.get("monsters", mons) if mons is Dictionary else mons
	var ids: Array = []
	if list is Array:
		for m in list:
			if m is Dictionary and m.has("id"):
				ids.append(str(m["id"]))
	else:
		for k in list:
			ids.append(str(k))
	assert_gt(ids.size(), 50, "CONTROL: read a real monster roster (%d)" % ids.size())

	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	var sheets: Dictionary = manifest.get("monster_sheets", {}) if manifest is Dictionary else {}
	assert_gt(sheets.size(), 20, "CONTROL: read a real sheet manifest (%d)" % sheets.size())

	var scene_src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var start := scene_src.find("var external_frames = HybridSpriteLoaderClass.load_monster_sprite_frames(monster_id)")
	assert_gt(start, -1, "CONTROL: located the procedural fallback block")
	var block := scene_src.substr(start, scene_src.find("\nfunc ", start) - start)
	var arms: Array = []
	var re := RegEx.create_from_string("\"([a-z_0-9]+)\":")
	for m in re.search_all(block):
		arms.append(m.get_string(1))
	assert_true("slime" in arms, "CONTROL: the arm scan found a known member")

	var orphans: Array = []
	for id in ids:
		if not sheets.has(id) and not (id in arms):
			orphans.append(id)
	assert_eq(orphans.size(), 0,
		"monsters with neither an artist sheet nor a procedural arm — these render as SLIMES: " + str(orphans))
