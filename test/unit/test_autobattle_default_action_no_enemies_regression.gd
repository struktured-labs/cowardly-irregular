extends GutTest

## tick 330: AutobattleSystem._get_default_action returns {"type":
## "defer"} (not "skip") when no enemies remain.
##
## Pre-fix the no-enemies branch returned {"type": "skip"} — a string
## BattleManager's action dispatch at line ~1972 has NO arm for. The
## default `_:` arm fired push_warning("Unknown action type 'skip'")
## and recovered by advancing the chain, but every "all enemies died
## before this combatant's turn" path produced a misleading runtime
## warning. Easy to trigger: any battle where a queued autobattle
## action arrives after the last enemy KO (sub-turn ordering,
## simultaneous deaths, summoner cleanup, etc).
##
## Fix: return "defer" — already wired in BattleManager's match
## (line 1979) with the correct "skip turn, gain AP, defend"
## semantics. Same intent (no enemies, step back), real handler.

const AUTOBATTLE_PATH := "res://src/autobattle/AutobattleSystem.gd"
const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: defer in the no-enemies branch ──────────────────────

func test_default_action_no_enemies_returns_defer() -> void:
	var src := _read(AUTOBATTLE_PATH)
	var fn_idx: int = src.find("func _get_default_action")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("\"type\": \"defer\""),
		"_get_default_action's no-enemies branch must return defer (was 'skip' — unknown to BattleManager)")
	# Pin via behavior, not raw text — the historical "skip" string
	# might appear in a comment explaining the fix. Verify via the
	# return-statement shape: after the last `return {` in the body,
	# the immediate next non-whitespace `"type"` value must be "defer".
	var return_idx: int = body.rfind("return {")
	assert_gt(return_idx, -1, "must find a return-dict statement")
	var return_body: String = body.substr(return_idx, 200)
	assert_true(return_body.contains("\"defer\""),
		"the LAST return statement (no-enemies fallback) must produce a defer-typed action")
	assert_false(return_body.contains("\"skip\""),
		"the LAST return statement must not still reference 'skip' — that was the bug")


# ── Source pin: BattleManager actually has a defer arm ──────────────

func test_battle_manager_has_defer_handler() -> void:
	# Sanity: defer must remain a real arm in BattleManager's action
	# match. If this assertion fails, the fix above silently regresses
	# back to the "Unknown action type" warning class.
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("\"defer\":"),
		"BattleManager must still have a defer arm in its action dispatch")
	assert_true(src.contains("_execute_defer(combatant)"),
		"defer arm must call _execute_defer")


# ── Behavioral: returned dict is well-formed ────────────────────────

func test_returned_action_shape() -> void:
	# Drive the function with no enemies in the battle. Easiest path:
	# instantiate AutobattleSystem and a Combatant, call the function
	# directly. No BattleManager means _get_enemies_for returns [].
	var script: GDScript = load(AUTOBATTLE_PATH)
	var sys: Object = script.new()
	add_child_autofree(sys)

	var combatant_script: GDScript = load("res://src/battle/Combatant.gd")
	var c: Object = combatant_script.new()
	add_child_autofree(c)

	var action: Dictionary = sys._get_default_action(c)
	assert_eq(str(action.get("type", "")), "defer",
		"no-enemies fallback must return type=defer")
	# Defer needs no other fields — the dispatch matches purely on type.
	assert_eq(action.size(), 1,
		"defer action dict must be {type: defer} — extra fields are noise")
