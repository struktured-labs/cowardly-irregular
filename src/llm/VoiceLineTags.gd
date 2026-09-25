class_name VoiceLineTags
extends RefCounted

## Each tag is a pure predicate over PartyCombatLineContext; code decides eligibility, the LLM only chooses among true lines.

const SIMPLE_TAGS: Array[String] = [
	"none_down", "all_full", "ally_down", "ally_low", "last_standing",
	"enemy_last", "enemy_nearly_dead", "many_enemies", "self_status",
]
## Say when a line MAY play and hold in most fights, so they filter but never outrank generic lines.
const PRECONDITION_TAGS: Array[String] = ["none_down", "all_full"]
const ALLY_ALIVE_PREFIX := "ally_alive:"
const ALLY_LOW_PCT := 30.0
const ENEMY_NEARLY_DEAD_PCT := 20.0


static func is_known_tag(tag: String) -> bool:
	if tag.begins_with(ALLY_ALIVE_PREFIX):
		return tag.length() > ALLY_ALIVE_PREFIX.length()
	return tag in SIMPLE_TAGS


## A moment is rare enough that a line written for it should win; ally_alive:* and PRECONDITION_TAGS are not.
static func is_moment_tag(tag: String) -> bool:
	return is_known_tag(tag) and not tag.begins_with(ALLY_ALIVE_PREFIX) and not (tag in PRECONDITION_TAGS)


## True when every tag holds; an unknown tag is never true.
static func is_eligible(tags: Array, ctx: PartyCombatLineContext) -> bool:
	for t in tags:
		if not tag_holds(str(t), ctx):
			return false
	return true


static func tag_holds(tag: String, ctx: PartyCombatLineContext) -> bool:
	if ctx == null or not is_known_tag(tag):
		return false
	var others: Array = ctx.party.filter(func(m): return str(m.get("name", "")) != ctx.speaker_name)
	var alive_enemies: Array = ctx.enemies.filter(func(e): return float(e.get("hp_pct", 0.0)) > 0.0)
	if tag.begins_with(ALLY_ALIVE_PREFIX):
		var job: String = tag.substr(ALLY_ALIVE_PREFIX.length())
		return others.any(func(m): return str(m.get("job_id", "")) == job and bool(m.get("is_alive", false)))
	match tag:
		"none_down":
			return ctx.party.size() >= 2 and ctx.party.all(func(m): return bool(m.get("is_alive", false)))
		"all_full":
			return tag_holds("none_down", ctx) and ctx.party.all(func(m): return float(m.get("hp_pct", 0.0)) >= 100.0)
		"ally_down":
			return others.any(func(m): return not bool(m.get("is_alive", true)))
		"ally_low":
			return others.any(func(m): return bool(m.get("is_alive", false)) and float(m.get("hp_pct", 100.0)) < ALLY_LOW_PCT)
		"last_standing":
			return not others.is_empty() and others.all(func(m): return not bool(m.get("is_alive", true)))
		"enemy_last":
			return alive_enemies.size() == 1
		"enemy_nearly_dead":
			return alive_enemies.any(func(e): return float(e.get("hp_pct", 100.0)) < ENEMY_NEARLY_DEAD_PCT)
		"many_enemies":
			return alive_enemies.size() >= 3
		"self_status":
			return not ctx.speaker_status.is_empty()
	return false
