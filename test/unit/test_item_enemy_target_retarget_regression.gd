extends GutTest

## tick 361: BattleManager._execute_item picks the right retargeter
## based on the item's authored target_type instead of ALWAYS calling
## _retarget_ally on every non-revival item.
##
## Pre-fix:
##   var is_revival_item = item_effects.get("revive", false)
##   for t in targets:
##     if is_revival_item: ... (handle dead allies)
##     else:               _retarget_ally(user, t, false)   # ← ALWAYS ally
##
## Damage items (holy_water, bomb_fragment, arctic_wind, lightning_bolt)
## have target_type SINGLE_ENEMY (2) / ALL_ENEMIES (3). Throwing Holy
## Water at a skeleton via autobattle silently redirected the target to
## the party's lowest-HP ally — the enemy never got hit, the ally took
## holy damage instead, and the autobattle script's "burn this on the
## undead boss" line was a silent no-op.
##
## Post-fix reads the item's target_type and routes SINGLE_ENEMY /
## ALL_ENEMIES through _retarget_enemy instead.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: _execute_item reads item target_type ────────────────

func test_execute_item_reads_target_type() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_item(")
	assert_gt(fn_idx, -1, "_execute_item must exist")
	# Slice the function body up to the next func.
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("item_target_type"),
		"_execute_item must read the item's authored target_type to pick the retargeter")
	assert_true(body.contains("ItemSystem.TargetType.SINGLE_ENEMY"),
		"_execute_item must reference SINGLE_ENEMY in its retarget decision")
	assert_true(body.contains("ItemSystem.TargetType.ALL_ENEMIES"),
		"_execute_item must reference ALL_ENEMIES in its retarget decision")


# ── Source pin: _retarget_enemy is the route for enemy-targeting items

func test_execute_item_routes_damage_items_to_retarget_enemy() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_item(")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# The decision should branch on targets_enemies and call _retarget_enemy.
	assert_true(body.contains("targets_enemies"),
		"_execute_item must compute a targets_enemies branch flag")
	assert_true(body.contains("_retarget_enemy(user, t)"),
		"_execute_item must call _retarget_enemy on damage-item targets — pre-fix _retarget_ally caught everything")


# ── Behavioral: items.json damage items ARE enemy-targeting ─────────

func test_damage_items_are_enemy_targeting_in_data() -> void:
	# Pin items.json so a future audit that flips a damage item to
	# SINGLE_ALLY (e.g. friendly-fire experimentation) doesn't silently
	# break the retarget-decision the post-fix relies on.
	var raw: String = FileAccess.get_file_as_string("res://data/items.json")
	assert_false(raw.is_empty(), "items.json must be loadable")
	var parsed: Variant = JSON.parse_string(raw)
	assert_eq(typeof(parsed), TYPE_DICTIONARY, "items.json root must be a Dictionary")
	var data: Dictionary = parsed
	# TargetType: SINGLE_ALLY=0, ALL_ALLIES=1, SINGLE_ENEMY=2, ALL_ENEMIES=3, SELF=4
	const SINGLE_ENEMY := 2
	const ALL_ENEMIES := 3
	for item_id in ["holy_water", "bomb_fragment", "lightning_bolt", "arctic_wind"]:
		assert_true(data.has(item_id), "items.json must include %s" % item_id)
		var item: Dictionary = data[item_id]
		var tt: int = int(item.get("target_type", -1))
		assert_true(tt == SINGLE_ENEMY or tt == ALL_ENEMIES,
			"%s must have enemy target_type (got %d) — fix relies on this" % [item_id, tt])
		var eff: Dictionary = item.get("effects", {})
		assert_true(eff.has("damage"),
			"%s must carry a damage effect — fix relies on this" % item_id)


# ── Behavioral: end-to-end retarget routes enemy targets correctly ──

func test_retarget_branch_behavior_dead_enemy() -> void:
	# Behavioral check pinning the WORST case of the bug. The pre-fix code
	# called _retarget_ally on every non-revival item. When the original
	# enemy target died between selection and execution (common in
	# autobattle queues), _retarget_ally's early-return short-circuit
	# missed and it found the lowest-HP ALLY instead — the live enemy
	# never got hit, and a fresh ally took the holy/fire/ice damage.
	#
	# Post-fix routes damage items through _retarget_enemy which keeps
	# the damage on enemies.
	var bm_script: GDScript = load(BATTLE_MANAGER_PATH)
	var bm: Object = bm_script.new()
	add_child_autofree(bm)

	var c_script: GDScript = load("res://src/battle/Combatant.gd")
	var ally: Combatant = c_script.new()
	ally.initialize({"name": "Ally", "max_hp": 100, "max_mp": 10,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	ally.current_hp = 50

	var live_enemy: Combatant = c_script.new()
	live_enemy.initialize({"name": "Skeleton2", "max_hp": 200, "max_mp": 10,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})

	var dead_enemy: Combatant = c_script.new()
	dead_enemy.initialize({"name": "Skeleton1", "max_hp": 200, "max_mp": 10,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	dead_enemy.is_alive = false
	dead_enemy.current_hp = 0

	var players: Array[Combatant] = [ally]
	var enemies: Array[Combatant] = [dead_enemy, live_enemy]
	bm.player_party = players
	bm.enemy_party = enemies

	# Post-fix branch: damage item with dead original target → live enemy.
	var got_enemy: Combatant = bm._retarget_enemy(ally, dead_enemy)
	assert_eq(got_enemy, live_enemy,
		"_retarget_enemy on a dead enemy must return the other live enemy")

	# Pre-fix bug surface: _retarget_ally on a dead enemy target returns
	# the ally instead. Confirms the WHOLE bug — pre-fix the call site
	# returned ally here, and ItemSystem.use_item then damaged the ally.
	var got_ally: Combatant = bm._retarget_ally(ally, dead_enemy, false)
	assert_eq(got_ally, ally,
		"_retarget_ally on dead enemy original falls back to ally — the bug pattern the call-site fix prevents")
