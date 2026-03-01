extends RefCounted
class_name BattleCommandMenu

## BattleCommandMenu - Handles Win98-style command menu creation and interaction
## Extracted from BattleScene to reduce god class complexity

const Win98MenuClass = preload("res://src/ui/Win98Menu.gd")

var _scene  # Reference to parent BattleScene (untyped to avoid circular dependency)

## Cached alive enemies list per selection turn to avoid recomputation
var _cached_alive_enemies: Array[Combatant] = []
var _alive_enemies_cache_valid: bool = false


func _init(scene) -> void:
	_scene = scene


func invalidate_alive_cache() -> void:
	"""Invalidate the alive enemies cache (call on selection turn start/end or enemy death)"""
	_alive_enemies_cache_valid = false


func get_alive_enemies() -> Array[Combatant]:
	"""Get all alive enemies (cached per selection turn)"""
	if _alive_enemies_cache_valid:
		return _cached_alive_enemies
	_cached_alive_enemies.clear()
	for enemy in _scene.test_enemies:
		if is_instance_valid(enemy) and enemy.is_alive:
			_cached_alive_enemies.append(enemy)
	_alive_enemies_cache_valid = true
	return _cached_alive_enemies


func show_win98_command_menu(combatant: Combatant) -> void:
	"""Show retro command menu for the combatant"""
	# Close any existing menu
	close_win98_menu()

	# Get character's sprite position (use BattleManager.player_party for correct object identity)
	var combatant_idx = BattleManager.player_party.find(combatant)
	if combatant_idx < 0 or combatant_idx >= _scene.party_sprite_nodes.size():
		return

	var sprite = _scene.party_sprite_nodes[combatant_idx]
	if not is_instance_valid(sprite):
		return

	var viewport_size = _scene.get_viewport_rect().size

	# Convert sprite position to screen coordinates
	var canvas_transform = _scene.get_viewport().get_canvas_transform()
	var screen_pos = canvas_transform * sprite.global_position

	# Position menu to the LEFT of the character sprite (menu expands left)
	var menu_x = clamp(screen_pos.x - 150, 10, viewport_size.x - 150)
	var menu_y = clamp(screen_pos.y - 40, 10, viewport_size.y - 120)
	var menu_pos = Vector2(menu_x, menu_y)

	# Get character class for styling
	var job_id = combatant.job.get("id", "fighter") if combatant.job else "fighter"

	# Build menu items with enemy targets as submenus
	var menu_items = build_command_menu_items_with_targets(combatant)

	# Create menu directly as child with high z_index
	_scene.active_win98_menu = Win98MenuClass.new()
	_scene.active_win98_menu.expand_left = true  # Expand submenus to the left
	_scene.active_win98_menu.expand_up = true  # Expand submenus upward
	_scene.active_win98_menu.is_root_menu = true  # Root menu can't be closed
	_scene.active_win98_menu.z_index = 100  # Render on top
	_scene.active_win98_menu.visible = true  # Ensure visible
	_scene.add_child(_scene.active_win98_menu)
	_scene.active_win98_menu.setup(combatant.combatant_name, menu_items, menu_pos, job_id)

	# Connect signals
	_scene.active_win98_menu.item_selected.connect(_on_win98_menu_selection)
	_scene.active_win98_menu.menu_closed.connect(_on_win98_menu_closed)
	_scene.active_win98_menu.actions_submitted.connect(_on_win98_actions_submitted)
	_scene.active_win98_menu.defer_requested.connect(_on_win98_defer_requested)
	_scene.active_win98_menu.go_back_requested.connect(_on_win98_go_back_requested)

	# Set max queue size and current AP for display
	var ap_limit = combatant.current_ap + 4
	var max_queue = mini(4, maxi(1, ap_limit))
	_scene.active_win98_menu.set_max_queue_size(max_queue)
	_scene.active_win98_menu.set_current_ap(combatant.current_ap)

	# Allow going back if not the first player in selection order
	var can_go_back = BattleManager.selection_index > 0
	_scene.active_win98_menu.set_can_go_back(can_go_back)

	# Apply command memory if enabled
	if _scene.command_memory_enabled and combatant.last_menu_selection != "":
		print("[CMD MEM] Applying %s -> %s" % [combatant.combatant_name, combatant.last_menu_selection])
		var submenu_memory = {}
		if combatant.last_attack_selection != "":
			submenu_memory["attack_menu"] = combatant.last_attack_selection
		if combatant.last_ability_selection != "":
			submenu_memory["ability_menu"] = combatant.last_ability_selection
		if combatant.last_item_selection != "":
			submenu_memory["item_menu"] = combatant.last_item_selection
		print("[CMD MEM] Submenu memory: %s" % str(submenu_memory))
		_scene.active_win98_menu.set_command_memory(combatant.last_menu_selection, submenu_memory)


func build_command_menu_items_with_targets(combatant: Combatant) -> Array:
	"""Build command menu with enemy targets as submenus"""
	var items = []
	var alive_enemies = get_alive_enemies()
	var canvas_transform = _scene.get_viewport().get_canvas_transform()

	# Autobattle option at the top
	items.append({
		"id": "autobattle",
		"label": "Auto",
		"data": {"action": "autobattle", "combatant": combatant}
	})

	# Attack -> submenu of enemy targets
	if alive_enemies.size() > 0:
		var enemy_targets = []
		for enemy in alive_enemies:
			var enemy_idx = _scene.test_enemies.find(enemy)
			var target_pos = Vector2.ZERO
			if enemy_idx >= 0 and enemy_idx < _scene.enemy_sprite_nodes.size():
				var s = _scene.enemy_sprite_nodes[enemy_idx]
				if is_instance_valid(s):
					target_pos = canvas_transform * s.global_position
			enemy_targets.append({
				"id": "attack_" + str(enemy_idx),
				"label": "%s (%d HP)" % [enemy.combatant_name, enemy.current_hp],
				"data": {"target_idx": enemy_idx, "action": "attack", "target_pos": target_pos}
			})
		items.append({
			"id": "attack_menu",
			"label": "Attack",
			"submenu": enemy_targets
		})
	else:
		items.append({
			"id": "attack",
			"label": "Attack",
			"data": null,
			"disabled": true
		})

	# Abilities -> submenu, each ability has enemy targets if offensive
	var job_abilities = combatant.job.get("abilities", []) if combatant.job else []
	var abilities = job_abilities.duplicate()
	for learned_id in combatant.learned_abilities:
		if learned_id not in abilities:
			abilities.append(learned_id)
	if abilities.size() > 0:
		var ability_items = []
		for ability_id in abilities:
			var ability = JobSystem.get_ability(ability_id)
			if ability.is_empty():
				continue
			var mp_cost = ability.get("mp_cost", 0)
			var can_afford = combatant.current_mp >= mp_cost
			var target_type = ability.get("target_type", "single_enemy")

			# For enemy-targeting abilities, add enemy submenu
			if target_type == "single_enemy" and alive_enemies.size() > 0 and can_afford:
				var enemy_targets = []
				for enemy in alive_enemies:
					var enemy_idx = _scene.test_enemies.find(enemy)
					var target_pos = Vector2.ZERO
					if enemy_idx >= 0 and enemy_idx < _scene.enemy_sprite_nodes.size():
						var s = _scene.enemy_sprite_nodes[enemy_idx]
						if is_instance_valid(s):
							target_pos = canvas_transform * s.global_position
					enemy_targets.append({
						"id": "ability_" + ability_id + "_enemy_" + str(enemy_idx),
						"label": "%s (%d HP)" % [enemy.combatant_name, enemy.current_hp],
						"data": {"ability_id": ability_id, "target_idx": enemy_idx, "target_type": "enemy", "target_pos": target_pos}
					})
				ability_items.append({
					"id": "ability_menu_" + ability_id,
					"label": "%s (%d)" % [ability["name"], mp_cost],
					"submenu": enemy_targets,
					"disabled": not can_afford
				})
			# For ally-targeting abilities (heal, buff), add party submenu
			elif target_type == "single_ally" and can_afford:
				var ally_targets = []
				for i in range(_scene.party_members.size()):
					var member = _scene.party_members[i]
					if not is_instance_valid(member) or not member.is_alive:
						continue
					var target_pos = Vector2.ZERO
					if i < _scene.party_sprite_nodes.size():
						var s = _scene.party_sprite_nodes[i]
						if is_instance_valid(s):
							target_pos = canvas_transform * s.global_position
					ally_targets.append({
						"id": "ability_" + ability_id + "_ally_" + str(i),
						"label": "%s (%d/%d HP)" % [member.combatant_name, member.current_hp, member.max_hp],
						"data": {"ability_id": ability_id, "target_idx": i, "target_type": "ally", "target_pos": target_pos}
					})
				ability_items.append({
					"id": "ability_menu_" + ability_id,
					"label": "%s (%d)" % [ability["name"], mp_cost],
					"submenu": ally_targets,
					"disabled": not can_afford
				})
			# For dead ally targeting (Raise, Phoenix Down), show only dead party members
			elif target_type == "dead_ally" and can_afford:
				var dead_targets = []
				for i in range(_scene.party_members.size()):
					var member = _scene.party_members[i]
					if not is_instance_valid(member) or member.is_alive:
						continue  # Skip alive members
					var target_pos = Vector2.ZERO
					if i < _scene.party_sprite_nodes.size():
						var s = _scene.party_sprite_nodes[i]
						if is_instance_valid(s):
							target_pos = canvas_transform * s.global_position
					dead_targets.append({
						"id": "ability_" + ability_id + "_dead_" + str(i),
						"label": "%s (KO)" % member.combatant_name,
						"data": {"ability_id": ability_id, "target_idx": i, "target_type": "dead_ally", "target_pos": target_pos}
					})
				# Only show if there are dead allies to revive
				if dead_targets.size() > 0:
					ability_items.append({
						"id": "ability_menu_" + ability_id,
						"label": "%s (%d)" % [ability["name"], mp_cost],
						"submenu": dead_targets,
						"disabled": not can_afford
					})
				else:
					# Show disabled if no dead allies
					ability_items.append({
						"id": "ability_" + ability_id,
						"label": "%s (%d)" % [ability["name"], mp_cost],
						"data": {"ability_id": ability_id},
						"disabled": true
					})
			else:
				ability_items.append({
					"id": "ability_" + ability_id,
					"label": "%s (%d)" % [ability["name"], mp_cost],
					"data": {"ability_id": ability_id},
					"disabled": not can_afford
				})

		if ability_items.size() > 0:
			items.append({
				"id": "ability_menu",
				"label": "Ability",
				"submenu": ability_items
			})

	# Items submenu
	if not combatant.inventory.is_empty():
		var item_items = []
		for item_id in combatant.inventory.keys():
			var item = ItemSystem.get_item(item_id)
			if item.is_empty():
				continue
			var quantity = combatant.inventory[item_id]
			var target_type = item.get("target_type", ItemSystem.TargetType.SINGLE_ALLY)

			# For SINGLE_ALLY items, add party member target submenu
			if target_type == ItemSystem.TargetType.SINGLE_ALLY:
				var ally_targets = []
				for i in range(_scene.party_members.size()):
					var member = _scene.party_members[i]
					if not is_instance_valid(member) or not member.is_alive:
						continue
					var target_pos = Vector2.ZERO
					if i < _scene.party_sprite_nodes.size():
						var s = _scene.party_sprite_nodes[i]
						if is_instance_valid(s):
							target_pos = canvas_transform * s.global_position
					ally_targets.append({
						"id": "item_" + item_id + "_ally_" + str(i),
						"label": "%s (%d/%d HP)" % [member.combatant_name, member.current_hp, member.max_hp],
						"data": {"item_id": item_id, "target_idx": i, "target_type": "ally", "target_pos": target_pos}
					})
				if ally_targets.size() > 0:
					item_items.append({
						"id": "item_menu_" + item_id,
						"label": "%s x%d" % [item["name"], quantity],
						"submenu": ally_targets
					})
			# For SINGLE_ENEMY items, add enemy target submenu
			elif target_type == ItemSystem.TargetType.SINGLE_ENEMY and alive_enemies.size() > 0:
				var enemy_targets = []
				for enemy in alive_enemies:
					var enemy_idx = _scene.test_enemies.find(enemy)
					var target_pos = Vector2.ZERO
					if enemy_idx >= 0 and enemy_idx < _scene.enemy_sprite_nodes.size():
						var s = _scene.enemy_sprite_nodes[enemy_idx]
						if is_instance_valid(s):
							target_pos = canvas_transform * s.global_position
					enemy_targets.append({
						"id": "item_" + item_id + "_enemy_" + str(enemy_idx),
						"label": "%s (%d HP)" % [enemy.combatant_name, enemy.current_hp],
						"data": {"item_id": item_id, "target_idx": enemy_idx, "target_type": "enemy", "target_pos": target_pos}
					})
				item_items.append({
					"id": "item_menu_" + item_id,
					"label": "%s x%d" % [item["name"], quantity],
					"submenu": enemy_targets
				})
			else:
				# Other target types (ALL_ALLIES, ALL_ENEMIES, SELF) don't need submenu
				item_items.append({
					"id": "item_" + item_id,
					"label": "%s x%d" % [item["name"], quantity],
					"data": {"item_id": item_id}
				})
		if item_items.size() > 0:
			items.append({
				"id": "item_menu",
				"label": "Item",
				"submenu": item_items
			})

	# Defer - skip turn, gain +1 AP (only available if AP < 4)
	items.append({
		"id": "defer",
		"label": "Defer",
		"data": null,
		"disabled": combatant.current_ap >= 4
	})

	return items


func _on_win98_menu_selection(item_id: String, item_data: Variant) -> void:
	"""Handle Win98 menu item selection"""
	# Force close menu first before processing action
	close_win98_menu()

	var alive_enemies = get_alive_enemies()
	var current = BattleManager.current_combatant

	# Save command memory for next turn
	if current and _scene.command_memory_enabled:
		if item_id.begins_with("attack_"):
			current.last_menu_selection = "attack_menu"
			current.last_attack_selection = item_id
			print("[CMD MEM] %s -> attack_menu / %s (single action)" % [current.combatant_name, item_id])
		elif item_id.begins_with("ability_") or (item_data is Dictionary and item_data.has("ability_id")):
			current.last_menu_selection = "ability_menu"
			if item_data is Dictionary and item_data.has("ability_id"):
				var ability_id = item_data.get("ability_id", "")
				if item_id.begins_with("ability_menu_"):
					current.last_ability_selection = item_id.substr(0, item_id.find("_enemy_") if "_enemy_" in item_id else item_id.length())
				elif "_enemy_" in item_id or "_ally_" in item_id:
					current.last_ability_selection = "ability_menu_" + ability_id
				else:
					current.last_ability_selection = item_id
			print("[CMD MEM] %s -> ability_menu / %s (single action)" % [current.combatant_name, current.last_ability_selection])
		elif item_id.begins_with("item_"):
			current.last_menu_selection = "item_menu"
			if item_data is Dictionary and item_data.has("item_id"):
				var i_id = item_data.get("item_id", "")
				if "_ally_" in item_id or "_enemy_" in item_id:
					current.last_item_selection = "item_menu_" + i_id
				else:
					current.last_item_selection = item_id
			print("[CMD MEM] %s -> item_menu / %s (single action)" % [current.combatant_name, current.last_item_selection])

	# Autobattle - toggle autobattle ON for this player and execute their turn
	if item_id == "autobattle" and item_data is Dictionary:
		var combatant_for_auto = item_data.get("combatant", null)
		if combatant_for_auto:
			var char_id = combatant_for_auto.combatant_name.to_lower().replace(" ", "_")
			AutobattleSystem.set_autobattle_enabled(char_id, true)
			SoundManager.play_ui("autobattle_on")
			_scene.log_message("[color=lime]%s: Autobattle enabled[/color]" % combatant_for_auto.combatant_name)
			print("[AUTOBATTLE] %s enabled - executing auto turn" % combatant_for_auto.combatant_name)
			BattleManager.execute_autobattle_for_current()
			_scene._update_ui()
		return

	# Attack with target from menu tree
	if item_id.begins_with("attack_") and item_data is Dictionary:
		var target_idx = item_data.get("target_idx", -1)
		if target_idx >= 0 and target_idx < _scene.test_enemies.size():
			var target = _scene.test_enemies[target_idx]
			if is_instance_valid(target) and target.is_alive:
				_scene._execute_attack(target)
			else:
				_scene.log_message("Target no longer valid!")
		return

	# Ability with target from menu tree (enemy or ally)
	if item_data is Dictionary and item_data.has("ability_id") and item_data.has("target_idx"):
		var ability_id = item_data.get("ability_id", "")
		var target_idx = item_data.get("target_idx", -1)
		var target_type = item_data.get("target_type", "enemy")

		if ability_id != "" and target_idx >= 0:
			var target: Combatant = null

			if target_type == "ally" or target_type == "dead_ally":
				if target_idx < _scene.party_members.size():
					target = _scene.party_members[target_idx]
			else:
				if target_idx < _scene.test_enemies.size():
					target = _scene.test_enemies[target_idx]

			var is_valid_target = false
			if is_instance_valid(target):
				if target_type == "dead_ally":
					is_valid_target = not target.is_alive
				else:
					is_valid_target = target.is_alive

			if is_valid_target:
				_scene._execute_ability(ability_id, target)
			else:
				_scene.log_message("Target no longer valid!")
		return

	# Ability without pre-selected target (self/ally targeting or all enemies)
	if item_id.begins_with("ability_") and item_data is Dictionary:
		var ability_id = item_data.get("ability_id", "")
		if ability_id != "":
			var ability = JobSystem.get_ability(ability_id)
			var target_type = ability.get("target_type", "single_enemy")

			match target_type:
				"all_enemies":
					if alive_enemies.size() > 0:
						_scene._execute_ability(ability_id, alive_enemies[0], true)
					else:
						_scene.log_message("No valid targets!")
				"single_ally", "all_allies", "self":
					var ab_target = current if current else (_scene.party_members[0] if _scene.party_members.size() > 0 else null)
					if ab_target:
						_scene._execute_ability(ability_id, ab_target)
				_:
					if alive_enemies.size() > 0:
						_scene._execute_ability(ability_id, alive_enemies[0])
		return

	# Item usage with target from menu tree
	if item_id.begins_with("item_") and item_data is Dictionary:
		var i_id = item_data.get("item_id", "")
		if i_id == "":
			return

		if item_data.has("target_idx"):
			var target_idx = item_data.get("target_idx", -1)
			var target_type_str = item_data.get("target_type", "ally")
			var target: Combatant = null

			if target_type_str == "ally" and target_idx >= 0 and target_idx < _scene.party_members.size():
				target = _scene.party_members[target_idx]
			elif target_type_str == "enemy" and target_idx >= 0 and target_idx < _scene.test_enemies.size():
				target = _scene.test_enemies[target_idx]

			if is_instance_valid(target) and target.is_alive:
				BattleManager.player_item(i_id, [target])
			else:
				_scene.log_message("Target no longer valid!")
			return

		# Fallback: no pre-selected target
		var item = ItemSystem.get_item(i_id)
		var targets = []
		var target_type = item.get("target_type", ItemSystem.TargetType.SINGLE_ALLY)

		match target_type:
			ItemSystem.TargetType.SINGLE_ENEMY:
				if alive_enemies.size() > 0:
					targets = [alive_enemies[0]]
			ItemSystem.TargetType.ALL_ENEMIES:
				targets = alive_enemies
			ItemSystem.TargetType.SINGLE_ALLY, ItemSystem.TargetType.ALL_ALLIES, ItemSystem.TargetType.SELF:
				var it_target = current if current else (_scene.party_members[0] if _scene.party_members.size() > 0 else null)
				if it_target:
					targets = [it_target]

		if targets.size() > 0:
			BattleManager.player_item(i_id, targets)
		else:
			_scene.log_message("No valid targets!")
		return

	# Defer - skip turn, gain +1 AP
	if item_id == "defer":
		_scene.log_message("[color=cyan]%s defers![/color]" % current.combatant_name)
		BattleManager.player_defer()
		_scene._update_ui()
		return


func _on_win98_menu_closed() -> void:
	"""Handle Win98 menu being closed"""
	_scene.active_win98_menu = null


func _on_win98_actions_submitted(actions: Array) -> void:
	"""Handle multiple actions submitted via Advance mode (Brave)"""
	_scene.active_win98_menu = null
	var current = BattleManager.current_combatant
	if not current:
		return

	# Store command memory from first action (for next turn)
	if actions.size() > 0 and _scene.command_memory_enabled:
		var first_action = actions[0]
		var mem_action_id: String = first_action.get("id", "")
		var mem_action_data = first_action.get("data", null)

		if mem_action_id.begins_with("attack_"):
			current.last_menu_selection = "attack_menu"
			current.last_attack_selection = mem_action_id
			print("[CMD MEM] %s -> attack_menu / %s (advance)" % [current.combatant_name, mem_action_id])
		elif mem_action_id.begins_with("ability_"):
			current.last_menu_selection = "ability_menu"
			if mem_action_data is Dictionary:
				var ability_id = mem_action_data.get("ability_id", "")
				if mem_action_id.begins_with("ability_menu_"):
					current.last_ability_selection = mem_action_id.substr(0, mem_action_id.find("_enemy_") if "_enemy_" in mem_action_id else mem_action_id.length())
				elif "_enemy_" in mem_action_id or "_ally_" in mem_action_id:
					current.last_ability_selection = "ability_menu_" + ability_id
				else:
					current.last_ability_selection = mem_action_id
			print("[CMD MEM] %s -> ability_menu / %s (advance)" % [current.combatant_name, current.last_ability_selection])
		elif mem_action_id.begins_with("item_"):
			current.last_menu_selection = "item_menu"
			if mem_action_data is Dictionary:
				var i_id = mem_action_data.get("item_id", "")
				if "_ally_" in mem_action_id or "_enemy_" in mem_action_id:
					current.last_item_selection = "item_menu_" + i_id
				else:
					current.last_item_selection = mem_action_id
			print("[CMD MEM] %s -> item_menu / %s (advance)" % [current.combatant_name, current.last_item_selection])

	# Convert menu actions to battle actions
	var battle_actions: Array[Dictionary] = []
	for action in actions:
		var action_id: String = action.get("id", "")
		var action_data = action.get("data", null)

		# Handle attack actions
		if action_id.begins_with("attack_") and action_data is Dictionary:
			var target_idx = action_data.get("target_idx", -1)
			if target_idx >= 0 and target_idx < _scene.test_enemies.size():
				var target = _scene.test_enemies[target_idx]
				if is_instance_valid(target) and target.is_alive:
					battle_actions.append({"type": "attack", "target": target})
				else:
					_scene.log_message("[color=gray]Target no longer valid, skipping action[/color]")

		# Handle ability actions (enemy, ally, or dead ally targets)
		elif action_id.begins_with("ability_") and action_data is Dictionary:
			var ability_id = action_data.get("ability_id", "")
			var target_idx = action_data.get("target_idx", -1)
			var target_type = action_data.get("target_type", "enemy")

			if target_idx >= 0:
				var target: Combatant = null
				if (target_type == "ally" or target_type == "dead_ally") and target_idx < _scene.party_members.size():
					target = _scene.party_members[target_idx]
				elif target_idx < _scene.test_enemies.size():
					target = _scene.test_enemies[target_idx]

				if is_instance_valid(target):
					battle_actions.append({"type": "ability", "ability_id": ability_id, "targets": [target]})

		# Handle item actions (enemy or ally targets)
		elif action_id.begins_with("item_") and action_data is Dictionary:
			var item_id = action_data.get("item_id", "")
			var target_idx = action_data.get("target_idx", -1)
			var target_type = action_data.get("target_type", "ally")

			if target_idx >= 0:
				var target: Combatant = null
				if target_type == "ally" and target_idx < _scene.party_members.size():
					target = _scene.party_members[target_idx]
				elif target_idx < _scene.test_enemies.size():
					target = _scene.test_enemies[target_idx]

				if is_instance_valid(target):
					battle_actions.append({"type": "item", "item_id": item_id, "targets": [target]})

	if battle_actions.size() > 0:
		_scene.log_message("[color=yellow]%s advances with %d actions![/color]" % [current.combatant_name, battle_actions.size()])
		BattleManager.player_advance(battle_actions)
		_scene._update_ui()


func _on_win98_defer_requested() -> void:
	"""Handle L button defer request (no queue)"""
	_scene.active_win98_menu = null
	var current = BattleManager.current_combatant
	if not current:
		return

	_scene.log_message("[color=cyan]%s defers![/color]" % current.combatant_name)
	BattleManager.player_defer()
	_scene._update_ui()


func _on_win98_go_back_requested() -> void:
	"""Handle B button request to go back to previous player"""
	if _scene.active_win98_menu and is_instance_valid(_scene.active_win98_menu):
		_scene.active_win98_menu.force_close()
		_scene.active_win98_menu = null
	BattleManager.go_back_to_previous_player()

	# Disable autobattle for the player we went back to
	var new_current = BattleManager.current_combatant
	if new_current and new_current in _scene.party_members:
		var char_id = new_current.combatant_name.to_lower().replace(" ", "_")
		if AutobattleSystem.is_autobattle_enabled(char_id):
			AutobattleSystem.set_autobattle_enabled(char_id, false)
			SoundManager.play_ui("autobattle_off")
			_scene.log_message("[color=gray]%s: Autobattle disabled (manual control)[/color]" % new_current.combatant_name)
			_scene._update_ui()


func close_win98_menu() -> void:
	"""Close the active Win98 menu"""
	if _scene.active_win98_menu and is_instance_valid(_scene.active_win98_menu):
		_scene.active_win98_menu.force_close()
		_scene.active_win98_menu = null
