class_name BossCadence
extends RefCounted

## A boss's breath on a clock: `every` ordinary turns, then `charge_turns` of visible charging, then the signature releases.
## Pure: state is a plain Dictionary the caller keeps (BattleManager stores it on the boss's meta); nothing here touches a node.

const BEAT_PLAIN := "plain"
const BEAT_CHARGE := "charge"
const BEAT_RELEASE := "release"

## Statuses that break a charge when they land on a charging boss.
const DEFAULT_INTERRUPTS: Array[String] = ["stun", "silence", "sleep", "cannot_act"]


## The row's `cadence` normalised, or {} when the row has none or names no signature.
static func config(row: Dictionary) -> Dictionary:
	var raw: Variant = row.get("cadence", null)
	if not raw is Dictionary or str((raw as Dictionary).get("signature", "")) == "":
		return {}
	var c: Dictionary = raw
	var interrupts: Array[String] = []
	for s in c.get("interrupted_by", DEFAULT_INTERRUPTS):
		interrupts.append(str(s))
	return {
		"signature": str(c["signature"]),
		"every": maxi(1, int(c.get("every", 3))),
		"charge_turns": maxi(1, int(c.get("charge_turns", 1))),
		"interrupted_by": interrupts,
	}


static func fresh_state() -> Dictionary:
	return {"phase": "build", "count": 0, "charge_left": 0, "interrupted": false}


## Advance one boss turn. Returns {"beat": plain|charge|release, "state": the state after this turn}.
static func next(state: Dictionary, cfg: Dictionary) -> Dictionary:
	var s: Dictionary = state.duplicate() if not state.is_empty() else fresh_state()
	s["interrupted"] = false
	if cfg.is_empty():
		return {"beat": BEAT_PLAIN, "state": s}
	if str(s.get("phase", "build")) == "charging":
		s["charge_left"] = int(s.get("charge_left", 0)) - 1
		if int(s["charge_left"]) > 0:
			return {"beat": BEAT_CHARGE, "state": s}
		s["phase"] = "build"
		s["count"] = 0
		return {"beat": BEAT_RELEASE, "state": s}
	s["count"] = int(s.get("count", 0)) + 1
	if int(s["count"]) > int(cfg["every"]):
		s["phase"] = "charging"
		s["charge_left"] = int(cfg["charge_turns"])
		return {"beat": BEAT_CHARGE, "state": s}
	return {"beat": BEAT_PLAIN, "state": s}


static func is_charging(state: Dictionary) -> bool:
	return str(state.get("phase", "build")) == "charging"


## A status landed on the boss. A charging boss hit by an interrupting status loses the breath and starts its count over.
static func on_status(state: Dictionary, cfg: Dictionary, status: String) -> Dictionary:
	var s: Dictionary = state.duplicate() if not state.is_empty() else fresh_state()
	if cfg.is_empty() or not is_charging(s) or not status in (cfg["interrupted_by"] as Array):
		return s
	s["phase"] = "build"
	s["count"] = 0
	s["charge_left"] = 0
	s["interrupted"] = true
	return s


## Boss turns until the signature releases: 1 means its next turn. -1 when there is no clock.
static func turns_to_release(state: Dictionary, cfg: Dictionary) -> int:
	if cfg.is_empty():
		return -1
	var s: Dictionary = state if not state.is_empty() else fresh_state()
	if is_charging(s):
		return maxi(1, int(s.get("charge_left", 1)))
	return maxi(0, int(cfg["every"]) - int(s.get("count", 0))) + int(cfg["charge_turns"]) + 1
