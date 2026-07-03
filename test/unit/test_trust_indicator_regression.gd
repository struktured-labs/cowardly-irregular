extends GutTest

## Trust was invisible on the party panel — the [A] tag reads only
## AutobattleSystem enablement, so a trusted PC (auto-playing turns!)
## showed no indicator at all. That invisibility is how the user got
## stuck asking "how do I disable trust?" Trusted PCs now show a cyan
## [T] in both the build and update paths.


func test_both_indicator_sites_know_about_trust() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleUIManager.gd")
	var hits: int = 0
	var idx: int = src.find("\" [T]\"")
	while idx != -1:
		hits += 1
		idx = src.find("\" [T]\"", idx + 1)
	assert_eq(hits, 2,
		"[T] must exist at BOTH the status-box build site and the per-turn update site (found %d)" % hits)
	assert_true(src.contains("member.player_trust"),
		"the tag must read the player_trust field, not the shared lock")
