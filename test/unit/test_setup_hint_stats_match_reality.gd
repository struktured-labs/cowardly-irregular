extends GutTest

## setup_hints quote live stats. They are authored prose in monsters.json that
## names concrete numbers — "9000 HP with high defense", "Defense 400 behind
## 7800 HP", "Speed 28 means it outspeeds almost everything" — and those numbers
## live somewhere else, in the same file, under `stats`.
##
## ⚠️ AS MEASURED 2026-07-29: nothing reads setup_hint. Zero consumers in src/
## (controls: drop_table 7, exp_reward 9, weaknesses 25). The whole `one_shot` block was
## authored ahead of its consumer across 50 monsters; no player had seen one of these
## strings. The measurement is DATED on purpose — a dated finding stays true forever,
## while the undated present tense it replaced ("nothing reads this TODAY") becomes a
## lie the day someone wires the field, and misdirects whoever reads it next.
##
## That correction matters, because the first version of this file justified itself
## with "tactical advice the player is meant to act on" — which was false, and would
## have made this guard *evidence that the field is wired*. A mutation-verified
## two-directional ratchet is persuasive; pointed at unconsumed data it certifies a
## liveness that doesn't exist, and the next person auditing `one_shot` believes it.
## (cowir-battle, msg 3355 — they measured it; I had verified the numbers were right
## and never asked whether anything displays them.)
##
## THE REAL REASON TO KEEP IT: this corpus is authored ahead of a consumer that may
## still arrive. The x10 re-denomination already broke a batch of these hints and they
## were fixed by hand. Keeping them true costs nothing now and makes wiring the field
## a one-line change instead of a 50-monster audit — the guard protects the option,
## not a live surface.
##
## All 7 quoting hints were correct at the time of writing. This keeps them that way
## by DERIVING the expected value from the monster's own stats rather than pinning
## the prose, so it survives any rebalance that updates both.

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
	assert_eq(wrong, [], "setup_hints quote live stats and these no longer match — most likely a "
		+ "rebalance moved the stat and left the prose, which is what the x10 re-denomination did. "
		+ "Before judging how urgent this is, read this file's header — it carries the DATED "
		+ "measurement of what does and does not read setup_hint, and the reason keeping these "
		+ "true is cheap insurance rather than a live fix. Fix the prose or the stat: %s" % [wrong])
