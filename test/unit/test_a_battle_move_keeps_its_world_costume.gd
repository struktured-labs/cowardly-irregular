extends GutTest

## Sibling of test_a_victory_keeps_its_world_costume. Past world 1 a starter's idle and victory wear the world's
## costume, but every swing, spell, flinch and fall snapped back to medieval armour mid-battle: the loader takes
## <anim>_<suffix>.png only when it exists, and only idle and victory had them (cowir-main, 2026-10-05: "attack,
## cast, hit and the rest revert mid-battle too"). attack, cast, hit and dead now have world sheets built from the
## artist's own poses at his frame count, so each plays at his speed (hit/dead after a pilot showed reaction poses
## transfer when SHOWN). Judged through the real loader in each world.

const Loader := preload("res://src/battle/sprites/HybridSpriteLoader.gd")
const STARTERS := ["fighter", "cleric", "mage", "rogue", "bard"]
const MOVES := [&"attack", &"cast", &"hit", &"dead"]

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


func _dressed_worlds() -> Array:
	var out: Array = []
	for world in range(2, 7):
		var suffix: String = Loader.world_suffix(world)
		if suffix != "" and ResourceLoader.exists("res://assets/sprites/jobs/fighter/idle_%s.png" % suffix):
			out.append([world, suffix])
	return out


func test_a_move_wears_the_costume_its_idle_wears() -> void:
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
			for move in MOVES:
				judged += 1
				var got := _sheet_of(sf, move)
				if not got.ends_with("%s_%s.png" % [move, pair[1]]):
					bad.append("%s %s in %s: idle is dressed, the %s plays %s" % [job, move, pair[1], move, got.get_file()])
	assert_gt(judged, 80, "CONTROL: dressed starters' moves were judged (%d)" % judged)
	assert_eq(bad, [], "moves that snap back to medieval mid-battle: %s" % str(bad))


func test_a_dressed_move_keeps_the_artists_frames_and_speed() -> void:
	var bad: Array = []
	for job in STARTERS:
		GameState.current_world = 1
		var base: SpriteFrames = Loader.load_sprite_frames(null, job)
		for move in MOVES:
			var frames := base.get_frame_count(move)
			var speed := base.get_animation_speed(move)
			assert_gt(frames, 0, "CONTROL: the %s's artist %s has frames" % [job, move])
			for pair in _dressed_worlds():
				GameState.current_world = int(pair[0])
				var sf: SpriteFrames = Loader.load_sprite_frames(null, job)
				if not _sheet_of(sf, move).ends_with("%s_%s.png" % [move, pair[1]]):
					continue
				if sf.get_frame_count(move) != frames or not is_equal_approx(sf.get_animation_speed(move), speed):
					bad.append("%s %s in %s: %d frames at %.2f fps, the artist's %d at %.2f" % [job, move, pair[1],
						sf.get_frame_count(move), sf.get_animation_speed(move), frames, speed])
				GameState.current_world = 1
	assert_eq(bad, [], "dressed moves that lost the artist's frame count or speed: %s" % str(bad))


func test_world_one_still_plays_the_artists_own_moves() -> void:
	GameState.current_world = 1
	for job in STARTERS:
		var sf: SpriteFrames = Loader.load_sprite_frames(null, job)
		for move in MOVES:
			assert_eq(_sheet_of(sf, move), "res://assets/sprites/jobs/%s/%s.png" % [job, move],
				"world 1 is the artist's base art for the %s's %s" % [job, move])


func test_zz_current_world_was_handed_back() -> void:
	assert_eq(int(GameState.current_world), _pre_world, "STRAND: current_world left at %d, was %d" % [int(GameState.current_world), _pre_world])
