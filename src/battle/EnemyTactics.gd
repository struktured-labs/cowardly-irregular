extends RefCounted
class_name EnemyTactics

## A monster plays the AP economy (struktured via main 23352): each turn its SHAPE (attack / defer / advance ×N) is a
## scored choice from the live battle state, tilted by a short prebaked plan (data/enemy_plans.json) and an intent bias.
## One brain for both engines: everything here is static and reads only what it is handed, so BattleManager and
## HeadlessBattleResolver call the same functions (autogrind 23353/23375). The role ladder still fills each slot.

const PLANS_PATH := "res://data/enemy_plans.json"
const MAX_ADVANCE := 4
## Stall bounds, deterministic and outside every weight: the .5xx "battles froze when everyone deferred" bug stays dead.
const MAX_CONSECUTIVE_DEFERS := 2
const AP_CAP := 4
## A posture or plan tilts; it never forces. Intent multipliers are clamped to this band (ai 23354).
const BIAS_MIN := 0.5
const BIAS_MAX := 2.0
## A party whose best member banked this much is about to burst.
const BURST_AP := 3
## Below this HP share a monster will not spend into AP debt it cannot survive.
const DEBT_HP := 0.35
const STATE_META := "enemy_tactics"

static var _plans: Dictionary = {}


static func plans() -> Dictionary:
	if _plans.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PLANS_PATH))
		_plans = parsed if parsed is Dictionary else {"version": 0, "plans": {"steady": {"turns": 3, "weights": {}}}, "personality": {"_default": "steady"}, "events": {}}
	return _plans


static func plan(tag: String) -> Dictionary:
	return plans().get("plans", {}).get(tag, plans().get("plans", {}).get("steady", {"turns": 3, "weights": {}}))


## The state the scorer sees, built the same way by both engines. `queued_defers` = this round's defers already chosen by
## the monster's own side (the caller reads its queue). `est` is (attacker, target) -> int damage; BattleManager's own estimate by default.
static func snapshot(me: Combatant, allies: Array, foes: Array, queued_defers: int = 0, est: Callable = Callable()) -> Dictionary:
	var hit := est if est.is_valid() else Callable(BattleManager, "estimate_attack_damage")
	var f: Array = []
	var ap_total := 0
	var ap_max := -99
	for c in foes:
		if not is_instance_valid(c) or not c.is_alive:
			continue
		f.append({"hp": c.current_hp, "max_hp": c.max_hp, "ap": c.current_ap, "deferring": c.is_defending, "est_hit": int(hit.call(me, c))})
		ap_total += c.current_ap
		ap_max = maxi(ap_max, c.current_ap)
	var alive := 0
	for a in allies:
		if is_instance_valid(a) and a.is_alive:
			alive += 1
	var st := state_of(me)
	return {"hp_pct": float(me.current_hp) / float(maxi(1, me.max_hp)), "ap": me.current_ap,
		"consecutive_defers": int(st.get("consecutive_defers", 0)), "allies_alive": alive, "queued_defers": queued_defers,
		"foes": f, "party_ap_total": ap_total, "party_ap_max": ap_max if not f.is_empty() else 0}


## The turn's shape: {"shape": "attack"|"defer"|"advance", "count": N, "target": foe index or -1, "why": term, "scores": {...}}.
static func choose(state: Dictionary, the_plan: Dictionary, bias: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var ap: int = int(state.get("ap", 0))
	var foes: Array = state.get("foes", [])
	var max_n: int = mini(MAX_ADVANCE, ap + 4)
	var can_advance: bool = ap >= 1 and max_n >= 2 and not foes.is_empty()
	var can_defer: bool = defer_is_legal(state)
	var s := {"attack": 1.0, "defer": 0.0, "advance": 0.0}
	var why := {"attack": "default", "defer": "", "advance": ""}
	var n_adv := 0
	var target := -1
	var locked := ""
	# A kill in reach beats every plan: one swing, or the fewest swings an Advance can afford.
	for i in foes.size():
		var hp: int = int(foes[i]["hp"])
		var hit: int = maxi(1, int(foes[i]["est_hit"]))
		if hit >= hp:
			s["attack"] = 3.0
			why["attack"] = "kill"
			s["advance"] = 0.0
			n_adv = 0
			target = i
			locked = "attack"
			break
		if can_advance:
			var need: int = int(ceil(float(hp) / float(hit)))
			if need <= max_n and (n_adv == 0 or need < n_adv):
				n_adv = maxi(2, need)
				target = i
				s["advance"] = 3.0
				why["advance"] = "finish"
				locked = "advance"
	if locked == "":
		if int(state.get("party_ap_max", 0)) >= BURST_AP:
			s["defer"] = 1.5
			why["defer"] = "brace"
		elif ap <= 0:
			s["defer"] = 0.6
			why["defer"] = "bank"
		if can_advance and ap >= 2:
			s["advance"] = 1.4
			n_adv = mini(ap + 1, max_n)
			why["advance"] = "banked"
	if n_adv > 0 and float(state.get("hp_pct", 1.0)) < DEBT_HP and ap - n_adv < 0:
		s["advance"] = 0.0
		why["advance"] = "debt"
	var w: Dictionary = the_plan.get("weights", {})
	for k in s:
		var tilt: float = float(w.get(k, 1.0))
		if k in ["defer", "advance"]:
			tilt *= clampf(float(bias.get(k + "_weight", 1.0)), BIAS_MIN, BIAS_MAX)
		var floor_v: float = s[k] if k == locked else 0.0
		s[k] = maxf(s[k] * tilt * (1.0 + (rng.randf_range(-0.08, 0.08) if rng and k != locked else 0.0)), floor_v)
	if not can_defer:
		s["defer"] = 0.0
	if not can_advance or n_adv < 2:
		s["advance"] = 0.0
	var shape := "attack"
	for k in ["advance", "defer"]:
		if s[k] > s[shape]:
			shape = k
	return {"shape": shape, "count": n_adv if shape == "advance" else 1, "target": target if shape != "defer" else -1,
		"why": why[shape], "scores": s}


## The stall rules: never a third defer in a row, never banking past the cap, never the last of its side to defer.
static func defer_is_legal(state: Dictionary) -> bool:
	if int(state.get("consecutive_defers", 0)) >= MAX_CONSECUTIVE_DEFERS:
		return false
	if int(state.get("ap", 0)) >= AP_CAP:
		return false
	var others: int = int(state.get("allies_alive", 1)) - 1
	return others <= 0 or int(state.get("queued_defers", 0)) < others


## The event that should re-pick the plan this turn, or "" (static, so both engines re-pick on the same turn).
static func repick_event(prev: Dictionary, now: Dictionary) -> String:
	if prev.is_empty():
		return "encounter"
	if _band(float(now.get("hp_pct", 1.0))) < _band(float(prev.get("hp_pct", 1.0))):
		return "hp_band_crossed"
	if int(now.get("allies_alive", 0)) < int(prev.get("allies_alive", 0)):
		return "ally_fell"
	if (now.get("foes", []) as Array).size() < (prev.get("foes", []) as Array).size():
		return "foe_fell"
	if int(now.get("party_ap_max", 0)) >= BURST_AP and int(prev.get("party_ap_max", 0)) < BURST_AP:
		return "party_banked"
	if _killable(now) and not _killable(prev):
		return "target_killable"
	return ""


## The deterministic plan for a personality (an existing AI archetype) and the event that prompted the pick.
static func pick_plan(personality: String, event: String) -> String:
	var p := plans()
	var by_event: String = str(p.get("events", {}).get(event, ""))
	if by_event != "" and p.get("plans", {}).has(by_event):
		return by_event
	var pers: Dictionary = p.get("personality", {})
	return str(pers.get(personality, pers.get("_default", "steady")))


## The cross-turn memory, owned here and changed only by commit() (autogrind 23375).
static func state_of(me: Combatant) -> Dictionary:
	return me.get_meta(STATE_META, {}) if is_instance_valid(me) else {}


static func commit(me: Combatant, choice: Dictionary, snap: Dictionary, plan_tag: String, turns_left: int) -> void:
	var st := state_of(me).duplicate()
	st["consecutive_defers"] = int(st.get("consecutive_defers", 0)) + 1 if choice.get("shape", "") == "defer" else 0
	st["plan"] = plan_tag
	st["turns_left"] = turns_left
	st["prev"] = snap
	me.set_meta(STATE_META, st)


## One full turn for one monster: snapshot, re-pick on an event or an expired plan, choose, commit. `bias` may carry an
## LLM-picked "plan" tag (cowir-ai); an unknown tag falls back to the deterministic pick.
static func decide(me: Combatant, allies: Array, foes: Array, personality: String, bias: Dictionary, rng: RandomNumberGenerator,
		queued_defers: int = 0, est: Callable = Callable()) -> Dictionary:
	var snap := snapshot(me, allies, foes, queued_defers, est)
	var st := state_of(me)
	var tag: String = str(st.get("plan", ""))
	var left: int = int(st.get("turns_left", 0))
	var event := repick_event(st.get("prev", {}), snap)
	if event != "" or left <= 0 or tag == "":
		var asked: String = str(bias.get("plan", ""))
		tag = asked if plans().get("plans", {}).has(asked) else pick_plan(personality, event)
		left = int(plan(tag).get("turns", 3))
	var choice := choose(snap, plan(tag), bias, rng)
	choice["plan"] = tag
	choice["event"] = event
	commit(me, choice, snap, tag, left - 1)
	return choice


static func _band(hp_pct: float) -> int:
	return clampi(int(hp_pct * 4.0), 0, 3)


static func _killable(state: Dictionary) -> bool:
	for f in state.get("foes", []):
		if int(f["est_hit"]) >= int(f["hp"]):
			return true
	return false
