extends GutTest

## tick 401: skip_dialogue (Skiptrotter skip_cutscene ability) sets
## a meta-skip flag that GameLoop consumes on the next cutscene
## check. Pre-fix the meta_effect fell through to push_warning —
## 5 MP burned to skip a cutscene; player got the cutscene anyway.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const GAME_LOOP_PATH := "res://src/GameLoop.gd"


func test_bm_arm_writes_flag() -> void:
	var src: String = FileAccess.get_file_as_string(BATTLE_MANAGER_PATH)
	var arm_idx: int = src.find("\"skip_dialogue\":")
	assert_gt(arm_idx, -1, "BattleManager must have a skip_dialogue arm")
	var window: String = src.substr(arm_idx, 800)
	assert_true(window.contains("meta_skip_next_cutscene"),
		"skip_dialogue arm must set meta_skip_next_cutscene flag")


func test_gameloop_consumes_flag() -> void:
	var src: String = FileAccess.get_file_as_string(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func check_pending_cutscene")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("meta_skip_next_cutscene"),
		"check_pending_cutscene must read meta_skip_next_cutscene")
	assert_true(body.contains("= false"),
		"check_pending_cutscene must single-shot clear the flag after consumption")


func test_data_authors_skip_dialogue() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("skip_cutscene"))
	assert_eq(str(data["skip_cutscene"].get("meta_effect", "")), "skip_dialogue")


func test_bm_writes_flag_runtime() -> void:
	# End-to-end: cast skip_dialogue, verify the flag is set on GameState.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	if not GameState:
		pending("GameState autoload required")
		return
	# Clear the flag first.
	GameState.game_constants["meta_skip_next_cutscene"] = false
	var c_script: GDScript = load("res://src/battle/Combatant.gd")
	var caster: Combatant = c_script.new()
	caster.initialize({"name": "Skipper", "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(caster)
	var ability: Dictionary = {
		"id": "test_skip_cutscene",
		"meta_effect": "skip_dialogue",
	}
	bm._execute_meta_ability(caster, ability, [])
	assert_true(bool(GameState.game_constants.get("meta_skip_next_cutscene", false)),
		"meta_skip_next_cutscene flag must be true after the cast")
	# Clean up.
	GameState.game_constants["meta_skip_next_cutscene"] = false
