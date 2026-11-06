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
var _pressed_at_ms := -100000
var _busy := false
## Members whose command menu this player drove: a member missing here acted on AI, not by hand.
var played: Dictionary = {}
## Revive/heal targets already chosen this selection phase: everyone picks before anyone acts, so without this 4 members revive one ally.
var _claimed: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_bm().execution_phase_started.connect(func(): _claimed.clear())
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


func _bm() -> Node:
	return get_tree().root.get_node("BattleManager")


func _js() -> Node:
	return get_tree().root.get_node("JobSystem")


func _is() -> Node:
	return get_tree().root.get_node("ItemSystem")


func _gl() -> Node:
	return get_tree().root.get_node_or_null("GameLoop")


func _battle_scene() -> Node:
	var gl := _gl()
	var s = gl.get("current_scene") if gl else null
	return s if s != null and is_instance_valid(s) and "active_win98_menu" in s else null


## The dialogue box on screen, whichever director owns it: the Rat King's cave plays its intro on its OWN
## CutsceneDirector, not GameLoop's, so the box is found by its script anywhere in the tree.
func _cutscene_dialogue() -> Node:
	return _find_dialogue(get_tree().root)


func _find_dialogue(n: Node) -> Node:
	var sc = n.get_script()
	if sc != null and str(sc.resource_path).ends_with("CutsceneDialogue.gd") and n.get("visible") == true \
			and n.get("_dialogue_queue") is Array and (n.get("_dialogue_queue") as Array).size() > 0:
		return n
	for c in n.get_children():
		var f := _find_dialogue(c)
		if f != null:
			return f
	return null


func _run() -> void:
	while is_inside_tree():
		await get_tree().process_frame
		if not enabled or _busy:
			continue
		_busy = true
		await _step()
		_busy = false


## A new save leaves some members on autobattle, and they then act with no menu at all (four of five in the
## encounter take: "one person choosing and four on autopilot"). Every member is played by hand here.
func _manual_party() -> void:
	var ab = get_tree().root.get_node_or_null("AutobattleSystem")
	var gl := _gl()
	var party: Array = gl.get("party") if gl and "party" in gl else []
	for m in party + _bm().player_party:
		if m == null or not is_instance_valid(m):
			continue
		var cid: String = str(m.combatant_name).to_lower().replace(" ", "_")
		if ab and ab.is_autobattle_enabled(cid):
			ab.set_autobattle_enabled(cid, false)
			print("[DEMO] %s: autobattle off, this member is played by hand" % m.combatant_name)
		if "autobattle_locked" in m and m.autobattle_locked:
			m.autobattle_locked = false
	if "is_autobattle_enabled" in _bm():
		_bm().is_autobattle_enabled = false


func _step() -> void:
	_manual_party()
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
		await _voice_done()
		await press("ui_accept")
		return
	if scene.get_node_or_null("VictoryResults") != null:
		await _beat(victory_hold, victory_hold + 0.6)
		await press("ui_accept")
		await _beat(1.0)
		return
	var menu = scene.get("active_win98_menu")
	if _bm().current_state == _bm().BattleState.PLAYER_SELECTING and menu != null \
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
	elif Time.get_ticks_msec() - _pressed_at_ms < 4000:
		# Still the line already confirmed: the index advances a frame late, and a second press here cut the NEXT voice line 0.4 s in (sfx 22756).
		await _beat(0.1)
		return
	await _voice_done()
	_pressed_at_ms = Time.get_ticks_msec()
	await press("ui_accept")
	await _beat(0.25)


## A Confirm closes the box on a batch's last line, and closing it stops the recording (cutscenes 22759): let the line finish, 10 s at most.
func _voice_done() -> void:
	var sm = get_tree().root.get_node_or_null("SoundManager")
	var waited := 0.0
	while sm != null and sm.has_method("is_voiced_line_playing") and sm.is_voiced_line_playing() and waited < 10.0:
		await _beat(0.1)
		waited += 0.1


# ── Policy ───────────────────────────────────────────────────────────────────

func _living(arr: Array) -> Array:
	return arr.filter(func(c): return c != null and is_instance_valid(c) and c.is_alive)


func _hp_frac(c) -> float:
	return float(c.current_hp) / float(maxi(1, c.max_hp))


func _knows(pc, aid: String) -> bool:
	return aid in pc.learned_abilities and not _js().get_ability(aid).is_empty() \
			and _js().get_ability_mp_cost(pc, aid) <= pc.current_mp


func _plan(scene: Node, pc) -> Dictionary:
	var party: Array = _living(_bm().player_party)
	var foes: Array = _living(scene.get("test_enemies"))
	if foes.is_empty():
		return {}
	var target = foes[0]
	for f in foes:
		if _hp_frac(f) < _hp_frac(target):
			target = f
	var t_idx: int = (scene.get("test_enemies") as Array).find(target)
	# A member down first: Raise, else a Phoenix Down (Mordaine's lv30 take lost the Mage and the Bard with no way back).
	var down = null
	for m in _bm().player_party:
		if is_instance_valid(m) and not m.is_alive and not _claimed.has(m.get_instance_id()):
			down = m
			break
	if down != null:
		var d_idx: int = _bm().player_party.find(down)
		if _knows(pc, "raise"):
			_claimed[down.get_instance_id()] = true
			return {"why": "%s is down, raise" % down.combatant_name,
				"steps": [{"path": ["ability_menu", ["ability_menu_raise", "ability_raise"], "ability_raise_dead_%d" % d_idx], "commit": "accept"}]}
		if _is().party_item_count(_bm().consumable_bag(pc), "phoenix_down") > 0:
			_claimed[down.get_instance_id()] = true
			return {"why": "%s is down, phoenix down" % down.combatant_name,
				"steps": [{"path": ["item_menu", "item_menu_phoenix_down", "item_phoenix_down_ally_%d" % d_idx], "commit": "accept"}]}
	# Heal the lowest ally under 40%, or under 50% once two are that low (a spread hit is coming again).
	var low_count := party.filter(func(m): return _hp_frac(m) < 0.50).size()
	var heal_at: float = 0.50 if low_count >= 2 else 0.40
	var hurt = null
	for m in party:
		if _hp_frac(m) < heal_at and not _claimed.has(m.get_instance_id()) and (hurt == null or _hp_frac(m) < _hp_frac(hurt)):
			hurt = m
	if hurt != null:
		var h_idx: int = _bm().player_party.find(hurt)
		for aid in ["curaga", "cura", "cure"]:
			if _knows(pc, aid):
				_claimed[hurt.get_instance_id()] = true
				return {"why": "%s at %d%%, heal" % [hurt.combatant_name, int(_hp_frac(hurt) * 100)],
					"steps": [{"path": ["ability_menu", ["ability_menu_" + aid, "ability_" + aid], "ability_%s_ally_%d" % [aid, h_idx]], "commit": "accept"}]}
		for iid in ["hi_potion", "potion"]:
			if _is().party_item_count(_bm().consumable_bag(pc), iid) > 0:
				_claimed[hurt.get_instance_id()] = true
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
		var a: Dictionary = _js().get_ability(str(aid))
		if a.is_empty() or str(a.get("target_type", "")) != "single_enemy":
			continue
		if not (str(a.get("type", "")) in ["magic", "physical"]):
			continue
		var cost: int = _js().get_ability_mp_cost(pc, str(aid))
		if cost > pc.current_mp * 0.5:
			continue
		var mult: float = float(a.get("damage_multiplier", 1.0))
		if mult > best_mult:
			best_mult = mult
			best = str(aid)
	if best != "" and best_mult > 1.2:
		return ["ability_menu", "ability_menu_" + best, "ability_%s_enemy_%d" % [best, t_idx]]
	return ["BASIC", t_idx]


## This member's own plain strike, read off the menu it was given: Attack where it exists, else the first top-level
## row whose target list reaches the foe (the Bard's attack row is Riff; main 22370). [] when nothing offers one.
func _basic_strike(root, t_idx: int) -> Array:
	if root == null or not is_instance_valid(root):
		return []
	var items: Array = root.get("menu_items")
	# A job whose free move REPLACES Attack (the Bard's Riff) strikes with that row.
	var pc = _bm().current_combatant
	var fm = pc.job.get("free_move", {}) if pc != null and pc.job is Dictionary else {}
	if fm is Dictionary and fm.get("replaces_attack", false) and str(fm.get("ability_id", "")) != "":
		var aid := str(fm["ability_id"])
		for row in items:
			if str(row.get("id", "")) == "ability_menu_" + aid:
				return ["ability_menu_" + aid, "ability_%s_enemy_%d" % [aid, t_idx]]
	for row in items:
		if str(row.get("id", "")) == "attack_menu":
			return ["attack_menu", "attack_%d" % t_idx]
	for row in items:
		var sub = row.get("submenu")
		if not (sub is Array) or row.get("disabled", false):
			continue
		var first := ""
		for child in sub:
			var cid := str(child.get("id", ""))
			if cid.ends_with("_enemy_%d" % t_idx) or cid == "attack_%d" % t_idx:
				return [str(row["id"]), cid]
			if first == "" and (cid.contains("_enemy_") or cid.begins_with("attack_")):
				first = cid
		if first != "":
			return [str(row["id"]), first]
	return []


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
	var pc = _bm().current_combatant
	if pc == null:
		return
	played[str(pc.combatant_name)] = true
	var plan := _plan(scene, pc)
	await _beat(0.8, 1.4)
	if plan.is_empty():
		return
	if plan.get("defer", false):
		print("[DEMO] %s: %s" % [pc.combatant_name, plan["why"]])
		await press("battle_defer")
		return
	for step in plan["steps"]:
		var path: Array = step["path"]
		if path.size() == 2 and str(path[0]) == "BASIC":
			path = _basic_strike(scene.get("active_win98_menu"), int(path[1]))
			step = {"path": path, "commit": step.get("commit", "accept")}
		var ok: bool = path.size() > 0 and await _do_step(scene, step)
		if not ok:
			await _back_to_root(scene)
			var fallback := _basic_strike(scene.get("active_win98_menu"), 0)
			if fallback.size() > 0 and fallback != path and await _do_step(scene, {"path": fallback, "commit": "accept"}):
				print("[DEMO] %s: %s -> %s not offered, struck with %s" % [pc.combatant_name, plan["why"], str(path), str(fallback)])
			else:
				print("[DEMO] %s: %s -> %s not offered and no strike row, defer" % [pc.combatant_name, plan["why"], str(path)])
				await _back_to_root(scene)
				await press("battle_defer")
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


## The party members who fought without this player ever opening their menu (cowir-main 22349: assert every turn).
func missing_menu_members(party: Array) -> Array:
	var out: Array = []
	for m in party:
		if m != null and is_instance_valid(m) and not played.has(str(m.combatant_name)):
			out.append(str(m.combatant_name))
	return out


## Raises a party the way the boss segment does (job level, the kit unlocked through it, full HP/MP). Static, so a
## segment can call it on the loaded script before the walk: load("res://tools/demo_battle_player.gd").level_party(...)
static func level_party(root: Node, party: Array, level: int) -> void:
	var js = root.get_node("JobSystem")
	for m in party:
		if m == null or not is_instance_valid(m):
			continue
		m.job_level = level
		js.learn_abilities_for_level(m, level)
		m.recalculate_stats()
		m.current_hp = m.max_hp
		m.current_mp = m.max_mp
		m.is_alive = true
	print("[DEMO] party at level %d" % level)
