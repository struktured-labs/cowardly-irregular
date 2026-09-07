extends GutTest

## tick 442: shared_damage passive's meta_effects.boss_damage_share
## now actually redirects a share of damage from a mind-swapped boss
## back to the controller.
##
## Pre-fix passives.json authored:
##   shared_damage: {meta_effects: {boss_damage_share: 0.5}}
##   description: "When controlling a boss, damage is split 50/50
##     between you and the boss"
## but no code path read the field — the passive was decoration.
## boss_control_swap (Bossbinder Mind Swap) applied mind_swap status
## with no controller link, so even if the field had been read there
## was no way to find who to redirect to.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const COMBATANT_PATH := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _make(name_str: String, max_hp: int = 100) -> Combatant:
	var c_script: GDScript = load(COMBATANT_PATH)
	var c: Combatant = c_script.new()
	c.initialize({"name": name_str, "max_hp": max_hp, "max_mp": 50,
		"attack": 10, "defense": 0, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func test_swap_sets_controller_meta() -> void:
	# Pin that boss_control_swap stores _mind_swap_controller meta so
	# the take_damage redirect has somewhere to look.
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("\"boss_control_swap\":")
	assert_gt(fn_idx, -1)
	# Window wide enough to cover the long fix comment block.
	var window: String = src.substr(fn_idx, 1500)
	assert_true(window.contains("set_meta(\"_mind_swap_controller\", caster)"),
		"boss_control_swap must store the caster as _mind_swap_controller on the target")


func test_break_clears_controller_meta() -> void:
	# Pin that break_mind_swap also wipes the controller meta — a
	# released boss must not still redirect to a stale controller.
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("\"break_mind_swap\":")
	assert_gt(fn_idx, -1)
	var window: String = src.substr(fn_idx, 700)
	assert_true(window.contains("remove_meta(\"_mind_swap_controller\")"),
		"break_mind_swap must clear _mind_swap_controller so a stale link can't redirect")


func test_take_damage_uses_meta_effect() -> void:
	var src := _read(COMBATANT_PATH)
	var fn_idx: int = src.find("func take_damage")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_get_passive_meta_effect_sum(\"boss_damage_share\")"),
		"take_damage must consult the controller's boss_damage_share")
	# Pin the redirect call.
	assert_true(body.contains("ctrl.take_damage(redirect_amount, is_magical)"),
		"take_damage must call ctrl.take_damage with the redirect share")
	# Pin reentrancy guard.
	assert_true(body.contains("_in_shared_damage_redirect"),
		"take_damage must use a reentrancy guard so A→B→A loops can't recurse")


func test_data_still_authors_share() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/passives.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("shared_damage"))
	var me: Variant = data["shared_damage"].get("meta_effects", {})
	assert_true(me is Dictionary)
	assert_gt(float(me.get("boss_damage_share", 0.0)), 0.0,
		"shared_damage passive must still author boss_damage_share > 0")


func test_runtime_no_swap_no_redirect() -> void:
	# Boss without mind_swap takes full damage, controller takes none.
	var boss: Combatant = _make("Boss", 1000)
	boss.current_hp = 500
	var ctrl: Combatant = _make("Controller", 1000)
	ctrl.current_hp = 500
	boss.take_damage(100, false)
	assert_lt(boss.current_hp, 500, "non-swapped boss must take damage")
	assert_eq(ctrl.current_hp, 500,
		"controller must NOT take redirected damage when no swap is active")


func test_runtime_swap_with_passive_redirects() -> void:
	# With mind_swap + controller meta + shared_damage equipped on
	# controller, half of the damage goes to the controller.
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null:
		pending("PassiveSystem autoload required")
		return
	if not ps.passives.has("shared_damage"):
		pending("shared_damage passive required")
		return
	var boss: Combatant = _make("BossB", 1000)
	boss.current_hp = 1000
	boss.add_status("mind_swap", 5)
	var ctrl: Combatant = _make("CtrlB", 1000)
	ctrl.current_hp = 1000
	ctrl.equipped_passives = ["shared_damage"]
	boss.set_meta("_mind_swap_controller", ctrl)
	# Use a large damage so the def=0 formula path leaves clear non-1 numbers.
	boss.take_damage(200, false)
	# Boss should have taken roughly half, controller should have
	# taken roughly half. Some int rounding plus the boss's residual
	# half going through the defense formula will skew the boss's
	# final loss, but the controller must have been hit.
	assert_lt(ctrl.current_hp, 1000,
		"controller must lose HP when boss is hit with shared_damage equipped")


func test_runtime_swap_without_passive_no_redirect() -> void:
	# Mind swap active but controller does NOT have shared_damage —
	# no redirect. This isolates the passive from the swap status.
	var boss: Combatant = _make("BossC", 1000)
	boss.current_hp = 1000
	boss.add_status("mind_swap", 5)
	var ctrl: Combatant = _make("CtrlC", 1000)
	ctrl.current_hp = 1000
	ctrl.equipped_passives = []
	boss.set_meta("_mind_swap_controller", ctrl)
	boss.take_damage(100, false)
	assert_eq(ctrl.current_hp, 1000,
		"controller without shared_damage equipped must NOT take redirected damage")


func test_runtime_dead_controller_no_redirect() -> void:
	# Edge case: controller is dead — the redirect must skip them so
	# damage doesn't silently vanish.
	var ps = Engine.get_main_loop().root.get_node_or_null("PassiveSystem")
	if ps == null:
		pending("PassiveSystem autoload required")
		return
	if not ps.passives.has("shared_damage"):
		pending("shared_damage passive required")
		return
	var boss: Combatant = _make("BossD", 1000)
	boss.current_hp = 1000
	boss.add_status("mind_swap", 5)
	var ctrl: Combatant = _make("CtrlD", 1000)
	ctrl.equipped_passives = ["shared_damage"]
	ctrl.current_hp = 0
	ctrl.is_alive = false
	boss.set_meta("_mind_swap_controller", ctrl)
	var boss_hp_before: int = boss.current_hp
	boss.take_damage(100, false)
	assert_lt(boss.current_hp, boss_hp_before,
		"boss must take full damage when controller is dead (no redirect target)")
