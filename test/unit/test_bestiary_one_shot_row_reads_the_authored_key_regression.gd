extends GutTest

## THE BESTIARY HAD A ROW FOR A KEY NOBODY WRITES.
##
## 2026-09-11. `BestiaryMenu._format_drops` appends "(One-shot: <item>)" to a
## monster's drop line, and `BestiarySystem` fed it `data.get("one_shot_reward")`.
## **No monster has ever authored that key** — 0 occurrences across monsters.json and
## bestiary.json — while 41 bosses author the reward one level down, inside the
## `one_shot` block as `reward_item: "boss_trophy"`. The row never rendered for
## anything, and the comment beside it says "set in monsters.json for special
## enemies".
##
## 🔑 MIRROR IMAGE OF THE BATTLEMANAGER BUG FIXED THE SAME DAY, and the pair is the
## reason this file exists rather than a one-line data edit. There, the DATA declared
## a reward and no code read it. Here, the UI has a READER and no data writes it.
## Same gap, opposite ends, one key name apart — and neither end could see the other,
## because each was locally consistent. A scan for "authored keys nothing reads" finds
## the first and is structurally blind to the second.
##
## ⚠️ WHAT THIS DOES NOT CLAIM. It checks that the resolution reaches the authored
## key and that the corpus still authors it. It does NOT open the menu, so it cannot
## tell you a player sees the row — @cowir-battle's rule, and the honest limit here.
## `_format_drops` is the renderer and it is not exercised below.

const MONSTERS := "res://data/monsters.json"
const BESTIARY_SYSTEM := "res://src/bestiary/BestiarySystem.gd"

## Bosses that must keep a one_shot reward, by name. A count floor passes while
## members quietly leave it; these do not.
const PREMISE_BOSSES: Array[String] = ["ice_dragon", "fire_dragon"]

var _cache: Dictionary = {}


func _monsters() -> Dictionary:
	if _cache.has("m"):
		return _cache["m"]
	var raw: String = FileAccess.get_file_as_string(MONSTERS)
	assert_ne(raw, "", "monsters.json must be readable")
	var parsed: Variant = JSON.parse_string(raw)
	var root: Dictionary = parsed as Dictionary if parsed is Dictionary else {}
	var inner: Variant = root.get("monsters", root)
	var out: Dictionary = inner as Dictionary if inner is Dictionary else {}
	_cache["m"] = out
	return out


## monster id -> the reward its one_shot block declares
func _authored_rewards() -> Dictionary:
	var out: Dictionary = {}
	for mid in _monsters().keys():
		var m: Variant = _monsters()[mid]
		if not (m is Dictionary):
			continue
		var block: Variant = (m as Dictionary).get("one_shot", null)
		if block is Dictionary:
			var reward: String = str((block as Dictionary).get("reward_item", ""))
			if reward != "":
				out[str(mid)] = reward
	return out


## PREMISE, by NAME not by count — a floor is blind to partial loss.
func test_premise_the_authored_rewards_are_present() -> void:
	# THE CONTROL MUST NOT BE DRAINABLE EITHER. Measured 2026-09-11: emptying PREMISE_BOSSES
	# gave Failed 0, Risky 0 — the loop below runs zero times and the corpus floor is a
	# literal that still passes, so the named-member fix I added an hour ago introduced
	# a new silent control. @cowir-sfx's cell: every `for x in LIST` and every
	# `size() >= LIST.size()` is silent at LIST == []. Pinned to a literal.
	assert_eq(PREMISE_BOSSES.size(), 2,
		"PREMISE_BOSSES has been emptied or resized — the named-member check below is now vacuous. If a member was deliberately retired, change this number in the same edit.")
	var rewards := _authored_rewards()
	var absent: Array[String] = []
	for mid in PREMISE_BOSSES:
		if not rewards.has(mid):
			absent.append(mid)
	assert_eq(absent.size(), 0,
		"a boss that carries a one_shot reward has stopped: %s — if the data moved, this whole file is about a key that no longer exists" % ", ".join(absent))
	assert_gt(rewards.size(), 35,
		"only %d monsters declare a one_shot reward; there were 41" % rewards.size())


## THE BUG. The flat key must still be unauthored — if it ever becomes the real
## vocabulary, the fallback below is the thing to keep and this arm is the warning.
func test_the_flat_key_is_still_the_one_nobody_writes() -> void:
	var flat: int = 0
	for mid in _monsters().keys():
		var m: Variant = _monsters()[mid]
		if m is Dictionary and str((m as Dictionary).get("one_shot_reward", "")) != "":
			flat += 1
	assert_eq(flat, 0,
		"%d monster(s) now author a flat one_shot_reward. That is fine — the resolution prefers it — but the nested block is what 41 of them use, so make sure the two do not disagree for the same monster." % flat)


## The resolution must reach the nested block, or the row is still dead. Reads the
## SHIPPED source rather than reimplementing the lookup: a copy of the resolution
## would pass while the game's own copy was wrong.
func test_the_bestiary_resolves_through_the_nested_block() -> void:
	var src: String = FileAccess.get_file_as_string(BESTIARY_SYSTEM)
	assert_ne(src, "", "BestiarySystem.gd must be readable")
	# THE CALL SITE, not the symbol. Measured 2026-09-11: asserting
	# contains("_one_shot_reward_of") stayed GREEN when the entry was reverted to the
	# flat key, because the HELPER DEFINITION still matched. A guard satisfied by a
	# function's existence says nothing about whether anything calls it — the same
	# hollowness that let my aftermath guard pass on a commented-out gate, and the
	# same reason the behavioural arm below cannot stand alone: calling the repaired
	# function directly cannot tell you the game reaches it.
	assert_true(src.contains("\"one_shot_reward\": _one_shot_reward_of(data)"),
		"the bestiary entry must be BUILT from the resolver. Found neither that assignment nor a replacement — if the wiring moved, point this arm at the new one; a bare data.get(\"one_shot_reward\") reads a key no monster authors")
	assert_false(src.contains("\"one_shot_reward\": data.get(\"one_shot_reward\""),
		"the entry is back on the flat key, which no monster in the corpus writes — the bestiary row is dead again")
	assert_true(src.contains("\"reward_item\""),
		"the resolver must read reward_item from the one_shot block, which is where all 41 rewards actually live")


## BEHAVIOURAL. Calls the SHIPPED static, not a copy of it.
func test_the_shipped_resolver_finds_a_real_reward() -> void:
	var rewards := _authored_rewards()
	if rewards.is_empty():
		fail_test("no authored rewards to resolve — the premise arm should already have failed")
		return
	var mid: String = PREMISE_BOSSES[0]
	var data: Variant = _monsters().get(mid, null)
	assert_true(data is Dictionary, "%s must be in monsters.json" % mid)
	if not (data is Dictionary):
		return

	var got: Variant = BestiarySystem._one_shot_reward_of(data as Dictionary)
	assert_eq(str(got), str(rewards[mid]),
		"the shipped resolver returned %s for %s; the data declares %s" % [str(got), mid, str(rewards[mid])])

	# Negative: a monster with no one_shot block must resolve to null, or every row
	# would claim a reward.
	var empty: Dictionary = {"name": "probe", "level": 1}
	assert_eq(BestiarySystem._one_shot_reward_of(empty), null,
		"a monster with no one_shot block must resolve to null — otherwise the bestiary row appears for everything and means nothing")
