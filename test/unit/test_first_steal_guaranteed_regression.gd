extends GutTest

## Playtest 2026-07-15: "He's rough if the steal fails the first time
## basically." Lockward is a knife-edge — first-turn Steal miss →
## Counter Stance one-shots the solo Rogue → unrecoverable loss spiral.
##
## Fix: monsters.json entry may set `first_steal_guaranteed: true`. The
## FIRST steal/mug against that target this fight always lands (rate roll
## bypassed). Falls back to normal rate after the steal_response has been
## consumed. Scoped to Lockward only — no global steal buff.


func test_lockward_monster_data_has_flag() -> void:
	var mons: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var lw: Dictionary = mons.get("rogue_lockward", {})
	assert_true(lw.get("first_steal_guaranteed", false) == true,
		"rogue_lockward.first_steal_guaranteed must be true — the whole gate hangs on this data flag")


func test_no_other_monster_gets_the_free_first_steal() -> void:
	# Anti-regression: this is a scoped balance concession for Lockward.
	# If a future monster gets the flag by copy-paste, the intent (and the
	# balance testing that went into Lockward's tuning) doesn't carry over.
	# Force a deliberate re-review by pinning the whitelist here.
	var mons: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var flagged: Array = []
	for id in mons.keys():
		if bool((mons[id] as Dictionary).get("first_steal_guaranteed", false)):
			flagged.append(id)
	assert_eq(flagged, ["rogue_lockward"],
		"first_steal_guaranteed is a Lockward-only concession — if a new monster needs it, extend this whitelist deliberately (balance re-review, not silent adoption)")


func test_helper_declared_and_gates_on_steal_response_consumed() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var i := src.find("func _first_steal_guaranteed")
	assert_gt(i, -1, "BattleManager must declare _first_steal_guaranteed helper")
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 700)
	assert_true("_steal_response_consumed" in body,
		"helper must gate on _steal_response_consumed so only the FIRST steal is guaranteed — subsequent steals fall back to normal rate")
	assert_true("first_steal_guaranteed" in body,
		"helper must read the monsters.json first_steal_guaranteed field")


func test_both_steal_paths_call_the_helper() -> void:
	# Steal path (line ~5439 pre-fix) and Mug path (line ~4121 pre-fix)
	# both roll `randf() < rate`. Both must consult the guarantee helper.
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_eq(src.count("_first_steal_guaranteed(_st) or randf() < _steal_rate"), 1,
		"Mug's steal-half must guard on the helper — otherwise Mug bypasses the concession")
	assert_eq(src.count("_first_steal_guaranteed(target) or randf() < effective_rate"), 1,
		"Steal ability must guard on the helper — the primary concession path")
