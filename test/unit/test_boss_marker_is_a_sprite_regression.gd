extends GutTest

## struktured 2026-09-06: "I want bosses to not be labeld as a 'B' tile any longer lets get a sprite
## there please." Both dungeon families drew a red square with a yellow letter B on it. Now the
## marker carries the boss's OWN battle idle frame, resolved from the same monster_sheets ledger
## the fight uses — so the thing on the map is the thing you fight, and a boss can never show two
## different faces.

const DC_SRC := "res://src/maps/dungeons/DragonCave.gd"
const WC_SRC := "res://src/maps/dungeons/WhisperingCave.gd"

## Every dungeon's declared boss, so a new dungeon with a typo'd id fails here and not on screen.
const BOSS_IDS := [
	"fire_dragon", "ice_dragon", "lightning_dragon", "shadow_dragon",
	"cave_rat_king", "chancellor_mordaine", "cartographer_wraith",
]


func _marker_body(src_path: String) -> String:
	var src := FileAccess.get_file_as_string(src_path)
	var i: int = src.find("func _create_boss_marker")
	assert_gt(i, -1, "CONTROL: %s must still have a boss marker builder" % src_path)
	var nxt: int = src.find("\nfunc ", i + 1)
	return src.substr(i, (nxt - i) if nxt > i else 2000)


func test_neither_dungeon_family_draws_the_letter_B_any_more() -> void:
	for src_path in [DC_SRC, WC_SRC]:
		var body := _marker_body(src_path)
		assert_false(body.contains('text = "B"'),
			"%s still labels the boss with a letter instead of drawing it" % src_path)
		assert_true(body.contains("monster_frame_texture"),
			"%s must resolve the boss's own sheet frame" % src_path)
		assert_true(body.contains("Sprite2D.new()"),
			"%s must actually add a sprite node, not just look the texture up" % src_path)


func test_the_marker_reads_the_dungeons_declared_boss_not_a_hardcoded_one() -> void:
	# DragonCave serves 6 different bosses; a literal id there would put a dragon in the castle.
	var body := _marker_body(DC_SRC)
	assert_true(body.contains("monster_frame_texture(boss_id)"),
		"DragonCave must pass its own boss_id — every subclass overrides it")


func test_every_declared_boss_actually_resolves_to_a_frame() -> void:
	var missing: Array[String] = []
	for id in BOSS_IDS:
		if HybridSpriteLoader.monster_frame_texture(id) == null:
			missing.append(id)
	assert_eq(missing, [] as Array[String],
		"bosses whose marker would fall back to a placeholder glyph: %s" % str(missing))


func test_the_resolver_can_report_absence() -> void:
	# CONTROL: without this the assertion above passes for a resolver that returns a texture always.
	assert_null(HybridSpriteLoader.monster_frame_texture("zzz_no_such_monster"),
		"a fabricated id must resolve to null, or the coverage check is vacuous")


func test_the_frame_is_the_idle_pose_and_a_real_region() -> void:
	var tex := HybridSpriteLoader.monster_frame_texture("cave_rat_king")
	assert_not_null(tex, "CONTROL: the Rat King has a sheet")
	assert_gt(tex.region.size.x, 0.0, "the atlas region must be a real rect, not a zero crop")
	assert_gt(tex.region.size.y, 0.0)
	# idle starts at frame 0 on every authored sheet; a non-zero origin would mean we grabbed
	# some other animation's frame and the boss would stand on the map mid-attack.
	assert_eq(tex.region.position, Vector2.ZERO, "idle frame 0 is the pose the marker should hold")
