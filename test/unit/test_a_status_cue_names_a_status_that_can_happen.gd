extends GutTest

## A status_* cue can only ever sound if something composes its key. play_status builds
## "status_" + name from an ABILITY EFFECT (BattleScene:4545) or an applied status
## (BattleManager:4601), so a cue whose suffix appears in neither corpus is unreachable by
## construction — authored, on disk, passing every orphan and loop-parity guard this lane has,
## and silent forever. cowir-ai found the same shape in the autogrind status ring (`slow`).
##
## ⚠️ THE APPLICABLE SET IS DATA-DRIVEN AND TOOK THREE PREDICATES TO GET RIGHT (2026-09-17):
##   add_status("x") literals in src/            15 ids   <- far too narrow; statuses are applied
##                                                           COMPOSED, add_status(entry["status"])
##   + authored effect/status/secondary_effect   75 ids   <- the real set
## and `status_cured` STILL looked unreachable until read: it is mapped from the ABILITY effects
## cure_all_status/cure_status at SoundManager:472. A cue keyed on an ability and one keyed on a
## status are indistinguishable from the key name alone, so this arm checks BOTH corpora.

const MANIFEST := "res://data/sfx_manifest.json"
const SOUND_MANAGER := "res://src/audio/SoundManager.gd"
const ABILITIES := "res://data/abilities.json"
const MONSTERS := "res://data/monsters.json"
## ITEMS is load-bearing, not thoroughness: _ITEM_EFFECT_SFX maps ITEM effects to status cues, so
## `status_cured` is reached by an item authoring cure_all_status and by nothing else. Omitting this
## file made the arm score that cue reachable off the MAP ROW ALONE — right answer, no basis.
const ITEMS := "res://data/items.json"

## Declared UNREACHABLE with a reason, not suppressed. Retirement trigger below: the day anything
## authors this status the entry must go, because the cue starts working and the note becomes a
## lie. This is a claim about DATA — one JSON edit from false — which is why it is armed rather
## than left in prose (cowir-autogrind's code-claim vs data-claim distinction).
const KNOWN_UNREACHABLE := {
	"paralyze": "no ability, monster or src/ literal authors a status named paralyze; the cue and its SOUNDS entry at SoundManager:171 are authored-ahead",
}


func _json(path: String) -> Dictionary:
	var t: String = FileAccess.get_file_as_string(path)
	if t == "":
		return {}
	var p = JSON.parse_string(t)
	return p if p is Dictionary else {}


## Every status name the game can put into play: composed applications are invisible to a literal
## scan, so authored data is the larger half of this corpus.
func _applicable() -> Dictionary:
	var out := {}
	var src: String = FileAccess.get_file_as_string(SOUND_MANAGER)
	var code: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	for m in RegEx.create_from_string('add_status\\(\\s*"([a-z_]+)"').search_all(code):
		out[m.get_string(1)] = true
	var authored := {}
	for path in [ABILITIES, MONSTERS]:
		var raw: String = FileAccess.get_file_as_string(path)
		for m in RegEx.create_from_string('"(?:effect|status|secondary_effect)"\\s*:\\s*"([a-z_]+)"').search_all(raw):
			authored[m.get_string(1)] = true
			out[m.get_string(1)] = true
	## items.json spells an effect as a KEY, not a value — `"effects": {"cure_all_status": true}` —
	## so the regex above cannot see one. Parsed, not pattern-matched: a third wrong predicate on
	## this one corpus would be a pattern of its own.
	var items: Dictionary = _json(ITEMS)
	var item_rows = items.get("items", items)
	if item_rows is Dictionary:
		for iid in item_rows.keys():
			var row = item_rows[iid]
			if row is Dictionary and row.get("effects") is Dictionary:
				for eff in (row["effects"] as Dictionary).keys():
					authored[str(eff)] = true
	## Cues reached through _ITEM_EFFECT_SFX are keyed on an ITEM EFFECT, not on a status name. The
	## map row is NOT proof: the cue is reachable only if something authors the effect it keys on.
	## Counting the row alone scored status_cured reachable while never opening items.json.
	for m in RegEx.create_from_string('\\["([a-z_]+)",\\s*"status_([a-z_]+)"\\]').search_all(src):
		if authored.has(m.get_string(1)):
			out[m.get_string(2)] = true
	return out


func test_every_status_cue_names_a_status_something_can_apply() -> void:
	var sfx: Dictionary = _json(MANIFEST).get("sfx", {})
	assert_gt(sfx.size(), 0, "VOID, not clean: the sfx manifest read back 0 entries")
	var live: Dictionary = _applicable()
	assert_gt(live.size(), 30,
		"CONTROL: only %d applicable statuses derived — the corpus is broken, not the data" % live.size())
	var cues: Array = []
	var unreachable: Array = []
	for k in sfx.keys():
		var key: String = str(k)
		if not key.begins_with("status_"):
			continue
		cues.append(key)
		var name: String = key.substr(7)
		if not live.has(name) and not KNOWN_UNREACHABLE.has(name):
			unreachable.append(key)
	assert_gt(cues.size(), 10, "CONTROL: %d status cues found — the prefix scan is broken" % cues.size())
	assert_eq(unreachable, [],
		"status cues nothing can compose (%d) — authored, on disk, and silent forever: %s" % [unreachable.size(), unreachable])
	print("[status-reach] %d status cues, %d applicable statuses, %d declared unreachable" % [cues.size(), live.size(), KNOWN_UNREACHABLE.size()])


func test_a_declared_unreachable_status_is_still_unreachable() -> void:
	var live: Dictionary = _applicable()
	assert_gt(live.size(), 30, "CONTROL: the applicable corpus must derive, or this arm judges nothing")
	assert_gt(KNOWN_UNREACHABLE.size(), 0,
		"KNOWN_UNREACHABLE is empty — every cue is reachable, so DELETE THIS ARM with the last entry rather than leaving it asserting nothing")
	for name in KNOWN_UNREACHABLE.keys():
		assert_false(live.has(str(name)),
			"%s IS now authored — the cue works, so DELETE its KNOWN_UNREACHABLE entry and the register note; the declaration has become a lie" % str(name))
		assert_gt(str(KNOWN_UNREACHABLE[name]).length(), 40,
			"%s is declared without a reason long enough to be one" % str(name))
