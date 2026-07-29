extends GutTest

## setup_hints quote live stats. They are authored prose in monsters.json that
## names concrete numbers — "9000 HP with high defense", "Defense 400 behind
## 7800 HP", "Speed 28 means it outspeeds almost everything" — and those numbers
## live somewhere else, in the same file, under `stats`.
##
## That is the lie-in-the-label shape with a rebalance as the trigger. The x10
## re-denomination (2026-07-28) already broke a batch of these; they were caught
## by hand and fixed. Nothing stops the next tuning pass from doing it again, and
## a wrong number here is worse than no number: the hint is tactical advice the
## player is meant to act on, and it reads as authoritative because it is specific.
##
## All 7 quoting hints were verified correct at the time of writing. This keeps
## them that way by DERIVING the expected value from the monster's own stats
## rather than pinning the prose.

const MONSTERS := "res://data/monsters.json"

## Word -> stat key. Only stats that actually appear in hint prose.
const STAT_WORDS := {
	"hp": "max_hp", "health": "max_hp",
	"defense": "defense", "def": "defense",
	"speed": "speed", "spd": "speed",
	"attack": "attack", "atk": "attack",
	"magic": "magic",
}


func _monsters() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(MONSTERS))
	return d if d is Dictionary else {}


## Collect (monster_id, hint) for every setup_hint at any nesting depth.
## Walks rather than assuming a level — the hints sit under `one_shot`, not the
## monster root, and a top-level-only reader silently finds zero.
func _hints() -> Array:
	var out: Array = []
	for mid in _monsters():
		var m = _monsters()[mid]
		if not (m is Dictionary):
			continue
		var stack: Array = [m]
		while not stack.is_empty():
			var node = stack.pop_back()
			if not (node is Dictionary):
				continue
			if node.has("setup_hint"):
				out.append([mid, str(node["setup_hint"])])
			for k in node:
				if node[k] is Dictionary:
					stack.append(node[k])
	return out


func test_control_hints_exist_and_some_quote_numbers() -> void:
	var h := _hints()
	assert_gt(h.size(), 20, "must find setup_hints — a walker that returns 0 makes every check below vacuous")
	var quoting := 0
	var re := RegEx.new()
	re.compile("(?i)(hp|defense|speed|attack|magic)\\s+([0-9]+)|([0-9]+)\\s+(hp|defense)")
	for pair in h:
		if re.search(pair[1]) != null:
			quoting += 1
	assert_gt(quoting, 3, "must find hints that quote concrete stat numbers, else this file guards nothing")


func test_quoted_stat_numbers_match_the_monster() -> void:
	var mons := _monsters()
	var re := RegEx.new()
	assert_eq(re.compile("(?i)(hp|health|defense|def|speed|spd|attack|atk|magic)\\s+([0-9]+)|([0-9]+)\\s+(hp|health|defense|def)"), OK)
	var wrong: Array = []
	for pair in _hints():
		var mid: String = pair[0]
		var hint: String = pair[1]
		var stats = mons.get(mid, {}).get("stats", {})
		if not (stats is Dictionary) or stats.is_empty():
			continue
		for m in re.search_all(hint):
			# Either "WORD 123" (groups 1,2) or "123 WORD" (groups 3,4).
			var word: String = m.get_string(1) if m.get_string(1) != "" else m.get_string(4)
			var num: String = m.get_string(2) if m.get_string(2) != "" else m.get_string(3)
			if word == "" or num == "":
				continue
			var key: String = STAT_WORDS.get(word.to_lower(), "")
			if key == "" or not stats.has(key):
				continue
			var actual: int = int(stats[key])
			if int(num) != actual:
				wrong.append("%s: hint says %s %s, actual %s=%d" % [mid, word, num, key, actual])
	assert_eq(wrong, [], "setup_hints quote live stats and these no longer match. A wrong number here is "
		+ "tactical advice the player acts on, and reads as authoritative because it is specific. "
		+ "Fix the prose or the stat, do not silence this: %s" % [wrong])
