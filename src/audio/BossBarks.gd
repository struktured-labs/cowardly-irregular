class_name BossBarks
extends RefCounted
## Short voiced battle barks per boss and trigger (data/boss_barks.json); one cooldown per battle so they stay flavour, not spam.

const DATA_PATH := "res://data/boss_barks.json"
const TRIGGERS := ["windup", "big_hit", "low_hp", "party_wipe"]

static var _data: Dictionary = {}

var _next_ok_ms: int = 0
var _last_line: String = ""
var _low_hp_spoken: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {"bosses": {}}
	return _data


static func cooldown_ms() -> int:
	return int(float(data().get("cooldown_sec", 6.0)) * 1000.0)


static func speaker_for(monster_id: String) -> String:
	return str((data().get("bosses", {}) as Dictionary).get(monster_id, {}).get("speaker", ""))


static func lines_for(monster_id: String, trigger: String) -> Array:
	return ((data().get("bosses", {}) as Dictionary).get(monster_id, {}) as Dictionary).get(trigger, [])


## Barks never play at 4x+ or turbo (the party's lines don't either) nor over a scripted line or a speech bubble.
static func allowed(time_scale: float, turbo: bool, blocked: bool) -> bool:
	return not turbo and not blocked and time_scale < 4.0


## The line to speak now, or "" (cooldown, no lines, or low_hp already spoken this battle). Never repeats the last line.
func pick(monster_id: String, trigger: String, now_ms: int, rng: RandomNumberGenerator = null) -> String:
	if now_ms < _next_ok_ms:
		return ""
	if trigger == "low_hp" and _low_hp_spoken.has(monster_id):
		return ""
	var pool: Array = lines_for(monster_id, trigger).duplicate()
	if pool.size() > 1:
		pool.erase(_last_line)
	if pool.is_empty():
		return ""
	var i: int = (rng.randi() if rng else randi()) % pool.size()
	_last_line = str(pool[i])
	_next_ok_ms = now_ms + cooldown_ms()
	if trigger == "low_hp":
		_low_hp_spoken[monster_id] = true
	return _last_line
