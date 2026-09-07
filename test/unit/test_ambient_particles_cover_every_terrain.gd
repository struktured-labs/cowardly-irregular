extends GutTest

## tick 90 regression: _spawn_ambient_particles must have a match arm
## for every TerrainType used in regular battles. Pre-fix, only
## PLAINS / CAVE / FOREST / VILLAGE / BOSS had arms. W1 sub-zone
## battles (ICE / DESERT / SWAMP / COAST / VOLCANIC) and W2-W6
## procedural fallbacks all dropped to the empty default — zero
## ambient particles, flat-looking backdrops.
##
## In W1 this is user-visible: a battle in the ice/desert/swamp/coast/
## volcanic zone genuinely uses procedural rendering (no artist art
## for those terrains in BACKDROP_PATHS), so the particle gap was
## live. For W2-W6 it's defense in depth — artist backdrop normally
## loads first.

const BATTLE_BG := "res://src/battle/BattleBackground.gd"


const REQUIRED_TERRAIN_PARTICLES: Array[String] = [
	"PLAINS", "CAVE", "FOREST", "VILLAGE", "BOSS",
	"ICE", "DESERT", "SWAMP", "COAST", "VOLCANIC",
	"SUBURBAN", "STEAMPUNK", "INDUSTRIAL", "DIGITAL", "ABSTRACT",
]


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _ambient_particles_body() -> String:
	var src := _read(BATTLE_BG)
	var idx: int = src.find("func _spawn_ambient_particles")
	assert_gt(idx, -1, "_spawn_ambient_particles must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_every_terrain_has_ambient_particle_arm() -> void:
	var body := _ambient_particles_body()
	for terrain in REQUIRED_TERRAIN_PARTICLES:
		var pattern: String = "TerrainType." + terrain + ":"
		assert_true(body.contains(pattern),
			"_spawn_ambient_particles must have arm for TerrainType.%s — without it, that terrain's battles spawn ZERO ambient particles (flat-looking)" % terrain)


func test_every_arm_calls_spawn_particle_type() -> void:
	# Pin: every arm must actually CALL _spawn_particle_type. Don't
	# regress to "arm exists but body is a comment/pass".
	var body := _ambient_particles_body()
	for terrain in REQUIRED_TERRAIN_PARTICLES:
		var arm_start: int = body.find("TerrainType." + terrain + ":")
		assert_gt(arm_start, -1, "%s arm must exist" % terrain)
		# The arm body extends until the next TerrainType. or end of fn.
		var next_arm: int = body.find("TerrainType.", arm_start + 1)
		var arm_body: String = body.substr(arm_start, next_arm - arm_start) if next_arm > -1 else body.substr(arm_start)
		assert_true(arm_body.contains("_spawn_particle_type("),
			"TerrainType.%s arm must call _spawn_particle_type — empty arm means no particles" % terrain)


func test_w1_subzone_arms_are_distinct() -> void:
	# Sanity: the 5 W1 sub-zones should each use a distinct particle
	# color so the zones feel different. Pin two distinctive colors.
	var body := _ambient_particles_body()
	# ICE uses near-white-blue: Color(0.95, 0.97, 1.0, 0.6)
	assert_true(body.contains("Color(0.95, 0.97, 1.0, 0.6)"),
		"ICE ambient particle color must be near-white-blue snowflake")
	# DESERT uses tan: Color(0.85, 0.72, 0.45, 0.5)
	assert_true(body.contains("Color(0.85, 0.72, 0.45, 0.5)"),
		"DESERT ambient particle color must be tan sand grain")


func test_volcanic_uses_glow_palette_key() -> void:
	# Pin: VOLCANIC should derive ember color from palette["glow"],
	# matching the BOSS pattern. If a future refactor strips the
	# palette lookup, ember color falls back to a hardcoded constant.
	var body := _ambient_particles_body()
	var v_idx: int = body.find("TerrainType.VOLCANIC:")
	assert_gt(v_idx, -1, "VOLCANIC arm must exist")
	var next_arm: int = body.find("TerrainType.", v_idx + 1)
	var arm: String = body.substr(v_idx, next_arm - v_idx) if next_arm > -1 else body.substr(v_idx)
	assert_true(arm.contains("palette.get(\"glow\""),
		"VOLCANIC arm must derive ember color from palette['glow'] — matches BOSS pattern, falls back to 'accent' if missing")
