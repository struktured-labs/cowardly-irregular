extends GutTest

## Bugfix 2026-07-05: smoke_bomb's description promises "guarantee escape or blind
## enemies" and it authors guaranteed_escape=true — but it's type="support", so it
## routed only to _execute_support_ability (which applied the blind). The
## guaranteed_escape field is read ONLY in _execute_escape_ability, which a
## support ability never reaches, so the escape half was dead. The support
## dispatch arm now fires the escape after the blind when guaranteed_escape is
## set (honoring escape_allowed, so on a boss you just get the blind).


func test_smoke_bomb_authors_guaranteed_escape() -> void:
	var a = JobSystem.get_ability("smoke_bomb")
	assert_false(a.is_empty(), "smoke_bomb must resolve")
	assert_true(bool(a.get("guaranteed_escape", false)), "smoke_bomb authors guaranteed_escape")
	assert_eq(str(a.get("type", "")), "support",
		"smoke_bomb is type support (blind) — the routing that skipped the escape")


func test_support_dispatch_triggers_guaranteed_escape() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var arm: int = src.find("\"support\", \"song\", \"status\":")
	assert_gt(arm, -1, "the support dispatch arm must exist")
	var block: String = src.substr(arm, 900)
	assert_true(block.contains("guaranteed_escape"),
		"the support arm must check guaranteed_escape")
	assert_true(block.contains("_execute_escape_ability"),
		"guaranteed_escape must trigger the escape path after the support effect")
