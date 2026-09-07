extends GutTest

## tick 143 regression: poison / burn / regen status-effect ticks
## must spawn floating damage/healing popups, not just silently
## drop the HP bar. Pre-fix only hp_changed emitted on these ticks,
## so the HP bar slid down but no number floated up — status
## effects felt invisible during multi-action turns.
##
## Fix: Combatant emits status_tick_damage / status_tick_heal
## signals carrying the amount + source ("poison"/"burn"/"regen").
## BattleScene connects per-Combatant in BattleEnemySpawner and
## in its own party-signals loop, calling _results_display
## with the same on_damage_dealt / on_healing_done methods used
## by regular attacks.

const COMBATANT := "res://src/battle/Combatant.gd"
const BATTLE_SCENE := "res://src/battle/BattleScene.gd"
const BATTLE_SPAWNER := "res://src/battle/BattleEnemySpawner.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Combatant signal declarations ────────────────────────────────────────

func test_combatant_declares_tick_signals() -> void:
	var src := _read(COMBATANT)
	assert_true(src.contains("signal status_tick_damage(amount: int, source: String)"),
		"status_tick_damage signal must be declared on Combatant")
	assert_true(src.contains("signal status_tick_heal(amount: int, source: String)"),
		"status_tick_heal signal must be declared on Combatant")


# ── Combatant emit sites ─────────────────────────────────────────────────

func test_poison_tick_emits_status_tick_damage() -> void:
	var src := _read(COMBATANT)
	# Look in the poison branch.
	var poison_idx: int = src.find("if \"poison\" in status_effects and is_alive:")
	assert_gt(poison_idx, -1, "poison branch must exist")
	var next_branch: int = src.find("if \"burning\"", poison_idx)
	var poison_body: String = src.substr(poison_idx, next_branch - poison_idx)
	assert_true(poison_body.contains("status_tick_damage.emit(poison_damage, \"poison\")"),
		"poison branch must emit status_tick_damage with 'poison' source")


func test_burn_tick_emits_status_tick_damage() -> void:
	var src := _read(COMBATANT)
	var burn_idx: int = src.find("if \"burning\" in status_effects and is_alive:")
	assert_gt(burn_idx, -1, "burn branch must exist")
	var next_branch: int = src.find("# Process heal-over-time effects", burn_idx)
	var burn_body: String = src.substr(burn_idx, next_branch - burn_idx)
	assert_true(burn_body.contains("status_tick_damage.emit(burn_damage, \"burn\")"),
		"burn branch must emit status_tick_damage with 'burn' source")


func test_regen_tick_emits_status_tick_heal() -> void:
	var src := _read(COMBATANT)
	var regen_idx: int = src.find("if \"regen\" in status_effects and is_alive:")
	assert_gt(regen_idx, -1, "regen branch must exist")
	var next_section: int = src.find("# Tick down status effect durations", regen_idx)
	var regen_body: String = src.substr(regen_idx, next_section - regen_idx)
	assert_true(regen_body.contains("status_tick_heal.emit(healed, \"regen\")"),
		"regen branch must emit status_tick_heal with 'regen' source")


func test_heal_only_fires_when_healing_actually_happened() -> void:
	# Negative pin: if already at max HP, regen shouldn't fire the
	# heal signal (would spawn a "0 healed" popup). The emit must
	# be inside the `if healed > 0:` guard.
	var src := _read(COMBATANT)
	var regen_idx: int = src.find("if \"regen\" in status_effects and is_alive:")
	var next_section: int = src.find("# Tick down status effect durations", regen_idx)
	var regen_body: String = src.substr(regen_idx, next_section - regen_idx)
	# `status_tick_heal.emit` must be preceded by `if healed > 0:`
	# guard. Pin the structural ordering.
	var emit_idx: int = regen_body.find("status_tick_heal.emit")
	var guard_idx: int = regen_body.find("if healed > 0:")
	assert_gt(emit_idx, -1, "regen emit must exist")
	assert_gt(guard_idx, -1, "if healed > 0 guard must exist")
	assert_lt(guard_idx, emit_idx,
		"if healed > 0 guard must precede status_tick_heal.emit — don't spawn '0 healed' popups")


# ── BattleScene signal handlers ──────────────────────────────────────────

func test_battle_scene_declares_tick_handlers() -> void:
	var src := _read(BATTLE_SCENE)
	assert_true(src.contains("func _on_status_tick_damage(amount: int, _source: String, target: Combatant) -> void:"),
		"BattleScene must declare _on_status_tick_damage handler")
	assert_true(src.contains("func _on_status_tick_heal(amount: int, _source: String, target: Combatant) -> void:"),
		"BattleScene must declare _on_status_tick_heal handler")


func test_tick_handlers_call_results_display() -> void:
	var src := _read(BATTLE_SCENE)
	# Pin: damage tick spawns via on_damage_dealt (same path as
	# regular attacks). Heal tick via on_healing_done.
	# Get _on_status_tick_damage body.
	var idx: int = src.find("func _on_status_tick_damage")
	assert_gt(idx, -1, "_on_status_tick_damage must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	assert_true(body.contains("_results_display.on_damage_dealt(target, amount, false)"),
		"_on_status_tick_damage must call _results_display.on_damage_dealt")
	# Heal handler.
	idx = src.find("func _on_status_tick_heal")
	assert_gt(idx, -1, "_on_status_tick_heal must exist")
	next_fn = src.find("\nfunc ", idx + 1)
	body = src.substr(idx, next_fn - idx)
	assert_true(body.contains("_results_display.on_healing_done(target, amount)"),
		"_on_status_tick_heal must call _results_display.on_healing_done")


func test_tick_handlers_guard_is_instance_valid() -> void:
	# Defensive: combatant could die between the tick emit and the
	# handler running (queue_free deferred). Pin the guard.
	var src := _read(BATTLE_SCENE)
	var idx: int = src.find("func _on_status_tick_damage")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	assert_true(body.contains("is_instance_valid(target)"),
		"_on_status_tick_damage must guard target with is_instance_valid")
	assert_true(body.contains("is_instance_valid(_results_display)"),
		"_on_status_tick_damage must guard _results_display too — defensive")


# ── Connect sites ────────────────────────────────────────────────────────

func test_party_members_connect_tick_signals() -> void:
	# Pin the connect in BattleScene's party loop.
	var src := _read(BATTLE_SCENE)
	assert_true(src.contains("member.status_tick_damage.connect(_on_status_tick_damage.bind(member))"),
		"party-member loop must connect status_tick_damage")
	assert_true(src.contains("member.status_tick_heal.connect(_on_status_tick_heal.bind(member))"),
		"party-member loop must connect status_tick_heal")


func test_all_enemy_spawn_paths_connect_tick_signals() -> void:
	# BattleEnemySpawner has 5 spawn paths (random encounter,
	# forced random, two boss-shape, single-boss). All must connect
	# the tick signals so enemies show popups too.
	var src := _read(BATTLE_SPAWNER)
	# Count occurrences of the tick connect.
	var dmg_count: int = 0
	var heal_count: int = 0
	var search_from: int = 0
	while true:
		var found: int = src.find("enemy.status_tick_damage.connect(_scene._on_status_tick_damage.bind(enemy))", search_from)
		if found < 0:
			break
		dmg_count += 1
		search_from = found + 1
	search_from = 0
	while true:
		var found: int = src.find("enemy.status_tick_heal.connect(_scene._on_status_tick_heal.bind(enemy))", search_from)
		if found < 0:
			break
		heal_count += 1
		search_from = found + 1
	assert_gte(dmg_count, 4,
		"BattleEnemySpawner must connect status_tick_damage on each spawn path (≥4 sites)")
	assert_gte(heal_count, 4,
		"BattleEnemySpawner must connect status_tick_heal on each spawn path (≥4 sites)")
