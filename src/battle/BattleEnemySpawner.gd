extends RefCounted
class_name BattleEnemySpawner

## BattleEnemySpawner - Handles enemy creation and spawning for battle encounters
## Extracted from BattleScene to reduce god class complexity

var _scene  # Reference to parent BattleScene (untyped to avoid circular dependency)

## Available monster types for random encounters
const MONSTER_TYPES = [
	{
		"id": "slime",
		"name": "Slime",
		"color": Color(0.3, 0.8, 0.3),
		"stats": {"max_hp": 80, "max_mp": 20, "attack": 10, "defense": 8, "magic": 5, "speed": 8},
		"weaknesses": ["fire"],
		"resistances": ["ice"]
	},
	{
		"id": "bat",
		"name": "Bat",
		"color": Color(0.4, 0.3, 0.5),
		"stats": {"max_hp": 50, "max_mp": 15, "attack": 12, "defense": 5, "magic": 6, "speed": 18},
		"weaknesses": ["fire", "lightning"],
		"resistances": []
	},
	{
		"id": "mushroom",
		"name": "Fungoid",
		"color": Color(0.6, 0.4, 0.3),
		"stats": {"max_hp": 100, "max_mp": 25, "attack": 8, "defense": 12, "magic": 10, "speed": 5},
		"weaknesses": ["fire"],
		"resistances": ["poison"]
	},
	{
		"id": "imp",
		"name": "Imp",
		"color": Color(0.8, 0.3, 0.3),
		"stats": {"max_hp": 70, "max_mp": 50, "attack": 8, "defense": 8, "magic": 18, "speed": 14},
		"weaknesses": ["ice", "holy"],
		"resistances": ["fire", "dark"]
	},
	{
		"id": "goblin",
		"name": "Goblin",
		"color": Color(0.5, 0.6, 0.3),
		"stats": {"max_hp": 120, "max_mp": 30, "attack": 15, "defense": 10, "magic": 8, "speed": 12},
		"weaknesses": ["lightning"],
		"resistances": []
	},
	{
		"id": "skeleton",
		"name": "Skeleton",
		"color": Color(0.9, 0.9, 0.85),
		"stats": {"max_hp": 90, "max_mp": 10, "attack": 14, "defense": 6, "magic": 3, "speed": 10},
		"weaknesses": ["holy", "fire"],
		"resistances": ["dark", "poison"]
	},
	{
		"id": "wolf",
		"name": "Dire Wolf",
		"color": Color(0.4, 0.35, 0.3),
		"stats": {"max_hp": 110, "max_mp": 15, "attack": 18, "defense": 8, "magic": 4, "speed": 16},
		"weaknesses": ["fire"],
		"resistances": ["ice"]
	},
	{
		"id": "ghost",
		"name": "Specter",
		"color": Color(0.7, 0.8, 0.9),
		"stats": {"max_hp": 60, "max_mp": 80, "attack": 6, "defense": 4, "magic": 20, "speed": 14},
		"weaknesses": ["holy"],
		"resistances": ["physical", "dark"]
	},
	{
		"id": "snake",
		"name": "Viper",
		"color": Color(0.3, 0.5, 0.2),
		"stats": {"max_hp": 70, "max_mp": 30, "attack": 12, "defense": 7, "magic": 8, "speed": 20},
		"weaknesses": ["ice"],
		"resistances": ["poison"]
	},
	{
		"id": "cave_rat",
		"name": "Cave Rat",
		"color": Color(0.45, 0.35, 0.3),
		"stats": {"max_hp": 90, "max_mp": 15, "attack": 30, "defense": 8, "magic": 10, "speed": 14},
		"weaknesses": ["fire"],
		"resistances": []
	},
	{
		"id": "rat_guard",
		"name": "Rat Guard",
		"color": Color(0.4, 0.35, 0.35),
		"stats": {"max_hp": 160, "max_mp": 25, "attack": 40, "defense": 18, "magic": 12, "speed": 11},
		"weaknesses": ["lightning"],
		"resistances": ["physical"]
	}
]

const MINIBOSS_TYPES = [
	{
		"id": "cave_troll",
		"name": "Cave Troll",
		"stats": {"max_hp": 400, "max_mp": 30, "attack": 55, "defense": 25, "magic": 10, "speed": 6},
		"weaknesses": ["fire", "lightning"],
		"resistances": ["ice"]
	},
	{
		"id": "shadow_knight",
		"name": "Shadow Knight",
		"stats": {"max_hp": 350, "max_mp": 80, "attack": 48, "defense": 30, "magic": 25, "speed": 12},
		"weaknesses": ["holy", "fire"],
		"resistances": ["dark", "ice"]
	}
]


func _init(scene) -> void:
	_scene = scene


func spawn_enemies() -> void:
	"""Spawn 1-3 random enemies for the battle - sometimes mixed groups"""
	# Clear any existing enemies
	for enemy in _scene.test_enemies:
		if is_instance_valid(enemy):
			# Disconnect known signals before freeing to prevent dangling connections
			if enemy.hp_changed.get_connections().size() > 0:
				for conn in enemy.hp_changed.get_connections():
					enemy.hp_changed.disconnect(conn.callable)
			if enemy.died.get_connections().size() > 0:
				for conn in enemy.died.get_connections():
					enemy.died.disconnect(conn.callable)
			enemy.queue_free()
	_scene.test_enemies.clear()

	# Check for autogrind pre-configured enemies
	if _scene.autogrind_enemy_data.size() > 0:
		spawn_from_data(_scene.autogrind_enemy_data)
		return

	# Check for encounter enemies from exploration (world-specific monsters)
	if _scene.encounter_enemies.size() > 0:
		spawn_encounter_enemies()
		return

	# Check for forced specific enemies (e.g., boss battles)
	if _scene.forced_enemies.size() > 0:
		spawn_forced_enemies()
		return

	# Check for miniboss battle
	if _scene.force_miniboss:
		spawn_miniboss()
		return

	# Random number of enemies (2-3, limited by available positions)
	var max_enemies = mini(3, _scene.enemy_positions.size())
	var num_enemies = randi_range(2, max_enemies)

	# 40% chance of mixed group, 60% chance of same type
	var use_mixed_group = randf() < 0.4 and num_enemies > 1

	# Pick monster types for this encounter
	var monster_types_for_encounter: Array = []
	if use_mixed_group:
		# Pick different types for each enemy
		var available_types = MONSTER_TYPES.duplicate()
		available_types.shuffle()
		for i in range(num_enemies):
			monster_types_for_encounter.append(available_types[i % available_types.size()])
	else:
		# All same type
		var monster_type = MONSTER_TYPES[randi() % MONSTER_TYPES.size()]
		for i in range(num_enemies):
			monster_types_for_encounter.append(monster_type)

	# Track names for encounter message
	var enemy_names: Dictionary = {}

	for i in range(num_enemies):
		var monster_type = monster_types_for_encounter[i]
		var enemy = Combatant.new()

		# Count how many of this type we've spawned for suffix
		var type_count = 0
		for j in range(i):
			if monster_types_for_encounter[j]["id"] == monster_type["id"]:
				type_count += 1

		var stats = monster_type["stats"].duplicate()
		# Only add suffix if there are multiple of the same type
		var same_type_total = monster_types_for_encounter.count(monster_type)
		if same_type_total > 1:
			stats["name"] = monster_type["name"] + " " + ["A", "B", "C"][type_count]
		else:
			stats["name"] = monster_type["name"]

		# Slight speed variation for turn order variety
		stats["speed"] = stats["speed"] + i
		enemy.initialize(stats)
		_scene.add_child(enemy)

		# Store monster type ID for sprite selection
		enemy.set_meta("monster_type", monster_type["id"])

		# Add weaknesses/resistances from monster type
		for weakness in monster_type.get("weaknesses", []):
			enemy.elemental_weaknesses.append(weakness)
		for resistance in monster_type.get("resistances", []):
			enemy.elemental_resistances.append(resistance)

		# Connect signals
		enemy.hp_changed.connect(_scene._on_enemy_hp_changed.bind(i))
		enemy.died.connect(_scene._on_enemy_died.bind(i))

		_scene.test_enemies.append(enemy)

		# Track for message
		if monster_type["name"] in enemy_names:
			enemy_names[monster_type["name"]] += 1
		else:
			enemy_names[monster_type["name"]] = 1

	# Build encounter message
	var msg_parts: Array = []
	for enemy_name in enemy_names:
		var count = enemy_names[enemy_name]
		if count > 1:
			msg_parts.append("%d %s" % [count, enemy_name + "s"])
		else:
			msg_parts.append("1 %s" % enemy_name)
	_scene.log_message("[color=gray]%s appeared![/color]" % " and ".join(msg_parts))

	_scene._update_ui()


func spawn_from_data(enemy_data_array: Array) -> void:
	"""Spawn enemies from pre-configured data dictionaries (used by autogrind system)"""
	var enemy_names: Dictionary = {}
	var max_enemies = mini(enemy_data_array.size(), _scene.enemy_positions.size())

	for i in range(max_enemies):
		var data = enemy_data_array[i]
		var enemy = Combatant.new()

		var stats = {}
		if data.has("stats"):
			stats = data["stats"].duplicate()
		else:
			stats = {
				"max_hp": data.get("max_hp", 100),
				"max_mp": data.get("max_mp", 20),
				"attack": data.get("attack", 10),
				"defense": data.get("defense", 10),
				"magic": data.get("magic", 10),
				"speed": data.get("speed", 8)
			}

		# Count duplicates for suffixing
		var type_id = data.get("id", "unknown")
		var type_name = data.get("name", "Monster")
		var same_type_count = 0
		for j in range(i):
			if enemy_data_array[j].get("id", "") == type_id:
				same_type_count += 1

		var total_same = 0
		for ed in enemy_data_array:
			if ed.get("id", "") == type_id:
				total_same += 1

		if total_same > 1:
			stats["name"] = type_name + " " + ["A", "B", "C"][same_type_count % 3]
		else:
			stats["name"] = type_name

		# Slight speed variation
		stats["speed"] = stats.get("speed", 8) + i

		enemy.initialize(stats)
		_scene.add_child(enemy)

		# Store monster type ID for sprite selection
		enemy.set_meta("monster_type", type_id)

		# Add weaknesses/resistances from data
		for weakness in data.get("weaknesses", []):
			enemy.elemental_weaknesses.append(weakness)
		for resistance in data.get("resistances", []):
			enemy.elemental_resistances.append(resistance)

		# Store corruption effects if present
		if data.has("corruption_effects"):
			enemy.set_meta("corruption_effects", data["corruption_effects"])

		# Store counter strategy if present (set by AutogrindSystem.create_scaled_enemy_data)
		if data.has("counter_strategy") and not data["counter_strategy"].is_empty():
			enemy.set_meta("counter_strategy", data["counter_strategy"])

		# Connect signals
		enemy.hp_changed.connect(_scene._on_enemy_hp_changed.bind(i))
		enemy.died.connect(_scene._on_enemy_died.bind(i))

		_scene.test_enemies.append(enemy)

		# Track for encounter message
		if type_name in enemy_names:
			enemy_names[type_name] += 1
		else:
			enemy_names[type_name] = 1

	# Build encounter message
	var msg_parts: Array = []
	for enemy_name in enemy_names:
		var count = enemy_names[enemy_name]
		if count > 1:
			msg_parts.append("%d %s" % [count, enemy_name + "s"])
		else:
			msg_parts.append("1 %s" % enemy_name)
	_scene.log_message("[color=gray]%s appeared![/color]" % " and ".join(msg_parts))

	_scene._update_ui()


func spawn_forced_enemies() -> void:
	"""Spawn specific enemies from the forced_enemies array (e.g., boss battles)"""
	# Load monster data
	var monsters_data = load_monsters_data()
	if monsters_data.is_empty():
		push_error("Failed to load monsters.json - falling back to random enemies")
		_scene.forced_enemies.clear()
		spawn_enemies()
		return

	var enemy_names: Array = []
	var is_boss_battle = false

	for i in range(_scene.forced_enemies.size()):
		var enemy_id = _scene.forced_enemies[i]
		if not monsters_data.has(enemy_id):
			push_warning("Unknown monster ID: %s" % enemy_id)
			continue

		var monster_data = monsters_data[enemy_id]
		var enemy = Combatant.new()
		var stats = {
			"name": monster_data.get("name", enemy_id),
			"max_hp": monster_data["stats"].get("max_hp", 100),
			"max_mp": monster_data["stats"].get("max_mp", 0),
			"attack": monster_data["stats"].get("attack", 10),
			"defense": monster_data["stats"].get("defense", 5),
			"magic": monster_data["stats"].get("magic", 5),
			"speed": monster_data["stats"].get("speed", 10)
		}
		enemy.initialize(stats)
		_scene.add_child(enemy)

		# Store monster type ID for sprite selection
		enemy.set_meta("monster_type", enemy_id)
		if monster_data.get("boss", false) or monster_data.get("miniboss", false):
			enemy.set_meta("is_boss", true)
			enemy.set_meta("is_miniboss", true)  # For music selection
			is_boss_battle = true
			# Store dialogue data for this boss
			if monster_data.has("dialogue"):
				_scene._boss_dialogue_data = monster_data["dialogue"]

		# Set abilities from monster data so AI can use them
		if monster_data.has("abilities"):
			enemy.job = {"abilities": monster_data["abilities"], "name": monster_data.get("name", enemy_id)}

		# Store Masterite metadata for specialized AI
		if monster_data.get("masterite", false):
			enemy.set_meta("masterite", true)
			enemy.set_meta("masterite_type", monster_data.get("masterite_type", ""))
			enemy.set_meta("masterite_phase", monster_data.get("masterite_phase", 1))

		# Connect signals
		enemy.hp_changed.connect(_scene._on_enemy_hp_changed.bind(i))
		enemy.died.connect(_scene._on_enemy_died.bind(i))

		_scene.test_enemies.append(enemy)
		enemy_names.append(stats["name"])

	# Announcement based on battle type
	if is_boss_battle:
		_scene.log_message("")
		_scene.log_message("[color=red]═══════════════════════════════[/color]")
		_scene.log_message("[color=orange]   👑  BOSS BATTLE!  👑[/color]")
		for enemy_name in enemy_names:
			_scene.log_message("[color=yellow]   %s appeared![/color]" % enemy_name)
		_scene.log_message("[color=red]═══════════════════════════════[/color]")
		_scene.log_message("")
	else:
		for enemy_name in enemy_names:
			_scene.log_message("[color=yellow]%s appeared![/color]" % enemy_name)

	_scene._update_ui()


func spawn_encounter_enemies() -> void:
	"""Spawn enemies from encounter_enemies IDs (world-specific random encounters)"""
	var monsters_data = load_monsters_data()

	var valid_ids: Array = []
	for eid in _scene.encounter_enemies:
		if monsters_data.has(eid):
			valid_ids.append(eid)
		else:
			push_warning("Unknown encounter enemy ID: %s — skipping" % eid)

	# Fall back to hardcoded MONSTER_TYPES if no valid IDs found
	if valid_ids.is_empty():
		push_warning("No valid encounter enemies found, falling back to defaults")
		_scene.encounter_enemies.clear()
		spawn_enemies()
		return

	var max_enemies = mini(valid_ids.size(), _scene.enemy_positions.size())
	var enemy_names: Dictionary = {}

	for i in range(max_enemies):
		var enemy_id = valid_ids[i]
		var monster_data = monsters_data[enemy_id]
		var enemy = Combatant.new()

		var stats = {
			"name": monster_data.get("name", enemy_id),
			"max_hp": monster_data["stats"].get("max_hp", 100),
			"max_mp": monster_data["stats"].get("max_mp", 0),
			"attack": monster_data["stats"].get("attack", 10),
			"defense": monster_data["stats"].get("defense", 5),
			"magic": monster_data["stats"].get("magic", 5),
			"speed": monster_data["stats"].get("speed", 10)
		}

		# Count duplicates for suffixing (e.g., Clockwork Sentinel A, B, C)
		var same_type_count = 0
		for j in range(i):
			if valid_ids[j] == enemy_id:
				same_type_count += 1
		var total_same = valid_ids.count(enemy_id)
		if total_same > 1:
			stats["name"] = stats["name"] + " " + ["A", "B", "C"][same_type_count % 3]

		# Slight speed variation for turn order variety
		stats["speed"] = stats["speed"] + i

		enemy.initialize(stats)
		_scene.add_child(enemy)

		# Store monster type ID for sprite selection
		enemy.set_meta("monster_type", enemy_id)

		# Set abilities from monster data so AI can use them
		if monster_data.has("abilities"):
			enemy.job = {"abilities": monster_data["abilities"], "name": monster_data.get("name", enemy_id)}

		# Store Masterite metadata for specialized AI
		if monster_data.get("masterite", false):
			enemy.set_meta("masterite", true)
			enemy.set_meta("masterite_type", monster_data.get("masterite_type", ""))

		# Add weaknesses/resistances from monster data
		for weakness in monster_data.get("weaknesses", []):
			enemy.elemental_weaknesses.append(weakness)
		for resistance in monster_data.get("resistances", []):
			enemy.elemental_resistances.append(resistance)

		# Connect signals
		enemy.hp_changed.connect(_scene._on_enemy_hp_changed.bind(i))
		enemy.died.connect(_scene._on_enemy_died.bind(i))

		_scene.test_enemies.append(enemy)

		# Track for encounter message
		var display_name = monster_data.get("name", enemy_id)
		if display_name in enemy_names:
			enemy_names[display_name] += 1
		else:
			enemy_names[display_name] = 1

	# Build encounter message
	var msg_parts: Array = []
	for enemy_name in enemy_names:
		var count = enemy_names[enemy_name]
		if count > 1:
			msg_parts.append("%d %s" % [count, enemy_name + "s"])
		else:
			msg_parts.append("1 %s" % enemy_name)
	_scene.log_message("[color=gray]%s appeared![/color]" % " and ".join(msg_parts))

	_scene._update_ui()


func load_monsters_data() -> Dictionary:
	"""Get monster definitions from EncounterSystem autoload (cached at startup)"""
	if EncounterSystem and not EncounterSystem.monster_database.is_empty():
		return EncounterSystem.monster_database
	# Fallback: load from disk if autoload unavailable (e.g., tests)
	var file_path = "res://data/monsters.json"
	if not FileAccess.file_exists(file_path):
		return {}
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return {}
	var json_string = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(json_string) == OK:
		return json.data
	return {}


func spawn_miniboss() -> void:
	"""Spawn a single miniboss enemy"""
	# Pick a random miniboss
	var boss_type = MINIBOSS_TYPES[randi() % MINIBOSS_TYPES.size()]

	var enemy = Combatant.new()
	var stats = boss_type["stats"].duplicate()
	stats["name"] = boss_type["name"]
	enemy.initialize(stats)
	_scene.add_child(enemy)

	# Store monster type ID for sprite selection
	enemy.set_meta("monster_type", boss_type["id"])
	enemy.set_meta("is_miniboss", true)

	# Add weaknesses/resistances
	for weakness in boss_type.get("weaknesses", []):
		enemy.elemental_weaknesses.append(weakness)
	for resistance in boss_type.get("resistances", []):
		enemy.elemental_resistances.append(resistance)

	# Connect signals
	enemy.hp_changed.connect(_scene._on_enemy_hp_changed.bind(0))
	enemy.died.connect(_scene._on_enemy_died.bind(0))

	_scene.test_enemies.append(enemy)

	# Epic announcement!
	_scene.log_message("")
	_scene.log_message("[color=red]═══════════════════════════════[/color]")
	_scene.log_message("[color=orange]   ⚔️  MINIBOSS BATTLE!  ⚔️[/color]")
	_scene.log_message("[color=yellow]   %s appeared![/color]" % boss_type["name"])
	_scene.log_message("[color=red]═══════════════════════════════[/color]")
	_scene.log_message("")

	_scene._update_ui()
