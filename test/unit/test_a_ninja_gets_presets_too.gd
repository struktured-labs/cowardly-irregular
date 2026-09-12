extends GutTest

## A player who earns the Ninja opened the autobattle preset catalog and found NOTHING — six jobs
## ship three stances each, the Ninja shipped zero, in a game whose stated pillar is that autobattle
## IS the game. Its unlock has worked since .298 (clear a dungeon in under five minutes).
##
## It was empty for a reason, not by oversight. Three of its five abilities — smoke_bomb,
## shadow_step, vanish — are SETUP moves that apply a status, and until `not_has_status` shipped in
## .307 the grammar could not say "only if it is not already up". A preset using them would have
## re-cast forever and the rules beneath it would never have run. So these are authored on top of
## that condition, and the arm that matters here is the one saying none of them can pin.
##
## Authored against the real kit and the engine's own fizzle arithmetic rather than against what
## sounds like a ninja move: the Guardian's DEFAULT script is the warning next door, where three of
## its abilities are monster abilities the job can never know.

const TEMPLATES := "res://data/autobattle_rule_templates.json"
const STANCES := ["aggressive", "balanced", "defensive"]
const JOB := "ninja"


func _json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_not_null(parsed, "CONTROL: %s parses" % path)
	return parsed


func _all_templates() -> Array:
	var all: Array = (_json(TEMPLATES).get("templates", []) as Array)
	assert_gt(all.size(), 17, "CONTROL: the catalog is populated (%d)" % all.size())
	return all


func _mine() -> Array:
	return _all_templates().filter(func(t): return str((t as Dictionary).get("job_id", "")) == JOB)


func _kit() -> Dictionary:
	var jobs: Dictionary = _json("res://data/jobs.json")
	jobs = jobs.get("jobs", jobs)
	var j: Dictionary = jobs.get(JOB, {})
	var out: Dictionary = {}
	for a in (j.get("abilities", []) as Array):
		out[str(a)] = true
	var at_level = j.get("abilities_at_level", {})
	if at_level is Dictionary:
		for lv in (at_level as Dictionary).keys():
			for a in ((at_level as Dictionary)[lv] as Array):
				out[str(a)] = true
	assert_gt(out.size(), 2, "CONTROL: the Ninja kit reads non-empty (%d)" % out.size())
	return out


func test_the_ninja_has_one_preset_per_stance() -> void:
	var mine := _mine()
	assert_eq(mine.size(), 3, "three stances, like every other job with presets")
	var seen: Array = []
	var names: Array = []
	for t in mine:
		seen.append(str((t as Dictionary).get("stance", "")))
		names.append(str((t as Dictionary).get("name", "")))
	seen.sort()
	names.sort()
	assert_eq(seen, STANCES, "one each of aggressive/balanced/defensive, got %s" % str(seen))
	assert_eq(names, ["Aggressive", "Balanced", "Defensive"], "and they are named for them: %s" % str(names))


func test_every_ability_is_one_the_ninja_can_actually_know() -> void:
	var kit := _kit()
	var bad: Array = []
	for t in _mine():
		for r in ((t as Dictionary).get("rules", []) as Array):
			for a in ((r as Dictionary).get("actions", []) as Array):
				var ad: Dictionary = a
				if str(ad.get("type", "")) != "ability":
					continue
				if not kit.has(str(ad.get("id", ""))):
					bad.append("%s/%s" % [str((t as Dictionary).get("id", "")), str(ad.get("id", ""))])
	assert_eq(bad.size(), 0, "a preset uses an ability outside the Ninja's kit — it can never fire: " + str(bad))


func test_the_live_deep_check_accepts_every_rule() -> void:
	## The strong arm. validate_rule with a character id runs the FIZZLE deep-check: kit membership,
	## unknown ids, and the MP guard computed as ceil(cost / base_pool * 100) — the engine's own
	## arithmetic rather than a second copy of it in this file, which would drift from the thing it
	## is meant to defend. _resolve_job_for_character falls back to the id, so "ninja" resolves.
	var abs_node = Engine.get_main_loop().root.get_node_or_null("AutobattleSystem")
	if abs_node == null or not abs_node.has_method("validate_rule"):
		pending("AutobattleSystem.validate_rule required")
		return
	var refused: Array = []
	var checked: int = 0
	for t in _mine():
		for r in ((t as Dictionary).get("rules", []) as Array):
			checked += 1
			var errors: Array = abs_node.validate_rule(r, JOB)
			if errors.size() > 0:
				refused.append("%s rule %d: %s" % [str((t as Dictionary).get("id", "")), checked, str(errors)])
	assert_gt(checked, 10, "CONTROL: rules were actually submitted (%d)" % checked)
	assert_eq(refused.size(), 0, "the deep check refuses an authored rule: " + str(refused))


func test_the_deep_check_would_have_caught_an_unguarded_cost() -> void:
	## CONTROL for the arm above: if the deep check waved everything through, "0 refusals" would
	## mean nothing. vanish is 12 MP of a 45 pool, so it needs mp_percent >= 27.
	var abs_node = Engine.get_main_loop().root.get_node_or_null("AutobattleSystem")
	if abs_node == null or not abs_node.has_method("validate_rule"):
		pending("AutobattleSystem.validate_rule required")
		return
	var unguarded: Dictionary = {
		"conditions": [{"type": "hp_percent", "op": "<", "value": 35}],
		"actions": [{"type": "ability", "id": "vanish", "target": "self"}],
	}
	assert_gt(abs_node.validate_rule(unguarded, JOB).size(), 0,
		"an unguarded 12 MP rule must be refused, or the arm above proves nothing")


func test_no_preset_rule_can_fire_forever() -> void:
	## The property this whole catalog waited on, checked across EVERY job's presets, not just mine.
	##
	## ⚠️ WIDENED 2026-09-12. It used to examine `target_type == "self"`, which was a PROXY for the
	## thing that matters and missed half of it. What makes a re-cast a wasted turn is that the
	## ability does NOTHING BUT apply the status — an enemy debuff is the same defect facing
	## outward, and `not_enemy_has_status` did not exist when this was written. Damage abilities
	## with a status rider (riff, shield_bash) are deliberately excluded: re-casting one still
	## deals its damage, so it is a choice, not a stall.
	var abilities: Dictionary = _json("res://data/abilities.json")
	abilities = abilities.get("abilities", abilities)
	var examined: int = 0
	var self_seen: int = 0
	var enemy_seen: int = 0
	var unguarded: Array = []
	for t in _all_templates():
		for r in ((t as Dictionary).get("rules", []) as Array):
			var conds: Array = (r as Dictionary).get("conditions", []) as Array
			for a in ((r as Dictionary).get("actions", []) as Array):
				var ad: Dictionary = a
				if str(ad.get("type", "")) != "ability":
					continue
				var def: Dictionary = abilities.get(str(ad.get("id", "")), {})
				var effect: String = str(def.get("effect", ""))
				if effect == "":
					continue
				## Does it do anything besides apply the status? If so, a repeat is not a stall.
				if def.has("damage_multiplier") or def.has("power"):
					continue
				var target: String = str(def.get("target_type", ""))
				var at_self: bool = target == "self"
				var at_enemy: bool = target in ["all_enemies", "single_enemy"]
				if not (at_self or at_enemy):
					continue
				examined += 1
				if at_self:
					self_seen += 1
				else:
					enemy_seen += 1
				var guarded: bool = false
				for c in conds:
					var cd: Dictionary = c
					var ctype: String = str(cd.get("type", ""))
					## The non-repeat must name THIS status — a guard on some other status bounds
					## nothing. Sides matter too: the caster's own statuses answer for a self buff,
					## the field's for a debuff.
					if at_self and ctype == "not_has_status" and str(cd.get("status", "")) == effect:
						guarded = true
					if at_enemy and ctype == "not_enemy_has_status" and str(cd.get("status", "")) == effect:
						guarded = true
					## A stat buff is the other shape of the same guard, used by the older presets.
					if ctype == "not_has_buff":
						guarded = true
					## A turn gate bounds it too — `turn == 1` fires once and can never repeat. It
					## is weaker (it cannot re-arm when the status lapses) but it is not a stall.
					if ctype == "turn":
						guarded = true
					## ⚠️ So does a gate on a resource the action SPENDS, and that is not a
					## loophole — it is the same bound one level out. press_the_edge and
					## circuit_breaker both call shift_band(-1), so a rule gated on
					## volatility_band lowers its own condition every time it fires and cannot
					## run forever. Added because this predicate flagged all three Speculator
					## presets: "has an effect and no damage term" is a PROXY for "does nothing
					## but apply a status", and it over-includes abilities whose damage lives in
					## the HANDLER rather than in a damage_multiplier — press_the_edge deals its
					## band-scaled damage through take_damage and carries neither field.
					if ctype == "volatility_band":
						guarded = true
				if not guarded:
					unguarded.append("%s -> %s (%s, %s)" % [str((t as Dictionary).get("id", "")),
						str(ad.get("id", "")), effect, target])
	assert_gt(self_seen, 2, "CONTROL: self-buff rules were found to examine (%d)" % self_seen)
	assert_gt(enemy_seen, 2, "CONTROL: ENEMY-debuff rules were found too (%d) — this is the half the "
		% enemy_seen + "old self-only predicate could not see, so without it the widening is inert")
	assert_eq(unguarded.size(), 0,
		"a preset applies a status with nothing to stop it re-applying, and the ability does nothing "
		+ "else — the turn is spent and every rule below it is unreachable: " + str(unguarded))


func test_every_preset_ends_in_an_unconditional_rule() -> void:
	## First match wins. A preset whose last rule can fail to match leaves the character doing
	## nothing on a turn the player paid for.
	for t in _mine():
		var rules: Array = (t as Dictionary).get("rules", []) as Array
		assert_gt(rules.size(), 1, "%s has rules at all" % str((t as Dictionary).get("id", "")))
		var last: Dictionary = rules[rules.size() - 1]
		var conds: Array = last.get("conditions", []) as Array
		assert_eq(conds.size(), 1, "%s's last rule must be a single catch-all" % str((t as Dictionary).get("id", "")))
		assert_eq(str((conds[0] as Dictionary).get("type", "")), "always",
			"%s must end on `always` or the turn can be wasted" % str((t as Dictionary).get("id", "")))


func test_the_catalog_actually_offers_them_to_a_ninja() -> void:
	## PRESENT is not REACHABLE: find_for_job is what the picker calls, and it drops any entry
	## failing its own shape check. This is the arm that says a player sees them.
	var cat = load("res://src/autobattle/AutobattleRuleTemplates.gd")
	assert_not_null(cat, "CONTROL: the catalog script loads")
	assert_gt((cat.find_for_job("fighter") as Array).size(), 0,
		"CONTROL: find_for_job returns presets for a job that already had them")
	var mine: Array = cat.find_for_job(JOB)
	assert_eq(mine.size(), 3, "a Ninja must be offered three presets; the catalog returned %d" % mine.size())


## ── and now the artifact, not the register ─────────────────────────────

var _abs: Node = null
var _bm: Node = null
var _p_backup: Array = []
var _e_backup: Array = []
var _fixture_ids: Array[String] = []


func before_each() -> void:
	_abs = get_node_or_null("/root/AutobattleSystem")
	if _abs:
		_abs._test_disable_persistence = true
	_bm = get_node_or_null("/root/BattleManager")
	if _bm:
		_p_backup = _bm.player_party.duplicate()
		_e_backup = _bm.enemy_party.duplicate()
	_fixture_ids.clear()


func after_each() -> void:
	if _bm:
		_bm.player_party.clear()
		_bm.enemy_party.clear()
		for c in _p_backup:
			_bm.player_party.append(c)
		for c in _e_backup:
			_bm.enemy_party.append(c)
	if _abs:
		for cid in _fixture_ids:
			_abs.character_profiles.erase(cid)


func test_the_balanced_preset_really_rotates_in_the_executor() -> void:
	## Every arm above reads JSON. "The rule carries a not_has_status condition" is a claim about
	## the DATA; what a player meets is what the executor hands the character on turn 2. So this one
	## installs the shipped preset on a real Ninja and steps turns.
	if _bm == null or _abs == null:
		pass_test("no battle autoloads in this harness")
		return
	var preset: Dictionary = {}
	for t in _mine():
		if str((t as Dictionary).get("id", "")) == "ninja_balanced":
			preset = t
	assert_false(preset.is_empty(), "CONTROL: the balanced preset was found to install")

	var c := Combatant.new()
	c.initialize({"name": "Rotating Ninja", "max_hp": 850, "max_mp": 45,
		"attack": 140, "defense": 80, "magic": 80, "speed": 18})
	c.job = JobSystem.get_job(JOB)
	c.job_level = 10
	add_child_autofree(c)
	var foe := Combatant.new()
	foe.initialize({"name": "Rotation Foe", "max_hp": 99999, "max_mp": 0,
		"attack": 1, "defense": 999, "magic": 1, "speed": 1})
	add_child_autofree(foe)
	_bm.player_party.clear()
	_bm.enemy_party.clear()
	_bm.player_party.append(c)
	_bm.enemy_party.append(foe)

	var cid: String = _abs._get_character_id(c)
	_fixture_ids.append(cid)
	_abs.set_character_script(cid, {"character_id": cid, "name": "Balanced",
		"rules": (preset.get("rules", []) as Array)})

	var pick := func() -> String:
		var actions: Array = _abs.execute_grid_autobattle(c)
		var a: Dictionary = actions[0]
		return str(a.get("ability_id", "")) if str(a.get("type", "")) == "ability" else str(a.get("type", ""))

	assert_eq(pick.call(), "shadow_step", "turn 1: full HP, healthy foe — the preset sets up")
	c.add_status("shadow_step", 1)
	assert_eq(pick.call(), "attack",
		"turn 2: already set up, so the rows BELOW must get the turn — this is the whole reason the "
		+ "Ninja had no presets before .307")
	c.remove_status("shadow_step")
	assert_eq(pick.call(), "shadow_step", "turn 3: it lapsed, so set up again")


func test_the_defensive_opener_watches_the_room_not_the_clock() -> void:
	## Shipped gated on `turn == 1`, because when these presets were authored the grammar had no
	## negation for an ENEMY status — so "blind them while they can still see" was unsayable and the
	## opener could only fire once per fight, never re-arming when the blind lapsed. That limit was
	## flagged in the commit rather than designed around; `not_enemy_has_status` (.313) closed it.
	if _bm == null or _abs == null:
		pass_test("no battle autoloads in this harness")
		return
	var preset: Dictionary = {}
	for t in _mine():
		if str((t as Dictionary).get("id", "")) == "ninja_defensive":
			preset = t
	assert_false(preset.is_empty(), "CONTROL: the defensive preset was found to install")

	var c := Combatant.new()
	c.initialize({"name": "Opener Ninja", "max_hp": 850, "max_mp": 45,
		"attack": 140, "defense": 80, "magic": 80, "speed": 18})
	c.job = JobSystem.get_job(JOB)
	c.job_level = 10
	add_child_autofree(c)
	var foe := Combatant.new()
	foe.initialize({"name": "Opener Foe", "max_hp": 99999, "max_mp": 0,
		"attack": 1, "defense": 999, "magic": 1, "speed": 1})
	add_child_autofree(foe)
	_bm.player_party.clear()
	_bm.enemy_party.clear()
	_bm.player_party.append(c)
	_bm.enemy_party.append(foe)

	var cid: String = _abs._get_character_id(c)
	_fixture_ids.append(cid)
	_abs.set_character_script(cid, {"character_id": cid, "name": "Defensive",
		"rules": (preset.get("rules", []) as Array)})
	var pick := func() -> String:
		var a: Dictionary = _abs.execute_grid_autobattle(c)[0]
		return str(a.get("ability_id", "")) if str(a.get("type", "")) == "ability" else str(a.get("type", ""))

	assert_eq(pick.call(), "smoke_bomb", "nobody is blinded yet, so blind the room")
	foe.add_status("blind", 2)
	assert_eq(pick.call(), "attack", "the room is blind — do not spend the turn re-blinding it")
	foe.remove_status("blind")
	assert_eq(pick.call(), "smoke_bomb",
		"and it RE-ARMS when the blind lapses, which a `turn == 1` gate could never do — that is "
		+ "the whole difference between watching the room and watching the clock")
