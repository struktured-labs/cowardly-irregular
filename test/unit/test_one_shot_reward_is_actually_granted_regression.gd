extends GutTest

## FORTY-ONE BOSSES PROMISED A TROPHY NOBODY COULD RECEIVE.
##
## 2026-09-11. `data/monsters.json` gives 50 monsters a `one_shot` block, and 41 of
## those declare `"reward_item": "boss_trophy"`. Nothing in `src/` had ever read that
## block. `_check_one_shot()` derives the achievement entirely from battle state —
## `_first_damage_phase` and `_execution_phase_count` — so the rank fired, the EXP
## bonus applied, the gold bonus applied, the victory banner said ONE-SHOT, and the
## one reward the DATA actually names was never granted.
##
## `boss_trophy` is a real item: "Proof you beat something that was designed to be
## hard. Mounted on an invisible plaque in your save file." It appeared in no drop
## table, no shop, no quest, no chest. It was unobtainable by any path in the game.
##
## THE SHAPE, which is why this file exists and not just the fix: a feature can be
## fully working and still not do the thing its data says. Every observable part of
## the one-shot system was correct. The bug was a key nobody read, and no test could
## have caught it by exercising the feature — you catch it by asking whether the
## authored data reaches the code.
##
## ⚠️ WHAT THIS FILE CANNOT SEE, stated because the arms below look stronger than
## they are. It reads the corpus and calls the delivery helper. It does NOT play a
## battle, so it cannot tell you a player reaches the branch — @cowir-battle's rule,
## earned by retracting their own fix: A TEST THAT CALLS THE REPAIRED FUNCTION
## DIRECTLY CANNOT TELL EITHER. The structural arm is the weakest here and is marked
## as such; treat it as "the wiring is present", never as "the trophy was received".

const MONSTERS := "res://data/monsters.json"
const ITEMS := "res://data/items.json"
const BATTLE_MANAGER_SRC := "res://src/battle/BattleManager.gd"
const BESTIARY_SRC := "res://src/bestiary/BestiarySystem.gd"

## Keys authored inside `one_shot` that NOTHING reads, each with the reason it is
## debt rather than a defect. Both are one edit from being a finding, so they are
## named here instead of being silently tolerated by a key-count assertion.
##
## hp_threshold — TWO DIFFERENT ACHIEVEMENTS, and which one the game means is an
##   open question for struktured, not a gap to close. I first wrote "a leftover
##   from a different design"; @cowir-battle, who owns this code, pushed back and
##   they are right — I asserted a cause I had not checked, and there is no recorded
##   ruling anywhere near _check_one_shot to support it.
##     shipped   TEMPO      every enemy died in the same execution phase as the
##                          first damage. Rewards a full-party alpha strike inside
##                          one turn; composes with Full Bank.
##     authored  MAGNITUDE  one blow removed >= hp_threshold (2500, 5000, …) HP.
##                          A different build entirely. 50 monsters carry a number.
##   They disagree about the same fight: a five-member Advance that kills in one
##   phase is a one-shot under tempo and fails a 2500 threshold if no single hit
##   reached it. WHICHEVER IS CHOSEN, SOME OF THE 41 TROPHIES CHANGE HANDS — so the
##   right resting place is this pin, not a fix.
## setup_hint — RETIRED 2026-09-11. 50 lines of authored tactical advice ("Stack
##   attack buffs, defer for max AP, then unleash all at once") that no surface had
##   ever shown. This entry said "the bestiary would be the obvious home" and the
##   home was one field away: BestiarySystem now carries it out with the entry and
##   the detail panel shows it under the drops, on defeated monsters only.
## Monsters that MUST appear in the one_shot walk. A count floor passes while members
## quietly leave it; these do not.
const PREMISE_MONSTERS: Array[String] = ["ice_dragon", "fire_dragon"]

const UNREAD_ONE_SHOT_KEYS := {
	"hp_threshold": "an unresolved design question, not debt: authored = damage MAGNITUDE, shipped = TEMPO. Struktured's call; see the note above",
}


## Parsed once. The first cut re-read and re-parsed monsters.json INSIDE the walk
## over its own keys, which is 106 parses of a 4k-line file per arm — 30s and 11,000
## asserts for five tests, in a suite the whole fleet waits on.
var _cache: Dictionary = {}


func _json(path: String) -> Dictionary:
	if _cache.has(path):
		return _cache[path]
	var raw: String = FileAccess.get_file_as_string(path)
	assert_ne(raw, "", "Expected %s to be readable" % path)
	var parsed: Variant = JSON.parse_string(raw)
	var out: Dictionary = parsed as Dictionary if parsed is Dictionary else {}
	_cache[path] = out
	return out


func _monsters() -> Dictionary:
	var d := _json(MONSTERS)
	var inner: Variant = d.get("monsters", d)
	return inner as Dictionary if inner is Dictionary else {}


## monster id -> its one_shot block
func _one_shot_blocks() -> Dictionary:
	if _cache.has("__one_shot"):
		return _cache["__one_shot"]
	var out: Dictionary = {}
	var ms := _monsters()
	for mid in ms.keys():
		var m: Variant = ms[mid]
		if not (m is Dictionary):
			continue
		var os_block: Variant = (m as Dictionary).get("one_shot", null)
		if os_block is Dictionary:
			out[str(mid)] = os_block
	_cache["__one_shot"] = out
	return out


## PREMISE. Every arm below walks the one_shot corpus; if the block is renamed or
## the file moves, the walk finds nothing and the assertions pass having measured
## an empty set. The cheap repair for a red here is to follow the rename.
func test_premise_the_one_shot_corpus_is_present() -> void:
	# THE CONTROL MUST NOT BE DRAINABLE EITHER. Measured 2026-09-11: emptying PREMISE_MONSTERS
	# gave Failed 0, Risky 0 — the loop below runs zero times and the corpus floor is a
	# literal that still passes, so the named-member fix I added an hour ago introduced
	# a new silent control. @cowir-sfx's cell: every `for x in LIST` and every
	# `size() >= LIST.size()` is silent at LIST == []. Pinned to a LITERAL — and gte,
# not eq: @cowir-overworld's PLUS-ONE magnitude showed the eq form REDS when a lane
# correctly adds an anchor. Their two questions: may this set grow on correct work
# (yes — another anchor is ordinary), and is growth itself the signal (no). A guard
# that reds on correct work is how suppression entries get written in the first place.
	assert_gte(PREMISE_MONSTERS.size(), 2,
		"PREMISE_MONSTERS holds %d, fewer than the 2 this guard defends — the named-member check below is going vacuous. ADDING an anchor is free; losing one is not." % PREMISE_MONSTERS.size())
	var blocks := _one_shot_blocks()
	# NAMED MEMBERS, not just a count — see the note on this arm.
	var absent: Array[String] = []
	for mid in PREMISE_MONSTERS:
		if not blocks.has(mid):
			absent.append(mid)
	assert_eq(absent.size(), 0,
		"a monster that carries a one_shot block has stopped contributing: %s — the walk is covering less than it did and a count floor cannot see that" % ", ".join(absent))
	assert_gt(blocks.size(), 40,
		"only %d monsters carry a one_shot block; there were 50 on 2026-09-11, so either the block was renamed or this walk is not reading monsters.json" % blocks.size())


## THE RATCHET, bidirectional. A key authored inside one_shot must be read by the
## game, or be named above with its reason.
##   grows   -> someone authored a new one_shot field nothing consumes
##   shrinks -> someone wired hp_threshold or setup_hint; delete its line
func test_every_one_shot_key_is_either_read_or_named_as_debt() -> void:
	# TWO consumers now, and the corpus must hold both or a live key reads as dead:
	# BattleManager grants the reward, the bestiary shows the hint. A BattleManager-only
	# corpus was correct until the bestiary landed and is a partial one after — the
	# "consumer moved house" case, which turns a real wiring into a false debt entry.
	var src: String = FileAccess.get_file_as_string(BATTLE_MANAGER_SRC) + FileAccess.get_file_as_string(BESTIARY_SRC)
	assert_true(src.contains("func _check_one_shot"),
		"the BattleManager half of the consumer corpus is missing — every key below would read as unconsumed for that reason")
	assert_true(src.contains("_one_shot_hint_of"),
		"the bestiary half of the consumer corpus is missing — setup_hint would read as unconsumed and this file would claim a debt that was paid")

	var keys: Dictionary = {}
	for mid in _one_shot_blocks().keys():
		for k in (_one_shot_blocks()[mid] as Dictionary).keys():
			keys[str(k)] = int(keys.get(str(k), 0)) + 1

	var unread: Array[String] = []
	var newly_read: Array[String] = []
	for k in keys.keys():
		var key: String = str(k)
		var is_read: bool = src.contains("\"%s\"" % key)
		if is_read and UNREAD_ONE_SHOT_KEYS.has(key):
			newly_read.append(key)
		elif not is_read and not UNREAD_ONE_SHOT_KEYS.has(key):
			unread.append("%s (authored on %d monsters)" % [key, int(keys[k])])

	assert_eq(unread.size(), 0,
		"a one_shot field is authored and never read: %s — either consume it (BattleManager grants, the bestiary displays) or add it to UNREAD_ONE_SHOT_KEYS with the reason it is debt" % ", ".join(unread))
	# STALE-BY-DELETION. The ratchet above only compares keys the corpus still AUTHORS,
	# so a key that disappears entirely leaves its debt entry behind with nothing to
	# notice — an inert suppression created by deletion rather than by being written
	# wrong. Same cell I closed on the ability guard; left open here until measured.
	var orphaned: Array[String] = []
	for k in UNREAD_ONE_SHOT_KEYS.keys():
		if not keys.has(str(k)):
			orphaned.append(str(k))
	orphaned.sort()
	assert_eq(orphaned.size(), 0,
		"UNREAD_ONE_SHOT_KEYS names a field no monster authors any more: %s — the entry is a claim about a corpus that has moved on. Delete the line." % ", ".join(orphaned))

	assert_eq(newly_read.size(), 0,
		"GOOD NEWS, STALE LIST: %s is now read by BattleManager. Delete its key from UNREAD_ONE_SHOT_KEYS at the top of this file so it stops claiming the data is dead." % ", ".join(newly_read))


## The reward the fix now grants has to be a real item, or the grant delivers an id
## the inventory cannot name. This is the arm that would catch a typo in the DATA,
## which the structural arm below cannot see.
func test_every_declared_one_shot_reward_is_a_real_item() -> void:
	var items := _json(ITEMS)
	assert_gt(items.size(), 50, "items.json looks empty (%d entries) — the check below would pass vacuously" % items.size())

	var declared: int = 0
	var phantom: Array[String] = []
	for mid in _one_shot_blocks().keys():
		var reward: String = str((_one_shot_blocks()[mid] as Dictionary).get("reward_item", ""))
		if reward == "":
			continue
		declared += 1
		if not items.has(reward):
			phantom.append("%s -> %s" % [str(mid), reward])

	assert_gt(declared, 35,
		"only %d monsters declare a one_shot reward_item; there were 41 — if this dropped, say so deliberately" % declared)
	assert_eq(phantom.size(), 0,
		"a one_shot reward names an item that is not in items.json: %s" % ", ".join(phantom))


## BEHAVIOURAL. Calls the SHIPPED delivery helper — the one both the drop path and
## the new one-shot path go through — rather than a copy of it. Proves the trophy
## reaches the victory-screen list and merges by quantity. It proves nothing about
## whether a battle gets here; see the file header.
func test_the_shared_delivery_records_the_trophy() -> void:
	var bm := get_node_or_null("/root/BattleManager")
	if bm == null:
		pending("BattleManager autoload not present in this harness — delivery not exercised")
		return
	assert_true(bm.has_method("_deliver_item"),
		"BattleManager._deliver_item must exist — it is the single delivery both the drop path and the one-shot reward use")

	var drops: Array = []
	bm._deliver_item("boss_trophy", drops)
	assert_eq(drops.size(), 1, "one delivery should append one entry, got %d" % drops.size())
	assert_eq(str(drops[0].get("item", "")), "boss_trophy", "the entry must name the delivered item")
	assert_eq(int(drops[0].get("qty", 0)), 1, "first delivery is qty 1")

	bm._deliver_item("boss_trophy", drops)
	assert_eq(drops.size(), 1, "a second delivery of the same id must MERGE, not append a duplicate row")
	assert_eq(int(drops[0].get("qty", 0)), 2, "merged quantity should be 2, got %d" % int(drops[0].get("qty", 0)))

	# Guard arm: an empty id must not produce a phantom row on the victory screen.
	bm._deliver_item("", drops)
	assert_eq(drops.size(), 1, "an empty item id must be refused, not delivered as a nameless row")


## STRUCTURAL, and the weakest arm in the file — it reads source text, so it can
## only say the wiring is present. Kept because the arm above cannot distinguish
## "the helper works" from "the helper is called by the one-shot path", and that
## distinction is the entire bug this file exists for.
func test_the_one_shot_path_reads_the_reward_and_delivers_it() -> void:
	var src: String = FileAccess.get_file_as_string(BATTLE_MANAGER_SRC)
	assert_true(src.contains("\"reward_item\""),
		"BattleManager must read the one_shot reward_item key — this is the whole fix")
	var idx: int = src.find("\"reward_item\"")
	assert_gt(idx, -1, "reward_item read must exist")
	var window_start: int = max(0, idx - 400)
	var window: String = src.substr(window_start, (idx - window_start) + 400)
	assert_true(window.contains("_one_shot_achieved"),
		"the reward_item read must be guarded by _one_shot_achieved — an unguarded read would hand the trophy out for any victory")
	assert_true(window.contains("_deliver_item"),
		"the one-shot reward must go through _deliver_item so it reaches the victory screen and the EventLog, not straight into an inventory dict")
