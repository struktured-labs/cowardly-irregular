extends GutTest

## tick 398: corrupt_save meta_effect (save_deletion ability) now
## applies its authored corruption_amount.
##
## Pre-fix the meta_effect fell through to `_:` push_warning. The
## save_deletion ability also has damage_multiplier=3.0 magic damage
## that routes elsewhere, but the corruption side-effect (the whole
## point of the "delete the player's save" terror move) silently
## dropped on the floor.
##
## Routes through GameState.add_corruption which clamps to [0, 1]
## and fires save_corrupted on increase — engine-level pieces
## already exist, just needed wiring.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"

## ⛔ RESTORING THE FIELD IS NOT RESTORING THE WORLD. This file drives the real
## `add_corruption`, which EMITS `corruption_changed` — and `SoundManager.set_save_corruption` is
## connected to it, so the autoload renders a 0.3 detune. The old teardown put `corruption_level`
## back with a DIRECT WRITE, and `corruption_level` is a plain var with no setter: a direct write
## notifies nobody. GameState went home; SoundManager kept the detune for every file after this one.
##
## ⚠️ IT WAS INVISIBLE UNTIL `.420` BECAUSE A MASK WAS REMOVED, NOT BECAUSE ANYTHING BROKE HERE.
## `reset_corruption` used to zero the rendered value outright; cowir-music changed it to RE-DERIVE
## from the save meter, correctly (a rotting save is meant to stay audible outside the grind loop).
## The re-derivation reads the value this teardown left behind. Their fix is right and this is its
## cost — an incomplete teardown that had been here the whole time.
##
## ✅ SO THE REPAIR IS TO RESTORE THE CAUSE, NOT THE FIELD: put the value back AND emit, so every
## listener re-derives from it. Emitting is what the production path does; a test that reaches
## through the front door has to leave through it too.
##
## ⚠️ AND IT MOVED TO after_each RATHER THAN STAYING INLINE AT THE END OF THE ARM. A GDScript error
## — or a failing assert — aborts the enclosing function, so an inline restore below an assertion is
## skipped exactly when the test is already going wrong, and the leak lands on top of the failure.
var _prior_corruption: float = 0.0
var _corruption_touched: bool = false


func after_each() -> void:
	if not _corruption_touched:
		return
	_corruption_touched = false
	if not GameState:
		return
	GameState.corruption_level = _prior_corruption
	if GameState.has_signal("corruption_changed"):
		GameState.corruption_changed.emit(_prior_corruption)


func test_arm_exists() -> void:
	var src: String = FileAccess.get_file_as_string(BATTLE_MANAGER_PATH)
	assert_true(src.contains("\"corrupt_save\":"),
		"BattleManager._execute_meta_ability must have a corrupt_save arm")
	# Pin the GameState.add_corruption call.
	var arm_idx: int = src.find("\"corrupt_save\":")
	var window: String = src.substr(arm_idx, 800)
	assert_true(window.contains("GameState.add_corruption(corruption_amount)"),
		"corrupt_save arm must call GameState.add_corruption with the authored amount")


func test_data_authors_corrupt_save() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("save_deletion"))
	assert_eq(str(data["save_deletion"].get("meta_effect", "")), "corrupt_save")
	# Must still author a non-zero corruption_amount for the fix to do anything.
	assert_gt(float(data["save_deletion"].get("corruption_amount", 0.0)), 0.0,
		"save_deletion must still author a positive corruption_amount")


func test_corrupt_save_raises_corruption() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	if not GameState:
		pending("GameState autoload required")
		return
	_prior_corruption = GameState.corruption_level
	_corruption_touched = true
	GameState.corruption_level = 0.0
	# Cast the meta ability synthetically.
	var c_script: GDScript = load("res://src/battle/Combatant.gd")
	var caster: Combatant = c_script.new()
	caster.initialize({"name": "Necromancer", "max_hp": 100, "max_mp": 100,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(caster)
	var ability: Dictionary = {
		"id": "test_save_deletion",
		"meta_effect": "corrupt_save",
		"corruption_amount": 0.3,
	}
	bm._execute_meta_ability(caster, ability, [])
	# Pre-fix corruption stayed at 0.0; post-fix it should rise.
	assert_gt(GameState.corruption_level, 0.0,
		"corruption_level must rise after corrupt_save meta_effect — pre-fix the cast silently fizzled")

