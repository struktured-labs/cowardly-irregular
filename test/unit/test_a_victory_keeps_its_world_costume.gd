extends GutTest

## struktured 2026-10-05: "victory animations arent replaced in suburban / alternate worlds either, still ones from
## medeivail". idle was the only battle anim with world sheets, so in W2+ the costume snapped back to medieval armour
## the moment victory played: the loader takes <anim>_<suffix>.png only if it exists, else the artist base.
## Now victory_<suffix>.png exists wherever the idle is dressed, built from the artist's own victory poses at his frame
## count, so frame_durations_ms (his timing) still applies. Judged through the real loader in each world.

const Loader := preload("res://src/battle/sprites/HybridSpriteLoader.gd")
const STARTERS := ["fighter", "cleric", "mage", "rogue", "bard"]

var _pre_world: int = -1
var _saved_world: int = -1


func before_all() -> void:
	_pre_world = int(GameState.current_world)


func before_each() -> void:
	_saved_world = int(GameState.current_world)


func after_each() -> void:
	GameState.current_world = _saved_world


func _sheet_of(sf: SpriteFrames, anim: StringName) -> String:
	if sf == null or not sf.has_animation(anim) or sf.get_frame_count(anim) == 0:
		return ""
	var t := sf.get_frame_texture(anim, 0)
	return (t as AtlasTexture).atlas.resource_path if t is AtlasTexture else t.resource_path


func _durations(sf: SpriteFrames, anim: StringName) -> Array:
	var out: Array = []
	for i in sf.get_frame_count(anim):
		out.append(snappedf(sf.get_frame_duration(anim, i), 0.0001))
	return out


## (world, suffix) for every world that dresses at least one starter's idle — the worlds a victory must follow.
func _dressed_worlds() -> Array:
	var out: Array = []
	for world in range(2, 7):
		var suffix: String = Loader.world_suffix(world)
		if suffix == "":
			continue
		for job in STARTERS:
			if ResourceLoader.exists("res://assets/sprites/jobs/%s/idle_%s.png" % [job, suffix]):
				out.append([world, suffix])
				break
	return out


func test_a_victory_wears_the_costume_its_idle_wears() -> void:
	var worlds := _dressed_worlds()
	assert_eq(worlds.size(), 5, "CONTROL: every world past the first dresses the starters' idle (%s)" % str(worlds))
	var bad: Array = []
	var judged := 0
	for pair in worlds:
		GameState.current_world = int(pair[0])
		for job in STARTERS:
			var sf: SpriteFrames = Loader.load_sprite_frames(null, job)
			if not _sheet_of(sf, &"idle").ends_with("idle_%s.png" % pair[1]):
				continue
			judged += 1
			var got := _sheet_of(sf, &"victory")
			if not got.ends_with("victory_%s.png" % pair[1]):
				bad.append("%s in %s: idle is dressed, victory plays %s" % [job, pair[1], got.get_file()])
	assert_gt(judged, 20, "CONTROL: dressed starters were judged (%d)" % judged)
	assert_eq(bad, [], "victories that snap back to medieval: %s" % str(bad))


func test_a_dressed_victory_keeps_the_artists_timing() -> void:
	var bad: Array = []
	for job in STARTERS:
		GameState.current_world = 1
		var base: SpriteFrames = Loader.load_sprite_frames(null, job)
		var want := _durations(base, &"victory")
		assert_gt(want.size(), 1, "CONTROL: the %s's artist victory has frames" % job)
		for pair in _dressed_worlds():
			GameState.current_world = int(pair[0])
			var sf: SpriteFrames = Loader.load_sprite_frames(null, job)
			if not _sheet_of(sf, &"victory").ends_with("victory_%s.png" % pair[1]):
				continue
			var got := _durations(sf, &"victory")
			if got != want:
				bad.append("%s in %s: %d frames %s, the artist's %d %s" % [job, pair[1], got.size(), str(got.slice(0, 3)), want.size(), str(want.slice(0, 3))])
	assert_eq(bad, [], "dressed victories that lost the artist's frame count or timing: %s" % str(bad))


func test_world_one_still_plays_the_artists_own_victory() -> void:
	GameState.current_world = 1
	for job in STARTERS:
		var sf: SpriteFrames = Loader.load_sprite_frames(null, job)
		assert_eq(_sheet_of(sf, &"victory"), "res://assets/sprites/jobs/%s/victory.png" % job,
			"world 1 is the artist's base art for the %s" % job)


func test_zz_current_world_was_handed_back() -> void:
	assert_eq(int(GameState.current_world), _pre_world, "STRAND: current_world left at %d, was %d" % [int(GameState.current_world), _pre_world])
