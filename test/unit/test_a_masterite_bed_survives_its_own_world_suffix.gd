extends GutTest

## THE MONSTERS SAY `futuristic` AND THE MUSIC SAYS `digital`, AND ONE MATCH ARM IS THE ONLY THING
## JOINING THEM. BattleScene:3354 builds a Masterite's bed as `boss_<role>_<suffix>` where the suffix
## comes from SoundManager._get_current_world_suffix() — which maps AREA IDS to a MUSIC word, and in
## five of six worlds returns the same word its area ids contain. World 5 is the exception: its ids
## read `overworld_futuristic` / `futuristic_overworld` and it returns "digital", because that is what
## the four composed beds are named.
##
## So "normalising" that suffix to match the world id — the obvious tidy-up, since monsters.json,
## the cutscenes and the sprite variants all say `futuristic` — silently breaks four Masterite
## fights. Measured 2026-10-25, and the consequence is worse than a missing bed: the manifest has no
## `boss_*_futuristic` keys AND no generic `boss_futuristic`, so SoundManager:4066 takes the second
## fallback and the four W5 Masterites would fight to the WORLD 1 MEDIEVAL boss theme, in the Digital
## world, with nothing but a polite log line. Raised by cowir-music, who found the bridge unpinned.
##
## Derived from the three sources rather than listed, so a sixth world or a fifth role is covered the
## day it lands. The two uncomposed steampunk beds pass on the structural rule rather than on an
## allowlist: their world HAS a bed, so they degrade to their own world's music, which is the whole
## distinction this file is about.

const MONSTERS := "res://data/monsters.json"
const MUSIC_MANIFEST := "res://data/music_manifest.json"
const SOUND_MANAGER := "res://src/audio/SoundManager.gd"
const BATTLE_SCENE := "res://src/battle/BattleScene.gd"


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(_read(path))
	return parsed if parsed is Dictionary else {}


func _music_keys() -> Dictionary:
	var root: Dictionary = _json(MUSIC_MANIFEST)
	var inner: Variant = root.get("tracks", root)
	return inner if inner is Dictionary else {}


## (role, monster_suffix) for every Masterite in the roster.
func _masterites() -> Array:
	var root: Dictionary = _json(MONSTERS)
	var inner: Variant = root.get("monsters", root)
	var mons: Dictionary = inner if inner is Dictionary else {}
	var out: Array = []
	for id in mons:
		var sid: String = str(id)
		if not sid.begins_with("masterite_"):
			continue
		var parts := sid.split("_")
		if parts.size() < 3:
			continue
		out.append({"id": sid, "role": str(parts[1]), "suffix": str(parts[parts.size() - 1])})
	return out


## The body of _get_current_world_suffix, bounded at BOTH ends — six other functions in this file
## return a world suffix, so an unbounded parse reads arms that are not this mapper's.
func _suffix_fn_body() -> String:
	var src: String = _read(SOUND_MANAGER)
	var start: int = src.find("func _get_current_world_suffix(")
	if start < 0:
		return ""
	var end: int = src.find("\nfunc ", start + 1)
	return src.substr(start, (end - start) if end > start else -1)


## Every (area-id list, returned suffix) arm of that match block.
func _suffix_arms() -> Array:
	var out: Array = []
	var rx := RegEx.new()
	rx.compile('((?:"[\\w]+",?\\s*)+):\\s*\\n\\s*return "(\\w+)"')
	for m in rx.search_all(_suffix_fn_body()):
		out.append({"ids": m.get_string(1), "suffix": m.get_string(2)})
	return out


## The distinct music suffixes this mapper can return. Three arms return "medieval", so this is a
## SET and not an arm count.
func _returned_suffixes() -> Dictionary:
	var out := {}
	for a in _suffix_arms():
		out[str(a["suffix"])] = true
	return out


## monster suffix -> the MUSIC suffix the mapper would return for that world. TWO SHAPES, because
## world 1's area ids are bare ("overworld", "village", "cave") while worlds 2-6 carry their theme
## word. Written keyed on `overworld_<suffix>` alone first, which silently found 5 of 6 and missed
## medieval entirely — the control arm caught it, which is the only reason this comment is here.
func _music_suffix_for_monster_suffix() -> Dictionary:
	var returned := _returned_suffixes()
	var out := {}
	for m in _masterites():
		var s: String = str(m["suffix"])
		if returned.has(s):
			out[s] = s          ## the identity worlds: the monster word IS the music word
			continue
		for a in _suffix_arms():
			if str(a["ids"]).contains('"overworld_%s"' % s) or str(a["ids"]).contains('"%s_overworld"' % s):
				out[s] = str(a["suffix"])   ## the translated world: futuristic -> digital
				break
	return out


func test_the_derivation_sees_all_three_sources() -> void:
	## CONTROL. Every arm below loops over these, so an empty parse would pass them all in silence.
	var mast := _masterites()
	assert_eq(mast.size(), 24, "the roster must still hold 24 Masterites (found %d)" % mast.size())
	var bridge := _music_suffix_for_monster_suffix()
	assert_gt(bridge.size(), 5, "the suffix mapper must parse all six worlds (got %s)" % str(bridge))
	var keys := _music_keys()
	assert_gt(keys.size(), 50, "the music manifest must parse (got %d keys)" % keys.size())
	var src: String = _read(BATTLE_SCENE)
	assert_true(src.contains('"boss_%s_%s" % [masterite_type, world_suffix]'),
		"BattleScene must still build a Masterite bed from the role and the WORLD SUFFIX — if that shape changed, every arm here is about the wrong key")


func test_the_two_world_suffix_vocabularies_agree() -> void:
	## ⛔ THE REASON THIS FILE IS NOT A RE-PIN OF test_a_masterite_without_a_theme_still_sounds_like_a_boss.
	## SoundManager holds TWO independent world->suffix mappings fifteen lines apart:
	##   :2635 _interior_world_suffix()      -> delegates to WeatherSystem.world_id_for(w)
	##   :2650 _get_current_world_suffix()   -> hand-written area-id match arms, zero WeatherSystem refs
	## cowir-music's guard derives its expected keys from WeatherSystem, so it reds on a WORLD_IDS
	## rename — measured by them. But BattleScene:3354 and _start_boss_music:4062 call the OTHER one,
	## so a rename of the hand-written arm leaves their derivation untouched and their file green
	## while four Masterite beds stop resolving. Two sources feeding one surface, and the guard was
	## pointed at the one the runtime does not read.
	##
	## These two are SUPPOSED to agree and nothing makes them, so this asserts AGREEMENT rather than
	## modelling precedence — if they agree, which one wins is moot.
	var bridge := _music_suffix_for_monster_suffix()
	var disagree: Array = []
	for w in range(1, 7):
		var canonical: String = str(WeatherSystem.world_id_for(w))
		var found := ""
		for monster_sfx in bridge:
			if str(bridge[monster_sfx]) == canonical:
				found = str(monster_sfx)
		if found == "":
			disagree.append("world %d: WeatherSystem says '%s', no area-id arm in _get_current_world_suffix returns it" % [w, canonical])
	assert_eq(disagree.size(), 0,
		"SoundManager's two world-suffix vocabularies must agree, or the beds a guard checks are not the beds the game asks for: " + str(disagree))


func test_the_futuristic_world_still_translates_to_the_digital_beds() -> void:
	## THE BRIDGE, NAMED. This is the only world whose music word differs from its monster word, and
	## the asymmetry is the whole hazard: five arms are identities, so the sixth looks like a typo.
	var bridge := _music_suffix_for_monster_suffix()
	assert_eq(str(bridge.get("futuristic", "")), "digital",
		"world 5's music suffix must stay 'digital' — the four composed beds are named boss_<role>_digital, and renaming this drops those fights to World 1's medieval boss theme")
	var identities: Array = []
	for monster_sfx in bridge:
		if str(bridge[monster_sfx]) == str(monster_sfx):
			identities.append(monster_sfx)
	assert_gt(identities.size(), 3,
		"most worlds must still be identities, or this file is pinning the wrong asymmetry: %s" % str(bridge))


func test_every_masterite_reaches_a_bed_from_its_own_world() -> void:
	## THE END-TO-END CLAIM. For each Masterite, build the key BattleScene would build and require
	## that it resolves — or that its WORLD'S generic bed does. Falling through to boss_medieval is
	## NOT acceptable: that is the defect, not a graceful degrade.
	var keys := _music_keys()
	var bridge := _music_suffix_for_monster_suffix()
	var unreachable: Array = []
	var degraded: Array = []
	var checked := 0
	for m in _masterites():
		var monster_sfx: String = str(m["suffix"])
		var music_sfx: String = str(bridge.get(monster_sfx, ""))
		if music_sfx == "":
			unreachable.append("%s: no world-suffix arm answers for '%s'" % [str(m["id"]), monster_sfx])
			continue
		checked += 1
		var bespoke := "boss_%s_%s" % [str(m["role"]), music_sfx]
		if keys.has(bespoke):
			continue
		var generic := "boss_%s" % music_sfx
		if keys.has(generic):
			degraded.append("%s -> %s (falls back to %s)" % [str(m["id"]), bespoke, generic])
			continue
		unreachable.append("%s wants %s; neither it nor %s exists, so it plays WORLD 1's boss theme" % [str(m["id"]), bespoke, generic])
	assert_eq(checked, 24, "CONTROL: every Masterite must have been checked, not skipped (%d)" % checked)
	assert_eq(unreachable.size(), 0, "a Masterite whose bed resolves to another world's music: " + str(unreachable))
	## Degrading to your own world's bed is allowed and currently used by exactly the two beds held
	## for struktured. Asserted as a CEILING so a silent slide from composed to generic shows up.
	assert_true(degraded.size() <= 2,
		"more Masterites now fall back to a generic world bed than the two uncomposed steampunk ones — say which and why: " + str(degraded))


func test_the_fallback_behind_the_bridge_is_the_wrong_world_on_purpose_pinned() -> void:
	## Why the arm above refuses a boss_medieval landing: SoundManager's SECOND fallback is literally
	## world 1, for a stated cost reason. That makes a missing per-world bed inaudible as a BUG and
	## audible only as the wrong music, which is why the bridge needs a guard rather than a log line.
	var src: String = _read(SOUND_MANAGER)
	var start: int = src.find("func _start_boss_music(")
	assert_true(start >= 0, "SoundManager must still declare _start_boss_music")
	if start < 0:
		return
	var end: int = src.find("\nfunc ", start + 1)
	var body: String = src.substr(start, (end - start) if end > start else -1)
	assert_true(body.contains('"boss_" + suffix'),
		"the per-world bed must still be the FIRST thing tried, or the bridge this file guards is not the one in use")
	assert_true(body.contains('"boss_medieval"'),
		"the medieval second fallback is the reason a missing world bed is inaudible — if it is gone, relax the arm above rather than leaving a stale rationale here")
