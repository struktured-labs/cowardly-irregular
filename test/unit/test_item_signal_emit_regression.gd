extends GutTest

## Polish regression: ItemSystem's heal/MP/damage/revive paths now emit
## the BattleManager.damage_dealt / healing_done signals so BattleScene's
## visual feedback (damage popup + screen shake, heal popup + soft green
## glow) fires when items are used in battle.
##
## Before this fix, all four mutation paths called target.{heal,
## restore_mp, take_damage, revive} directly without emitting a signal.
## Visual result: HP/MP bar would tick but no number popup, no glow, no
## screen shake. Items felt under-acknowledged.
##
## Now each mutation captures the ACTUAL amount applied (after defense,
## curse, overcap, etc.) and emits the matching signal so the existing
## BattleScene → BattleResultsDisplay handler chain triggers naturally.
##
## Tests cover:
##   • potion heal_hp emits healing_done with the actual amount
##   • megalixir heal_hp_percent emits healing_done
##   • ether heal_mp emits healing_done as the MP-restore visual proxy
##     (CLAUDE.md convention; matches Free Move's Pray/Channel/Riff)
##   • magic_tonic heal_mp_percent emits healing_done
##   • phoenix_down revive emits healing_done with the revived HP
##   • throwing_dagger / damage path emits damage_dealt with the actual
##     post-defense damage AND the elemental data the popup uses
##   • Zero-effect cases (heal a full-HP target) do NOT spam an emit

const ITEM_SYSTEM_PATH := "res://src/items/ItemSystem.gd"


# ── Source pins (cheap, deterministic) ────────────────────────────────────────

func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


func test_heal_hp_path_emits_healing_done() -> void:
	var text := _read(ITEM_SYSTEM_PATH)
	# Find the heal_hp branch (not the percent one — both must be checked).
	var idx := text.find("if effects.has(\"heal_hp\") and not _heal_consumed_by_revive")
	assert_gt(idx, -1, "heal_hp branch must exist")
	var rest := text.substr(idx, 400)
	assert_true(rest.contains("BattleManager.healing_done.emit"),
		"heal_hp branch must emit BattleManager.healing_done so the heal popup + glow fire")


func test_heal_hp_percent_path_emits_healing_done() -> void:
	var text := _read(ITEM_SYSTEM_PATH)
	var idx := text.find("if effects.has(\"heal_hp_percent\") and not _heal_consumed_by_revive")
	assert_gt(idx, -1, "heal_hp_percent branch must exist")
	var rest := text.substr(idx, 500)
	assert_true(rest.contains("BattleManager.healing_done.emit"),
		"heal_hp_percent branch must emit BattleManager.healing_done")


func test_heal_mp_path_emits_healing_done() -> void:
	var text := _read(ITEM_SYSTEM_PATH)
	var idx := text.find("if effects.has(\"heal_mp\"):")
	assert_gt(idx, -1, "heal_mp branch must exist")
	var rest := text.substr(idx, 400)
	assert_true(rest.contains("BattleManager.healing_done.emit"),
		"heal_mp branch must emit healing_done as the MP-restore visual proxy")


func test_heal_mp_percent_path_emits_healing_done() -> void:
	var text := _read(ITEM_SYSTEM_PATH)
	var idx := text.find("if effects.has(\"heal_mp_percent\"):")
	assert_gt(idx, -1, "heal_mp_percent branch must exist")
	var rest := text.substr(idx, 500)
	assert_true(rest.contains("BattleManager.healing_done.emit"),
		"heal_mp_percent branch must emit healing_done")


func test_revive_path_emits_healing_done() -> void:
	var text := _read(ITEM_SYSTEM_PATH)
	var idx := text.find("if effects.has(\"revive\") and effects[\"revive\"]:")
	assert_gt(idx, -1, "revive branch must exist")
	var rest := text.substr(idx, 900)
	assert_true(rest.contains("target.revive("),
		"revive branch must still call target.revive() (sanity)")
	assert_true(rest.contains("BattleManager.healing_done.emit"),
		"revive branch must emit healing_done so the revived HP gets the popup + glow")


func test_damage_path_emits_damage_dealt_with_element_and_modifier() -> void:
	var text := _read(ITEM_SYSTEM_PATH)
	var idx := text.find("if effects.has(\"damage\"):")
	assert_gt(idx, -1, "damage branch must exist")
	# Damage block runs through elemental + undead handling + the emit;
	# scope the slice to the next blank-func boundary so the window can't
	# be too short to catch the emit at the bottom.
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("BattleManager.damage_dealt.emit"),
		"damage branch must emit damage_dealt so the popup + screen shake fire")
	# Spot-check the call shape carries the elemental info the popup uses.
	assert_true(body.contains("damage_dealt.emit(target, actual_damage, false, element, multiplier)"),
		"damage_dealt emit must pass (target, actual_damage, is_crit=false, element, multiplier) so the popup colours correctly")


# ── Behavioral via the live autoload ─────────────────────────────────────────

func _gs() -> Node:
	return get_node_or_null("/root/GameState")


func _is() -> Node:
	return get_node_or_null("/root/ItemSystem")


func _bm() -> Node:
	return get_node_or_null("/root/BattleManager")


func _make_target(max_hp: int = 100, hp: int = 100, max_mp: int = 50, mp: int = 50) -> Combatant:
	var t := Combatant.new()
	t.combatant_name = "Tester"
	t.max_hp = max_hp
	t.max_mp = max_mp
	add_child_autofree(t)
	# Combatant._ready() runs on add_child and resets current_hp/mp to max.
	# Set the test-specific values AFTER that so they aren't clobbered.
	t.current_hp = hp
	t.current_mp = mp
	t.defense = 0
	t.is_alive = hp > 0
	return t


func test_heal_emits_signal_with_actual_amount() -> void:
	# Live behavioural roundtrip: connect to healing_done, use a potion-like
	# item, assert the actual amount comes through.
	var item_sys := _is()
	var bm := _bm()
	if item_sys == null or bm == null:
		pending("ItemSystem/BattleManager autoload unavailable in this environment")
		return
	# Stub a potion. Use a unique id so we don't clobber a real entry on accident.
	var test_id := "_test_potion_heal_signal"
	item_sys.items[test_id] = {
		"id":          test_id,
		"name":        "Test Potion",
		"category":    item_sys.ItemCategory.CONSUMABLE,
		"target_type": item_sys.TargetType.SINGLE_ALLY,
		"effects":     {"heal_hp": 30},
	}
	var target := _make_target(100, 60)  # 40 HP missing
	var captured: Array = []
	var handler := func(emit_target, amount):
		captured.append({"target": emit_target, "amount": amount})
	bm.healing_done.connect(handler)
	# Cast to typed array so the signature matches use_item().
	var typed_targets: Array[Combatant] = [target]
	var ok: bool = item_sys.use_item(target, test_id, typed_targets)
	bm.healing_done.disconnect(handler)
	item_sys.items.erase(test_id)
	assert_true(ok, "use_item must return true on success")
	assert_eq(captured.size(), 1, "healing_done must fire exactly once per heal target")
	assert_eq(captured[0]["target"], target,
		"healing_done target arg must be the actual healed combatant")
	assert_gt(int(captured[0]["amount"]), 0,
		"healing_done amount must reflect the real positive heal (after overcap)")


func test_overcap_heal_does_not_emit_zero_amount() -> void:
	# Healing a full-HP target should result in actual=0 → no emit (we
	# don't want the popup spamming "0 HP" for ineffective use).
	var item_sys := _is()
	var bm := _bm()
	if item_sys == null or bm == null:
		pending("ItemSystem/BattleManager autoload unavailable in this environment")
		return
	var test_id := "_test_potion_overcap"
	item_sys.items[test_id] = {
		"id":          test_id,
		"name":        "Test Potion (overcap)",
		"category":    item_sys.ItemCategory.CONSUMABLE,
		"target_type": item_sys.TargetType.SINGLE_ALLY,
		"effects":     {"heal_hp": 30},
	}
	var target := _make_target(100, 100)  # Already full HP
	var captured: Array = []
	var handler := func(_t, _a):
		captured.append(1)
	bm.healing_done.connect(handler)
	var typed_targets: Array[Combatant] = [target]
	item_sys.use_item(target, test_id, typed_targets)
	bm.healing_done.disconnect(handler)
	item_sys.items.erase(test_id)
	assert_eq(captured.size(), 0,
		"healing_done must NOT fire when the heal overcapped to 0 actual HP")
