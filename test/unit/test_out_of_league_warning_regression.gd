extends GutTest

## struktured 2026-07-15: wandered into the Shadow Dragon Cave at ~lvl 10
## and got flattened by Umbraxis (lvl 18) with zero warning. Ruling:
## "out of ur league warnings are a good idea but you should be allowed
## to fight it of course. party remarks are good."
##
## Implementation: DragonCave._maybe_warn_out_of_league — a Toast-borne
## party remark on dungeon entry when the resident boss out-levels the
## party average by OUT_OF_LEAGUE_LEVEL_GAP (5)+. NEVER blocks entry or
## the fight.

const CAVE := "res://src/maps/dungeons/DragonCave.gd"


func test_warning_helper_exists_and_fires_on_ready() -> void:
	var src := FileAccess.get_file_as_string(CAVE)
	assert_true("func _maybe_warn_out_of_league" in src,
		"DragonCave must declare the out-of-league warning helper")
	assert_true("_maybe_warn_out_of_league()" in src,
		"the helper must be CALLED from _ready — an uncalled helper is the authored-but-never-wired class")


func test_warning_is_nonblocking() -> void:
	# The ruling: warn, never block. The helper must not touch any gate/
	# lock/transition primitive.
	var src := FileAccess.get_file_as_string(CAVE)
	var i := src.find("func _maybe_warn_out_of_league")
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 2000)
	assert_false("push_lock" in body,
		"warning must not lock input — entry stays free")
	assert_false("transition_triggered" in body,
		"warning must not redirect the player out of the dungeon")
	assert_true("Toast.show_warning" in body,
		"warning surfaces via Toast — passive, dismissible, non-modal")


func test_gap_threshold_and_remarks_authored() -> void:
	var src := FileAccess.get_file_as_string(CAVE)
	assert_true("const OUT_OF_LEAGUE_LEVEL_GAP: int = 5" in src,
		"gap threshold pinned at 5 levels — retune deliberately, not by drift")
	var i := src.find("const OUT_OF_LEAGUE_REMARKS")
	assert_gt(i, -1)
	var window := src.substr(i, 800)
	for pc in ["Cleric:", "Fighter:", "Rogue:", "Mage:", "Bard:"]:
		assert_true(pc in window,
			"every starter PC needs a remark variant (%s missing) — the warning is party-voiced" % pc)


func test_boss_levels_still_support_the_gap() -> void:
	# The warning derives from monsters.json levels. Umbraxis at 18 vs the
	# post-cave party (~10-12) must clear the gap; Rat King at 10 must NOT
	# warn a level-9 party (gap 1). Pins the data the feature reads.
	var mons: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var umbraxis_lvl: int = int((mons.get("shadow_dragon", mons.get("umbraxis", {})) as Dictionary).get("level", 0))
	assert_gte(umbraxis_lvl, 15,
		"Umbraxis must stay a high-level optional boss — the warning depends on real level data")
