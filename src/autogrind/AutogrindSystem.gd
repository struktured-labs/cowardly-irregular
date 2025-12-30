extends Node

## AutogrindSystem - Automated battle grinding with escalating risk/reward
## The more efficient you grind, the more dangerous it becomes

signal grind_started()
signal grind_stopped(results: Dictionary)
signal battle_completed(battle_num: int, results: Dictionary)
signal efficiency_increased(new_multiplier: float)
signal corruption_increased(level: float)
signal interrupt_triggered(reason: String)
signal meta_boss_spawned(boss_name: String)
signal system_collapse()
signal region_cracked(region_id: String, crack_level: int)
signal autobattle_interrupted(reason: String)

## Grind state
var is_grinding: bool = false
var battles_completed: int = 0
var total_exp_gained: int = 0
var total_items_gained: Dictionary = {}

## Efficiency system
var efficiency_multiplier: float = 1.0  # Increases rewards but also danger
var max_efficiency: float = 10.0
var efficiency_growth_rate: float = 0.1  # Per battle

## Region crack detection
var region_crack_levels: Dictionary = {}  # {region_id: crack_level}
var current_region_id: String = ""
var consecutive_wins: int = 0
var wins_to_crack_region: int = 20  # Wins needed to "crack" a region
var reward_penalty_per_crack: float = 0.15  # -15% rewards per crack level

## Meta-adaptation when cracked
var adaptation_on_crack: bool = true  # Monsters adapt when region cracked

## Danger scaling
var monster_adaptation_level: float = 0.0  # Enemies get stronger
var meta_corruption_level: float = 0.0     # Reality starts breaking
var corruption_threshold: float = 5.0      # When system collapse occurs

## Interrupt conditions
var interrupt_rules: Dictionary = {
	"hp_threshold": 20.0,      # Stop if any party member HP < 20%
	"party_death": true,       # Stop if any party member dies
	"item_depleted": true,     # Stop if healing items run out
	"corruption_limit": 4.5,   # Stop before system collapse
	"max_battles": 100         # Safety limit
}

## Permadeath staking (optional high-risk mode)
var permadeath_staking_enabled: bool = false
var permadeath_multiplier: float = 3.0  # 3x rewards but permanent death on wipe

## Meta-boss triggers
var meta_bosses_enabled: bool = true
var meta_boss_spawn_chance: float = 0.0  # Increases with corruption

## Battle configuration for grinding
var grind_enemy_template: Dictionary = {}
var grind_party: Array[Combatant] = []


func _ready() -> void:
	pass


## Autogrind control
func start_autogrind(party: Array[Combatant], enemy_template: Dictionary, config: Dictionary = {}) -> void:
	"""Start automated grinding session"""
	if is_grinding:
		print("Autogrind already active!")
		return

	is_grinding = true
	battles_completed = 0
	total_exp_gained = 0
	total_items_gained.clear()
	efficiency_multiplier = 1.0
	monster_adaptation_level = 0.0
	meta_corruption_level = 0.0
	meta_boss_spawn_chance = 0.0

	grind_party = party.duplicate()
	grind_enemy_template = enemy_template.duplicate()

	# Apply custom config
	if config.has("interrupt_rules"):
		for key in config["interrupt_rules"]:
			interrupt_rules[key] = config["interrupt_rules"][key]

	if config.has("permadeath_staking"):
		permadeath_staking_enabled = config["permadeath_staking"]

	grind_started.emit()
	print("=== AUTOGRIND STARTED ===")
	print("Efficiency: %.1fx | Corruption: %.2f" % [efficiency_multiplier, meta_corruption_level])

	_process_grind_loop()


func stop_autogrind(reason: String = "Manual stop") -> void:
	"""Stop autogrind and return results"""
	if not is_grinding:
		return

	is_grinding = false

	var results = {
		"battles_completed": battles_completed,
		"total_exp_gained": total_exp_gained,
		"total_items_gained": total_items_gained.duplicate(),
		"final_efficiency": efficiency_multiplier,
		"corruption_level": meta_corruption_level,
		"stop_reason": reason
	}

	grind_stopped.emit(results)
	print("=== AUTOGRIND STOPPED ===")
	print("Reason: %s" % reason)
	print("Battles: %d | EXP: %d | Efficiency: %.1fx" % [
		battles_completed, total_exp_gained, efficiency_multiplier
	])


func _process_grind_loop() -> void:
	"""Main autogrind loop - runs battles automatically"""
	while is_grinding:
		# Check interrupt conditions before battle
		var interrupt_reason = _check_interrupt_conditions()
		if interrupt_reason != "":
			interrupt_triggered.emit(interrupt_reason)
			stop_autogrind(interrupt_reason)
			return

		# Check for meta-boss spawn
		if meta_bosses_enabled and randf() < meta_boss_spawn_chance:
			_spawn_meta_boss()

		# Start automated battle
		_run_automated_battle()

		# Wait for battle to complete (in real implementation, this would be async)
		await get_tree().create_timer(0.1).timeout


func _run_automated_battle() -> void:
	"""Run a single automated battle"""
	battles_completed += 1

	# Create adapted enemy (gets stronger with monster_adaptation_level)
	var enemy = _create_adapted_enemy()

	# Simulate battle (in full implementation, this would run actual battle)
	var battle_result = _simulate_battle(grind_party, [enemy])

	# Process results
	_process_battle_results(battle_result)

	# Increase efficiency and danger
	_increase_efficiency()

	battle_completed.emit(battles_completed, battle_result)


func _create_adapted_enemy() -> Dictionary:
	"""Create enemy adapted to player's efficiency (gets stronger)"""
	var enemy = grind_enemy_template.duplicate(true)

	# Apply monster adaptation (enemies scale with efficiency)
	var adaptation_bonus = monster_adaptation_level * 0.15  # +15% stats per level
	enemy["max_hp"] = int(enemy.get("max_hp", 100) * (1.0 + adaptation_bonus))
	enemy["attack"] = int(enemy.get("attack", 10) * (1.0 + adaptation_bonus))
	enemy["defense"] = int(enemy.get("defense", 10) * (1.0 + adaptation_bonus))
	enemy["magic"] = int(enemy.get("magic", 10) * (1.0 + adaptation_bonus))

	# Apply meta-corruption effects (enemies gain weird abilities)
	if meta_corruption_level >= 2.0:
		enemy["corruption_effects"] = _get_corruption_effects()

	return enemy


func _get_corruption_effects() -> Array:
	"""Get corruption-based enemy modifications"""
	var effects = []

	if meta_corruption_level >= 2.0:
		effects.append("reality_bending")  # Damage ignores defense

	if meta_corruption_level >= 3.0:
		effects.append("time_distortion")  # Acts twice per turn

	if meta_corruption_level >= 4.0:
		effects.append("stat_drain")  # Permanently reduces player stats

	return effects


func _simulate_battle(party: Array, enemies: Array) -> Dictionary:
	"""Simulate a battle (simplified for autogrind)"""
	# In full implementation, this would run actual battle
	# For now, simulate based on stats

	var party_power = 0.0
	for member in party:
		if member is Combatant:
			party_power += member.attack + member.magic + member.defense

	var enemy_power = 0.0
	for enemy in enemies:
		enemy_power += enemy.get("attack", 10) + enemy.get("magic", 10) + enemy.get("defense", 10)

	# Victory if party is stronger (with some randomness)
	var victory = (party_power > enemy_power * 0.8) and randf() < 0.9

	# Calculate rewards with efficiency multiplier
	var exp_gained = int(50 * efficiency_multiplier)
	if permadeath_staking_enabled:
		exp_gained = int(exp_gained * permadeath_multiplier)

	var items_gained = {}
	if victory and randf() < 0.3 * efficiency_multiplier:
		items_gained["potion"] = 1

	return {
		"victory": victory,
		"exp_gained": exp_gained,
		"items_gained": items_gained
	}


func _process_battle_results(result: Dictionary) -> void:
	"""Process battle results and update grind stats"""
	if result["victory"]:
		# Track consecutive wins for region crack detection
		consecutive_wins += 1
		_check_region_crack()

		# Apply region crack penalty to rewards
		var crack_penalty = _get_region_crack_penalty()
		var adjusted_exp = int(result["exp_gained"] * (1.0 - crack_penalty))

		total_exp_gained += adjusted_exp

		# Add items
		for item_id in result["items_gained"]:
			var quantity = result["items_gained"][item_id]
			if total_items_gained.has(item_id):
				total_items_gained[item_id] += quantity
			else:
				total_items_gained[item_id] = quantity

		# Award EXP to party
		for member in grind_party:
			if member is Combatant and member.is_alive:
				member.gain_job_exp(adjusted_exp)

		# Show penalty if region is cracked
		if crack_penalty > 0:
			print("[color=yellow]Region cracked! Rewards reduced by %.0f%%[/color]" % (crack_penalty * 100))
	else:
		# Defeat - reset consecutive wins
		consecutive_wins = 0

		# Check permadeath
		if permadeath_staking_enabled:
			_trigger_permadeath()
		stop_autogrind("Party defeated")


func _increase_efficiency() -> void:
	"""Increase efficiency multiplier and associated dangers"""
	var old_efficiency = efficiency_multiplier

	# Increase efficiency
	efficiency_multiplier = min(efficiency_multiplier + efficiency_growth_rate, max_efficiency)

	# Increase monster adaptation
	monster_adaptation_level += 0.05

	# Increase meta-corruption (danger!)
	var corruption_gain = 0.02 * efficiency_multiplier
	meta_corruption_level += corruption_gain

	# Increase meta-boss spawn chance
	meta_boss_spawn_chance = min(meta_corruption_level * 0.05, 0.3)

	if efficiency_multiplier > old_efficiency:
		efficiency_increased.emit(efficiency_multiplier)

	if meta_corruption_level >= corruption_threshold:
		_trigger_system_collapse()

	corruption_increased.emit(meta_corruption_level)


func _check_interrupt_conditions() -> String:
	"""Check if any interrupt conditions are met, returns reason or empty string"""
	# Check HP threshold
	if interrupt_rules.get("hp_threshold", 0) > 0:
		for member in grind_party:
			if member is Combatant and member.get_hp_percentage() < interrupt_rules["hp_threshold"]:
				return "HP threshold reached (%d%%)" % interrupt_rules["hp_threshold"]

	# Check party death
	if interrupt_rules.get("party_death", false):
		for member in grind_party:
			if member is Combatant and not member.is_alive:
				return "Party member died"

	# Check item depletion
	if interrupt_rules.get("item_depleted", false):
		var has_healing_items = false
		for member in grind_party:
			if member is Combatant:
				if member.get_item_count("potion") > 0 or member.get_item_count("hi_potion") > 0:
					has_healing_items = true
					break
		if not has_healing_items:
			return "Healing items depleted"

	# Check corruption limit
	if meta_corruption_level >= interrupt_rules.get("corruption_limit", 999.0):
		return "Corruption limit reached (%.1f)" % meta_corruption_level

	# Check max battles
	if battles_completed >= interrupt_rules.get("max_battles", 999):
		return "Max battles reached (%d)" % battles_completed

	return ""


func _spawn_meta_boss() -> void:
	"""Spawn a meta-boss due to corruption"""
	var boss_name = _generate_meta_boss_name()
	meta_boss_spawned.emit(boss_name)
	print("[color=red]⚠ META-BOSS SPAWNED: %s ⚠[/color]" % boss_name)

	# In full implementation, this would create an actual boss fight
	# For now, just increase corruption and stop grinding
	meta_corruption_level += 1.0
	stop_autogrind("Meta-boss appeared: %s" % boss_name)


func _generate_meta_boss_name() -> String:
	"""Generate creepy meta-boss name based on corruption"""
	var prefixes = ["Glitch", "Corrupted", "Fragmented", "Recursive", "Null"]
	var suffixes = ["Witness", "Observer", "Process", "Handler", "Exception"]

	return "%s %s" % [
		prefixes[randi() % prefixes.size()],
		suffixes[randi() % suffixes.size()]
	]


func _trigger_system_collapse() -> void:
	"""Trigger system collapse event (max corruption reached)"""
	system_collapse.emit()
	print("[color=purple]=== SYSTEM COLLAPSE ===[/color]")
	print("Meta-corruption has reached critical levels!")
	print("Reality is fragmenting...")

	# Spawn multiple meta-bosses
	for i in range(3):
		_spawn_meta_boss()

	stop_autogrind("SYSTEM COLLAPSE")


func _trigger_permadeath() -> void:
	"""Handle permadeath when staking is enabled"""
	print("[color=red]=== PERMADEATH TRIGGERED ===[/color]")
	print("Your party has been permanently lost to the grind...")

	# Mark all party members as permanently dead
	for member in grind_party:
		if member is Combatant:
			member.is_alive = false
			# In full implementation, would save this to persistent data

	stop_autogrind("PERMADEATH - Party wiped with staking enabled")


## Configuration
func set_interrupt_rule(rule_name: String, value: Variant) -> void:
	"""Set an interrupt rule"""
	interrupt_rules[rule_name] = value
	print("Interrupt rule set: %s = %s" % [rule_name, value])


func enable_permadeath_staking(enabled: bool) -> void:
	"""Enable/disable permadeath staking"""
	permadeath_staking_enabled = enabled
	print("Permadeath staking: %s (%.1fx rewards)" % [
		"ENABLED" if enabled else "disabled",
		permadeath_multiplier if enabled else 1.0
	])


## Region crack system
func set_current_region(region_id: String) -> void:
	"""Set the current region for crack tracking"""
	if current_region_id != region_id:
		current_region_id = region_id
		consecutive_wins = 0  # Reset on region change

		if not region_crack_levels.has(region_id):
			region_crack_levels[region_id] = 0


func _check_region_crack() -> void:
	"""Check if region should crack (player has mastered it)"""
	if current_region_id.is_empty():
		return

	if consecutive_wins >= wins_to_crack_region:
		# Region cracked! Increase crack level
		var old_level = region_crack_levels.get(current_region_id, 0)
		region_crack_levels[current_region_id] = old_level + 1
		consecutive_wins = 0  # Reset for next crack level

		var new_level = region_crack_levels[current_region_id]
		region_cracked.emit(current_region_id, new_level)

		print("[color=red]═══ REGION CRACKED ═══[/color]")
		print("The game has detected you've mastered this area!")
		print("Crack Level: %d" % new_level)
		print("Monsters will adapt - rewards decreased %.0f%%" % (new_level * reward_penalty_per_crack * 100))
		print("[color=yellow]Move to a new area or devise new strategies![/color]")

		# Apply meta-adaptation
		if adaptation_on_crack:
			_apply_meta_adaptation(new_level)


func _apply_meta_adaptation(crack_level: int) -> void:
	"""Apply meta-adaptation when region is cracked"""
	# Increase monster adaptation significantly
	monster_adaptation_level += crack_level * 0.3  # +30% stats per crack level

	# Monsters gain new behaviors
	print("[color=purple]Monsters are adapting...[/color]")
	if crack_level >= 1:
		print("  - Enemies now counter your common strategies")
	if crack_level >= 2:
		print("  - Enemies prioritize interrupting your autobattle logic")
	if crack_level >= 3:
		print("  - Enemies exploit weaknesses in your script")
		# Could trigger corruption increase
		meta_corruption_level += 0.5


func _get_region_crack_penalty() -> float:
	"""Get reward penalty based on region crack level"""
	if current_region_id.is_empty():
		return 0.0

	var crack_level = region_crack_levels.get(current_region_id, 0)
	return min(crack_level * reward_penalty_per_crack, 0.75)  # Max 75% penalty


func get_region_crack_level(region_id: String) -> int:
	"""Get crack level for a region"""
	return region_crack_levels.get(region_id, 0)


func is_region_cracked(region_id: String) -> bool:
	"""Check if a region is cracked"""
	return region_crack_levels.get(region_id, 0) > 0


## Autobattle interrupt system
func check_autobattle_interrupt(combatant: Combatant) -> String:
	"""Check if autobattle should interrupt to manual control"""
	# Check HP danger
	if combatant.get_hp_percentage() < 30.0:
		return "Low HP - interrupting to manual control"

	# Check if about to die (enemy can one-shot)
	# In full implementation, would calculate enemy damage

	# Check if surrounded (multiple enemies targeting)
	# In full implementation, would check battle state

	return ""  # No interrupt


func interrupt_to_manual(reason: String) -> void:
	"""Interrupt autobattle/autogrind to manual control"""
	if is_grinding:
		stop_autogrind(reason)

	autobattle_interrupted.emit(reason)
	print("[color=orange]⚠ AUTOBATTLE INTERRUPTED ⚠[/color]")
	print("Reason: %s" % reason)
	print("Switching to manual control...")

	# In full implementation, would disable autobattle and return control to player
