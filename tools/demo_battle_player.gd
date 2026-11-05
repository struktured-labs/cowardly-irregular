extends Node
class_name DemoBattlePlayer

## Plays battles like a person for the Indie Hall demo reel (cowir-main 22251): it only ever sends REAL input actions
## (ui_up/ui_down/ui_accept/battle_advance/battle_defer, each a press and a release, through Input.parse_input_event)
## and reads live state to choose. It never calls BattleManager to act. Every pause is game time that the battle's
## speed cannot compress (create_timer(t, true, false, true)), which under Movie Maker is exactly video time.
## Add it to the tree; it plays whatever battle, cutscene line or victory screen is in front of it.
##   intro_read_lines: lines of a boss intro shown at a reading pace before confirming through the rest.
## Every choice is printed as `[DEMO] <member>: <why> -> <path>`.

var intro_read_lines: int = 2
## Seconds the victory screen is held before confirming: a boss win lets "The Weight Lifts" land (music 22267).
var victory_hold: float = 2.6
var enabled: bool = true
var _rng := RandomNumberGenerator.new()
var _group_used := false
var _seen_line := -1
var _busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_run()


func _beat(lo: float, hi: float = -1.0) -> void:
	var t := lo if hi < 0.0 else _rng.randf_range(lo, hi)
	await get_tree().create_timer(t, true, false, true).timeout


## One real press and release of an input action.
func press(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await _beat(0.08)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await _beat(0.05)


func _gl() -> Node:
	return get_tree().root.get_node_or_null("GameLoop")


func _battle_scene() -> Node:
	var gl := _gl()
	var s = gl.get("current_scene") if gl else null
	return s if s != null and is_instance_valid(s) and "active_win98_menu" in s else null


func _cutscene_dialogue() -> Node:
	var gl := _gl()
	if gl == null or not gl.has_method("get_cutscene_director"):
		return null
	var d = gl.get_cutscene_director()
	var dlg = d.get("_dialogue") if d != null else null
	return dlg if dlg != null and is_instance_valid(dlg) else null


func _run() -> void:
	while is_inside_tree():
		await get_tree().process_frame
		if not enabled or _busy:
			continue
		_busy = true
		await _step()
		_busy = false


func _step() -> void:
	var dlg := _cutscene_dialogue()
	if dlg != null and dlg.visible and (dlg.get("_dialogue_queue") as Array).size() > 0:
		await _read_line(dlg)
		return
	var scene := _battle_scene()
	if scene == null:
		return
	var bd = scene.get("_battle_dialogue")
	if bd != null and is_instance_valid(bd) and bd.visible:
		await _beat(1.6, 2.4)
		await press("ui_accept")
		return
	if scene.get_node_or_null("VictoryResults") != null:
		await _beat(victory_hold, victory_hold + 0.6)
		await press("ui_accept")
		await _beat(1.0)
		return
	var menu = scene.get("active_win98_menu")
	if BattleManager.current_state == BattleManager.BattleState.PLAYER_SELECTING and menu != null \
			and is_instance_valid(menu) and menu.visible and menu.get("_can_accept_input") == true:
		await _take_turn(scene, menu)


## A boss intro: the first `intro_read_lines` lines are read (typing done, the voice clip finished, a reading beat),
## then the rest are confirmed through at a brisker human pace. Never Back (a single Back skips the scene).
func _read_line(dlg: Node) -> void:
	var idx: int = int(dlg.get("_current_index"))
	var reading: bool = idx < intro_read_lines
	var waited := 0.0
	while dlg.get("_is_typing") == true and waited < 8.0:
		await _beat(0.05)
		waited += 0.05
	if idx != _seen_line:
		_seen_line = idx
		var voice: float = float(dlg.get("_line_voice_sec"))
		if reading:
			await _beat(maxf(voice, 0.0) + _rng.randf_range(1.4, 2.2))
		else:
			await _beat(maxf(voice * 0.6, 0.0) + _rng.randf_range(0.5, 0.8))
	await press("ui_accept")
	await _beat(0.25)


# ── Policy ───────────────────────────────────────────────────────────────────

func _living(arr: Array) -> Array:
	return arr.filter(func(c): return c != null and is_instance_valid(c) and c.is_alive)


func _hp_frac(c) -> float:
	return float(c.current_hp) / float(maxi(1, c.max_hp))


func _knows(pc, aid: String) -> bool:
	return aid in pc.learned_abilities and not JobSystem.get_ability(aid).is_empty() \
			and JobSystem.get_ability_mp_cost(pc, aid) <= pc.current_mp


func _plan(scene: Node, pc) -> Dictionary:
	var party: Array = _living(BattleManager.player_party)
	var foes: Array = _living(scene.get("test_enemies"))
	if foes.is_empty():
		return {}
	var target = foes[0]
	for f in foes:
		if _hp_frac(f) < _hp_frac(target):
			target = f
	var t_idx: int = (scene.get("test_enemies") as Array).find(target)
	# Heal the lowest ally under 40%, before anything else.
	var hurt = null
	for m in party:
		if _hp_frac(m) < 0.40 and (hurt == null or _hp_frac(m) < _hp_frac(hurt)):
			hurt = m
	if hurt != null:
		var h_idx: int = BattleManager.player_party.find(hurt)
		for aid in ["curaga", "cura", "cure"]:
			if _knows(pc, aid):
				return {"why": "%s at %d%%, heal" % [hurt.combatant_name, int(_hp_frac(hurt) * 100)],
					"steps": [{"path": ["ability_menu", ["ability_menu_" + aid, "ability_" + aid], "ability_%s_ally_%d" % [aid, h_idx]], "commit": "accept"}]}
		for iid in ["hi_potion", "potion"]:
			if ItemSystem.party_item_count(BattleManager.consumable_bag(pc), iid) > 0:
				return {"why": "%s at %d%%, potion" % [hurt.combatant_name, int(_hp_frac(hurt) * 100)],
					"steps": [{"path": ["item_menu", "item_menu_" + iid, "item_%s_ally_%d" % [iid, h_idx]], "commit": "accept"}]}
	# A telegraphed big hit, or AP in debt: Defer and take it on the chin.
	var telegraph := false
	for f in foes:
		if f.has_method("has_status") and (f.has_status("storm_charging") or f.has_status("charging")):
			telegraph = true
	if pc.current_ap <= -1 or (telegraph and pc.current_ap < 2):
		return {"why": "AP %d%s, defer" % [pc.current_ap, " and a telegraphed strike" if telegraph else ""], "defer": true}
	# The whole party banked AP: one group attack per battle.
	if not _group_used and party.size() >= 3 and party.all(func(m): return m.current_ap >= 2):
		_group_used = true
		return {"why": "party AP all >= 2, group attack", "steps": [{"path": ["group_menu", "group_all_out"], "commit": "accept", "target": t_idx}]}
	var strike := _best_strike(pc, t_idx)
	# AP in hand and a foe low: burst it with a queued Advance.
	if pc.current_ap >= 1 and _hp_frac(target) < 0.35:
		var n: int = clampi(pc.current_ap + 1, 2, 3)
		var steps: Array = []
		for i in n:
			steps.append({"path": strike, "commit": "advance" if i < n - 1 else "accept"})
		return {"why": "%s at %d%%, advance x%d" % [target.combatant_name, int(_hp_frac(target) * 100), n], "steps": steps}
	return {"why": "strike %s" % target.combatant_name, "steps": [{"path": strike, "commit": "accept"}]}


## The strongest affordable single-target damage this member knows, else Attack.
func _best_strike(pc, t_idx: int) -> Array:
	var best := ""
	var best_mult := 0.0
	for aid in pc.learned_abilities:
		var a: Dictionary = JobSystem.get_ability(str(aid))
		if a.is_empty() or str(a.get("target_type", "")) != "single_enemy":
			continue
		if not (str(a.get("type", "")) in ["magic", "physical"]):
			continue
		var cost: int = JobSystem.get_ability_mp_cost(pc, str(aid))
		if cost > pc.current_mp * 0.5:
			continue
		var mult: float = float(a.get("damage_multiplier", 1.0))
		if mult > best_mult:
			best_mult = mult
			best = str(aid)
	if best != "" and best_mult > 1.2:
		return ["ability_menu", "ability_menu_" + best, "ability_%s_enemy_%d" % [best, t_idx]]
	return ["attack_menu", "attack_%d" % t_idx]


# ── Driving the menu ─────────────────────────────────────────────────────────

func _deepest(root) -> Node:
	var m = root
	while m != null and m.get("submenu") != null and is_instance_valid(m.submenu) and m.submenu.visible:
		m = m.submenu
	return m


func _index_of(menu, want) -> int:
	var ids: Array = want if want is Array else [want]
	var items: Array = menu.get("menu_items")
	for id in ids:
		for i in items.size():
			if str((items[i] as Dictionary).get("id", "")) == str(id):
				return i
	return -1


## Walks the cursor to a row one visible press at a time.
func _walk_to(menu, idx: int) -> void:
	var guard := 0
	while is_instance_valid(menu) and int(menu.selected_index) != idx and guard < 24:
		await press("ui_down" if idx > int(menu.selected_index) else "ui_up")
		await _beat(0.30, 0.55)
		guard += 1


func _take_turn(scene: Node, root) -> void:
	var pc = BattleManager.current_combatant
	if pc == null:
		return
	var plan := _plan(scene, pc)
	await _beat(0.8, 1.4)
	if plan.is_empty():
		return
	if plan.get("defer", false):
		print("[DEMO] %s: %s" % [pc.combatant_name, plan["why"]])
		await press("battle_defer")
		return
	for step in plan["steps"]:
		var ok: bool = await _do_step(scene, step)
		if not ok:
			print("[DEMO] %s: %s -> path %s not offered, attacking instead" % [pc.combatant_name, plan["why"], str(step["path"])])
			await _back_to_root(scene)
			var t_idx: int = int(str(step["path"][-1]).get_slice("_", str(step["path"][-1]).get_slice_count("_") - 1)) if step["path"].size() > 0 else 0
			await _do_step(scene, {"path": ["attack_menu", ["attack_%d" % t_idx]], "commit": "accept"})
			return
	print("[DEMO] %s: %s -> %s" % [pc.combatant_name, plan["why"], str(plan["steps"].map(func(s): return s["path"]))])


func _do_step(scene: Node, step: Dictionary) -> bool:
	var path: Array = step["path"]
	for i in path.size():
		var root = scene.get("active_win98_menu")
		if root == null or not is_instance_valid(root):
			return false
		var menu := _deepest(root)
		var idx := _index_of(menu, path[i])
		if idx < 0:
			# An optional middle step that this kit skips (e.g. no target submenu): carry on from here.
			if i == path.size() - 1:
				return false
			continue
		await _walk_to(menu, idx)
		await _beat(0.25, 0.45)
		var last: bool = i == path.size() - 1
		var row: Dictionary = menu.menu_items[idx]
		if last and not row.has("submenu"):
			await press("battle_advance" if step.get("commit", "accept") == "advance" else "ui_accept")
			await _beat(0.35, 0.6)
			return true
		await press("ui_accept")
		await _beat(0.35, 0.55)
	# The path ended on a row that opened a target list (a group attack): pick the planned foe, else the first.
	var root2 = scene.get("active_win98_menu")
	var menu2 := _deepest(root2) if root2 != null and is_instance_valid(root2) else null
	if menu2 != null and menu2 != root2:
		var want_t: int = int(step.get("target", 0))
		var idx2 := -1
		for i in (menu2.menu_items as Array).size():
			if str(menu2.menu_items[i].get("id", "")).ends_with("_%d" % want_t):
				idx2 = i
		await _walk_to(menu2, maxi(idx2, 0))
		await _beat(0.25, 0.4)
		await press("battle_advance" if step.get("commit", "accept") == "advance" else "ui_accept")
		await _beat(0.35, 0.6)
	return true


func _back_to_root(scene: Node) -> void:
	var root = scene.get("active_win98_menu")
	var guard := 0
	while root != null and is_instance_valid(root) and _deepest(root) != root and guard < 4:
		await press("ui_cancel")
		await _beat(0.3)
		guard += 1
