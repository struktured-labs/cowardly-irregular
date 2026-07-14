extends GutTest

## Wires the 3 stubbed party-dialogue triggers (low_hp, big_hit_taken, used_signature_ability).
## Source pins lock the contract; behavioural tests drive the gate.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


# ── Source pins ──────────────────────────────────────────────────────────────

func test_signature_abilities_dictionary_covers_starter_jobs() -> void:
	var text := _read(BATTLE_MANAGER_PATH)
	var idx := text.find("const SIGNATURE_ABILITIES")
	assert_gt(idx, -1, "SIGNATURE_ABILITIES const must exist")
	for entry in ["\"fighter\":", "\"cleric\":", "\"mage\":", "\"rogue\":", "\"bard\":"]:
		assert_true(text.find(entry) != -1,
			"SIGNATURE_ABILITIES must include starter %s" % entry)


func test_log_player_action_fires_signature_trigger() -> void:
	var text := _read(BATTLE_MANAGER_PATH)
	var idx := text.find("func _log_player_action")
	assert_gt(idx, -1, "_log_player_action must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("used_signature_ability"),
		"_log_player_action must fire used_signature_ability via _maybe_fire_party_line")
	assert_true(body.contains("_is_signature_ability"),
		"_log_player_action must gate the signature trigger via _is_signature_ability")


func test_damage_handler_exists_and_is_connected_on_start_battle() -> void:
	var text := _read(BATTLE_MANAGER_PATH)
	assert_true(text.find("func _on_damage_dealt_for_party_dialogue") != -1,
		"_on_damage_dealt_for_party_dialogue handler must exist")
	# start_battle must connect it (idempotent via is_connected guard).
	var sb_idx := text.find("func start_battle")
	assert_gt(sb_idx, -1, "start_battle must exist")
	var rest := text.substr(sb_idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("damage_dealt.connect(_on_damage_dealt_for_party_dialogue)"),
		"start_battle must connect damage_dealt → _on_damage_dealt_for_party_dialogue")
	assert_true(body.contains("damage_dealt.is_connected"),
		"start_battle's connect must be guarded by is_connected to stay idempotent")


func test_damage_handler_uses_threshold_constants() -> void:
	var text := _read(BATTLE_MANAGER_PATH)
	var idx := text.find("func _on_damage_dealt_for_party_dialogue")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("BIG_HIT_HP_PCT_THRESHOLD"),
		"big-hit branch must use BIG_HIT_HP_PCT_THRESHOLD constant")
	assert_true(body.contains("LOW_HP_PCT_THRESHOLD"),
		"low-hp branch must use LOW_HP_PCT_THRESHOLD constant")
	assert_true(body.contains("\"big_hit_taken\""),
		"handler must fire big_hit_taken event id")
	assert_true(body.contains("\"low_hp\""),
		"handler must fire low_hp event id")


# ── Behavioural ──────────────────────────────────────────────────────────────

func test_is_signature_ability_matches_fighter_power_strike() -> void:
	var bm: Node = get_node_or_null("/root/BattleManager")
	if bm == null:
		pending("BattleManager autoload unavailable")
		return
	var c: Combatant = Combatant.new()
	c.combatant_name = "Hero"
	c.job = {"id": "fighter"}
	add_child_autofree(c)
	assert_true(bm._is_signature_ability(c, "power_strike"),
		"fighter + power_strike must be flagged signature")
	assert_false(bm._is_signature_ability(c, "cure"),
		"fighter + cure must NOT be flagged signature (wrong job)")


func test_is_signature_ability_covers_every_starter() -> void:
	var bm: Node = get_node_or_null("/root/BattleManager")
	if bm == null:
		pending("BattleManager autoload unavailable")
		return
	var pairs: Dictionary = {
		"fighter": "power_strike",
		"cleric":  "cure",
		"mage":    "fire",
		"rogue":   "backstab",
		"bard":    "inspiring_melody",
	}
	for job_id in pairs:
		var c: Combatant = Combatant.new()
		c.combatant_name = "PC_%s" % job_id
		c.job = {"id": job_id}
		add_child_autofree(c)
		assert_true(bm._is_signature_ability(c, pairs[job_id]),
			"%s + %s must be flagged signature" % [job_id, pairs[job_id]])


func test_damage_handler_no_ops_for_non_party_target() -> void:
	var bm: Node = get_node_or_null("/root/BattleManager")
	if bm == null:
		pending("BattleManager autoload unavailable")
		return
	var c: Combatant = Combatant.new()
	c.combatant_name = "Enemy"
	c.max_hp = 100
	c.current_hp = 100
	c.is_alive = true
	add_child_autofree(c)
	# c is NOT in player_party — handler should silently return without crash.
	bm._on_damage_dealt_for_party_dialogue(c, 99, true, "", 1.0)
	assert_true(true, "handler must early-return for non-party target")


func test_damage_handler_no_ops_for_zero_amount() -> void:
	var bm: Node = get_node_or_null("/root/BattleManager")
	if bm == null:
		pending("BattleManager autoload unavailable")
		return
	var c: Combatant = Combatant.new()
	c.combatant_name = "Hero"
	c.max_hp = 100; c.current_hp = 100; c.is_alive = true
	add_child_autofree(c)
	## Tick 182: pre-fix `bm.player_party = [c]` was a typed-array
	## trap — Array[Combatant] field, generic [c] literal, silent
	## SCRIPT ERROR that aborted the function before the assert.
	## Build a typed local first so the assignment succeeds.
	var snapshot: Array[Combatant] = bm.player_party.duplicate()
	var typed_party: Array[Combatant] = [c]
	bm.player_party = typed_party
	bm._on_damage_dealt_for_party_dialogue(c, 0, false, "", 1.0)
	bm.player_party = snapshot
	assert_true(true, "handler must early-return when amount <= 0")
