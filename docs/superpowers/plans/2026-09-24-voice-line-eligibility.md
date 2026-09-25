# Voice Line Eligibility (piece 2a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Party combat lines become situation-aware and LLM-chosen while staying voiced: tagged lines play only when their condition is true (fixing ally-naming lines in solo duels), and with LLM dialogue on, the LLM picks among eligible voiced lines instead of writing silent ones.

**Architecture:** A static `VoiceLines` helper gives every reader one way to read a `trigger_voices` element (string or `{"line","when"}`) with its original list index. `VoiceLineTags` evaluates tags as pure predicates over `PartyCombatLineContext`. `PartyPersonas.pick_trigger_voice` filters by eligibility and prefers tagged lines. `BattleManager._run_party_line_async` builds the context first, then (LLM on) asks `LLMService.choose()` for a number among the eligible lines and emits the matching clip.

**Tech Stack:** Godot 4.4.1, GDScript, GUT tests via `tools/run_tests.sh`.

**Spec:** `docs/superpowers/specs/2026-09-24-local-tts-voice-design.md` (piece 2a, contract 1). Read both.

## Global Constraints

- List index `n` of a `trigger_voices` value is clip `voice_<job>_<trigger>_<n>`; index 0 is `voice_<job>_<trigger>`. **A filtered pick must still use the entry's ORIGINAL index.**
- An element is a string or `{"line": String, "when": String | Array[String]}`. Tags never affect indexing.
- `source_sha` / every text join uses the `line` text, never `str(element)`.
- Tags are evaluated **by code**, never by the LLM.
- `.gd` comments are one line max (`##` docblocks are the established idiom).
- Every godot invocation: `XDG_DATA_HOME=$PWD/tmp/xdg`, `--audio-driver Dummy`. After adding a `class_name` file, run `XDG_DATA_HOME=$PWD/tmp/xdg godot --headless --audio-driver Dummy --import --quit` before tests.
- Lanes run their own test files, never the full suite (cowir-main gates the fold).
- Branch: `llm/voice-line-eligibility`. Never commit to main.
- Web behaviour unchanged.

## File Structure

| File | Responsibility |
|---|---|
| Create `src/llm/VoiceLines.gd` | Element shape: `text_of`, `tags_of`, `entries_of` (with original index), `variant_key`, choice labels and mapping. Static. |
| Create `src/llm/VoiceLineTags.gd` | Tag vocabulary and predicates over `PartyCombatLineContext`: `is_known_tag`, `tag_holds`, `is_eligible`. Static. |
| Modify `src/llm/PartyPersonas.gd` | Read entries via `VoiceLines`; `pick_trigger_voice(job, event, ctx)` with eligibility; `eligible_trigger_entries`. |
| Modify `src/llm/LLMService.gd` | `_guard_choice` treats digits as word characters. |
| Modify `src/llm/DialoguePrompts.gd` | `build_party_line_choice` prompt builder. |
| Modify `src/battle/BattleManager.gd` | `_run_party_line_async`: context first, eligibility pick, LLM choose path. |
| Modify 3 tests | `_variants` (voice pack), signature guard, long-quip reader use `VoiceLines.text_of`. |

---

### Task 1: One reader for a line, with its original index

**Files:**
- Create: `src/llm/VoiceLines.gd`
- Modify: `src/llm/PartyPersonas.gd:58-97`
- Modify: `test/unit/test_party_voice_pack_regression.gd:36`
- Modify: `test/unit/test_persona_signature_line_names_current_ability.gd:56`
- Modify: `test/unit/test_a_long_quip_widens_before_it_grows_tall_regression.gd:49`
- Test: `test/unit/test_a_tagged_line_keeps_its_clip.gd`

**Interfaces:**
- Produces: `VoiceLines.text_of(entry: Variant) -> String`, `VoiceLines.tags_of(entry: Variant) -> Array[String]`, `VoiceLines.entries_of(raw: Variant) -> Array` (each `{"index": int, "line": String, "tags": Array[String]}`), `VoiceLines.variant_key(event_kind: String, n: int) -> String`, `PartyPersonas.get_trigger_entries(job_id: String, event_kind: String) -> Array`.

- [ ] **Step 1: Write the failing test**

`test/unit/test_a_tagged_line_keeps_its_clip.gd`:
```gdscript
extends GutTest

## A trigger_voices element may become {"line","when"} at the same index; its text, and so its clip, must not change.

var _saved_rogue: Dictionary = {}
var _saved_last: Dictionary = {}


func before_each() -> void:
	_saved_rogue = (PartyPersonas._data.get("rogue", {}) as Dictionary).duplicate(true)
	_saved_last = PartyPersonas._last_variant.duplicate()


func after_each() -> void:
	PartyPersonas._data["rogue"] = _saved_rogue
	PartyPersonas._last_variant = _saved_last


func _rogue_says(lines: Variant) -> void:
	var entry: Dictionary = _saved_rogue.duplicate(true)
	var tv: Dictionary = entry.get("trigger_voices", {})
	tv["turn_start"] = lines
	entry["trigger_voices"] = tv
	PartyPersonas._data["rogue"] = entry


func test_a_string_and_its_tagged_object_have_the_same_text() -> void:
	var s := "Cleric. When you're ready."
	assert_eq(VoiceLines.text_of(s), s)
	assert_eq(VoiceLines.text_of({"line": s, "when": "ally_alive:cleric"}), s,
		"tagging a line in place must not change its text, or its clip goes stale")


func test_tags_read_from_either_shape() -> void:
	assert_eq(VoiceLines.tags_of("plain"), [] as Array[String])
	assert_eq(VoiceLines.tags_of({"line": "x", "when": "none_down"}), ["none_down"] as Array[String])
	assert_eq(VoiceLines.tags_of({"line": "x", "when": ["ally_alive:mage", "ally_alive:rogue"]}),
		["ally_alive:mage", "ally_alive:rogue"] as Array[String])


func test_entries_keep_their_original_index_across_a_skipped_one() -> void:
	var e: Array = VoiceLines.entries_of(["zero", "", {"line": "two", "when": "ally_down"}])
	assert_eq(e.size(), 2, "the empty entry is skipped")
	assert_eq(int(e[0]["index"]), 0)
	assert_eq(int(e[1]["index"]), 2,
		"the entry after a skipped one must keep index 2, or it plays another line's clip")
	assert_eq(str(e[1]["line"]), "two")


func test_variant_key_matches_the_clip_contract() -> void:
	assert_eq(VoiceLines.variant_key("low_hp", 0), "low_hp")
	assert_eq(VoiceLines.variant_key("low_hp", 7), "low_hp_7")


func test_a_pick_names_its_own_clip_even_after_a_skipped_entry() -> void:
	_rogue_says(["zero", "", "two"])
	var seen := {}
	for i in 60:
		var p: Dictionary = PartyPersonas.pick_trigger_voice("rogue", "turn_start")
		seen[p["voice_key"]] = p["line"]
	assert_eq(seen.get("turn_start_2"), "two",
		"'two' sits at index 2 and must play voice_rogue_turn_start_2, not _1")
	assert_false(seen.has("turn_start_1"), "no line lives at index 1, so its clip must never be named")


func test_an_object_entry_is_spoken_as_its_line() -> void:
	_rogue_says([{"line": "Only when it's true.", "when": "none_down"}, "Plain."])
	for i in 40:
		var p: Dictionary = PartyPersonas.pick_trigger_voice("rogue", "turn_start")
		assert_false(str(p["line"]).begins_with("{"),
			"an object entry must be spoken as its line, got %s" % p["line"])


func test_every_list_reader_reads_the_line_not_the_element() -> void:
	for path in ["res://test/unit/test_party_voice_pack_regression.gd",
			"res://test/unit/test_persona_signature_line_names_current_ability.gd",
			"res://test/unit/test_a_long_quip_widens_before_it_grows_tall_regression.gd"]:
		var src: String = FileAccess.get_file_as_string(path)
		assert_ne(src, "", "could not read %s" % path)
		assert_true(src.contains("VoiceLines.text_of("),
			"%s must read a line through VoiceLines.text_of, or a tagged entry is hashed as JSON" % path)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `XDG_DATA_HOME=$PWD/tmp/xdg tools/run_tests.sh a_tagged_line_keeps_its_clip`
Expected: EC=3 (parse error: `VoiceLines` not declared).

- [ ] **Step 3: Create `src/llm/VoiceLines.gd`**

```gdscript
class_name VoiceLines
extends RefCounted

## A trigger_voices element is a line or {"line": str, "when": tag|[tags]}; its index n is clip _n either way.


## The spoken text of one element, whichever shape it is.
static func text_of(entry: Variant) -> String:
	if entry is Dictionary:
		return str((entry as Dictionary).get("line", ""))
	return "" if entry == null else str(entry)


## The element's tags; a bare string has none.
static func tags_of(entry: Variant) -> Array[String]:
	var out: Array[String] = []
	if not (entry is Dictionary):
		return out
	var w: Variant = (entry as Dictionary).get("when", null)
	if w is Array:
		for t in w:
			out.append(str(t))
	elif w != null and str(w) != "":
		out.append(str(w))
	return out


## Non-empty entries with their ORIGINAL index, so a filtered pick still names its own clip.
static func entries_of(raw: Variant) -> Array:
	var lines: Array = raw if raw is Array else [raw]
	var out: Array = []
	for n in lines.size():
		var text: String = text_of(lines[n])
		if text == "":
			continue
		out.append({"index": n, "line": text, "tags": tags_of(lines[n])})
	return out


## Clip key suffix for variant n: voice_<job>_<this>.
static func variant_key(event_kind: String, n: int) -> String:
	return event_kind if n == 0 else "%s_%d" % [event_kind, n]
```

- [ ] **Step 4: Route `PartyPersonas` through it**

Replace `get_trigger_lines`, `get_trigger_voice` and `pick_trigger_voice` in `src/llm/PartyPersonas.gd` (lines 58–97) with:
```gdscript
## A trigger's entries with their ORIGINAL list index: variant n speaks clip voice_<job>_<trigger>_<n>.
func get_trigger_entries(job_id: String, event_kind: String) -> Array:
	if not _data.has(job_id):
		return []
	var voices: Variant = _data[job_id].get("trigger_voices", {})
	if not (voices is Dictionary):
		return []
	return VoiceLines.entries_of((voices as Dictionary).get(event_kind, null))


## A trigger's line texts, in list order.
func get_trigger_lines(job_id: String, event_kind: String) -> Array:
	var out: Array = []
	for e in get_trigger_entries(job_id, event_kind):
		out.append(str(e["line"]))
	return out


## Variant 0's line: what every caller read before lists existed.
func get_trigger_voice(job_id: String, event_kind: String) -> String:
	var lines: Array = get_trigger_lines(job_id, event_kind)
	return "" if lines.is_empty() else str(lines[0])


var _last_variant: Dictionary = {}

## {"line", "voice_key"}: a random entry, never the same one twice running when there are two or more.
func pick_trigger_voice(job_id: String, event_kind: String) -> Dictionary:
	var entries: Array = get_trigger_entries(job_id, event_kind)
	if entries.is_empty():
		return {"line": "", "voice_key": ""}
	var e: Dictionary = _pick_no_repeat(job_id + "|" + event_kind, entries)
	return {"line": str(e["line"]), "voice_key": VoiceLines.variant_key(event_kind, int(e["index"]))}


## One entry at random, avoiding the ORIGINAL index spoken last time for this key.
func _pick_no_repeat(key: String, entries: Array) -> Dictionary:
	if entries.size() == 1:
		_last_variant[key] = int(entries[0]["index"])
		return entries[0]
	var last: int = int(_last_variant.get(key, -1))
	var pool: Array = entries.filter(func(x): return int(x["index"]) != last)
	if pool.is_empty():
		pool = entries
	var e: Dictionary = pool[randi() % pool.size()]
	_last_variant[key] = int(e["index"])
	return e
```

- [ ] **Step 5: Point the three test readers at `VoiceLines.text_of`**

`test/unit/test_party_voice_pack_regression.gd:36`:
```gdscript
		out.append([key, VoiceLines.text_of(lines[n])])
```
`test/unit/test_persona_signature_line_names_current_ability.gd:56`:
```gdscript
	return "\n".join(PackedStringArray((entry as Array).map(func(e): return VoiceLines.text_of(e)))) if entry is Array else VoiceLines.text_of(entry)
```
`test/unit/test_a_long_quip_widens_before_it_grows_tall_regression.gd:49`:
```gdscript
				out.append({"who": "%s/%s" % [job, trig], "text": '"%s"' % VoiceLines.text_of(ln)})
```

- [ ] **Step 6: Import, then run the new test and every existing reader**

```bash
XDG_DATA_HOME=$PWD/tmp/xdg godot --headless --audio-driver Dummy --import --quit
for t in a_tagged_line_keeps_its_clip a_trigger_can_speak_many_lines party_voice_pack_regression \
  persona_signature_line_names_current_ability a_long_quip_widens_before_it_grows_tall_regression \
  party_llm_dialogue_regression a_party_voice_matches_its_characters_gender; do
  XDG_DATA_HOME=$PWD/tmp/xdg tools/run_tests.sh $t > tmp/t.log 2>&1; echo "$t EC=$?"; done
```
Expected: every line `EC=0`.

- [ ] **Step 7: Mutation check**

Temporarily change `text_of`'s Dictionary branch to `return str(entry)`; re-run `a_tagged_line_keeps_its_clip`. Expected: EC=1 naming `test_a_string_and_its_tagged_object_have_the_same_text`. Revert. Then change `entries_of` to append `"index": out.size()`; re-run. Expected: EC=1 naming the skipped-entry arm. Revert.

- [ ] **Step 8: Commit**

```bash
git add src/llm/VoiceLines.gd src/llm/PartyPersonas.gd test/unit/test_a_tagged_line_keeps_its_clip.gd \
  test/unit/test_party_voice_pack_regression.gd test/unit/test_persona_signature_line_names_current_ability.gd \
  test/unit/test_a_long_quip_widens_before_it_grows_tall_regression.gd
git commit -m "feat(llm): a voice line may carry tags, and keeps its own clip"
```

---

### Task 2: Tags are predicates over the battle

**Files:**
- Create: `src/llm/VoiceLineTags.gd`
- Test: `test/unit/test_a_line_naming_an_ally_needs_that_ally.gd`

**Interfaces:**
- Consumes: `PartyCombatLineContext` (`speaker_name`, `speaker_status`, `party[]` of `{name, job_id, hp_pct, is_alive}`, `enemies[]` of `{name, hp_pct}`; HP is 0–100).
- Produces: `VoiceLineTags.is_known_tag(tag: String) -> bool`, `VoiceLineTags.tag_holds(tag: String, ctx: PartyCombatLineContext) -> bool`, `VoiceLineTags.is_eligible(tags: Array, ctx: PartyCombatLineContext) -> bool`.

- [ ] **Step 1: Write the failing test**

`test/unit/test_a_line_naming_an_ally_needs_that_ally.gd`:
```gdscript
extends GutTest

## A tagged line plays only when its condition is true; the solo duel is where an ally-naming line was wrong.


func _ctx(party: Array, enemies: Array = [{"name": "Slime", "hp_pct": 100.0}], status: Array = []) -> PartyCombatLineContext:
	var c := PartyCombatLineContext.new()
	c.speaker_name = "Aria"
	c.speaker_job_id = "fighter"
	c.speaker_status = status
	c.party = party
	c.enemies = enemies
	return c


func _m(name: String, job: String, hp: float = 100.0, alive: bool = true) -> Dictionary:
	return {"name": name, "job_id": job, "hp_pct": hp, "is_alive": alive}


func test_a_solo_duel_has_no_cleric_to_call_on() -> void:
	var duel := _ctx([_m("Aria", "fighter")])
	assert_false(VoiceLineTags.tag_holds("ally_alive:cleric", duel),
		"in a spotlight duel the speaker is alone, so a line naming the Cleric must not play")
	assert_false(VoiceLineTags.is_eligible(["ally_alive:cleric"], duel))


func test_ally_alive_needs_the_ally_present_and_standing() -> void:
	var party := _ctx([_m("Aria", "fighter"), _m("Mira", "cleric")])
	assert_true(VoiceLineTags.tag_holds("ally_alive:cleric", party))
	var down := _ctx([_m("Aria", "fighter"), _m("Mira", "cleric", 0.0, false)])
	assert_false(VoiceLineTags.tag_holds("ally_alive:cleric", down), "a KO'd Cleric can't answer")


func test_the_speaker_is_not_their_own_ally() -> void:
	var c := _ctx([_m("Aria", "fighter")])
	assert_false(VoiceLineTags.tag_holds("ally_alive:fighter", c),
		"the speaker's own job must not satisfy an ally tag")


func test_none_down_needs_a_party_and_nobody_down() -> void:
	assert_true(VoiceLineTags.tag_holds("none_down", _ctx([_m("Aria", "fighter"), _m("Mira", "cleric")])))
	assert_false(VoiceLineTags.tag_holds("none_down", _ctx([_m("Aria", "fighter"), _m("Mira", "cleric", 0.0, false)])))
	assert_false(VoiceLineTags.tag_holds("none_down", _ctx([_m("Aria", "fighter")])),
		"'Nobody fell' is about a group; in a solo duel there is no group")


func test_the_remaining_tags() -> void:
	var two := [_m("Aria", "fighter"), _m("Mira", "cleric", 20.0)]
	assert_true(VoiceLineTags.tag_holds("ally_low", _ctx(two)))
	assert_false(VoiceLineTags.tag_holds("ally_down", _ctx(two)))
	assert_true(VoiceLineTags.tag_holds("ally_down", _ctx([_m("Aria", "fighter"), _m("Mira", "cleric", 0.0, false)])))
	assert_true(VoiceLineTags.tag_holds("last_standing", _ctx([_m("Aria", "fighter"), _m("Mira", "cleric", 0.0, false)])))
	assert_false(VoiceLineTags.tag_holds("last_standing", _ctx([_m("Aria", "fighter")])), "alone from the start is not last standing")
	assert_true(VoiceLineTags.tag_holds("enemy_last", _ctx(two, [{"name": "A", "hp_pct": 50.0}, {"name": "B", "hp_pct": 0.0}])))
	assert_true(VoiceLineTags.tag_holds("enemy_nearly_dead", _ctx(two, [{"name": "A", "hp_pct": 12.0}])))
	assert_false(VoiceLineTags.tag_holds("enemy_nearly_dead", _ctx(two, [{"name": "A", "hp_pct": 0.0}])), "a dead enemy is not nearly dead")
	assert_true(VoiceLineTags.tag_holds("many_enemies", _ctx(two, [{"name": "A", "hp_pct": 9.0}, {"name": "B", "hp_pct": 9.0}, {"name": "C", "hp_pct": 9.0}])))
	assert_true(VoiceLineTags.tag_holds("self_status", _ctx(two, [{"name": "A", "hp_pct": 50.0}], ["poison"])))


func test_every_tag_must_hold_and_an_unknown_one_never_does() -> void:
	var c := _ctx([_m("Aria", "fighter"), _m("Mira", "cleric")])
	assert_true(VoiceLineTags.is_eligible([], c), "an untagged line is always eligible")
	assert_true(VoiceLineTags.is_eligible(["ally_alive:cleric", "none_down"], c))
	assert_false(VoiceLineTags.is_eligible(["ally_alive:cleric", "ally_down"], c), "all tags must hold")
	assert_false(VoiceLineTags.is_known_tag("ally_dwon"), "a typo is not a tag")
	assert_false(VoiceLineTags.is_eligible(["ally_dwon"], c), "an unknown tag makes the line ineligible, never silently true")
	assert_true(VoiceLineTags.is_known_tag("ally_alive:bard"))
	assert_false(VoiceLineTags.is_known_tag("ally_alive:"), "a parameterised tag needs its parameter")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `XDG_DATA_HOME=$PWD/tmp/xdg tools/run_tests.sh a_line_naming_an_ally_needs_that_ally`
Expected: EC=3 (`VoiceLineTags` not declared).

- [ ] **Step 3: Create `src/llm/VoiceLineTags.gd`**

```gdscript
class_name VoiceLineTags
extends RefCounted

## Each tag is a pure predicate over PartyCombatLineContext; code decides eligibility, the LLM only chooses among true lines.

const SIMPLE_TAGS: Array[String] = [
	"none_down", "ally_down", "ally_low", "last_standing",
	"enemy_last", "enemy_nearly_dead", "many_enemies", "self_status",
]
const ALLY_ALIVE_PREFIX := "ally_alive:"
const ALLY_LOW_PCT := 30.0
const ENEMY_NEARLY_DEAD_PCT := 20.0


static func is_known_tag(tag: String) -> bool:
	if tag.begins_with(ALLY_ALIVE_PREFIX):
		return tag.length() > ALLY_ALIVE_PREFIX.length()
	return tag in SIMPLE_TAGS


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
```

- [ ] **Step 4: Import and run**

```bash
XDG_DATA_HOME=$PWD/tmp/xdg godot --headless --audio-driver Dummy --import --quit
XDG_DATA_HOME=$PWD/tmp/xdg tools/run_tests.sh a_line_naming_an_ally_needs_that_ally; echo EC=$?
```
Expected: `EC=0`.

- [ ] **Step 5: Mutation check**

Make `others` include the speaker (`var others: Array = ctx.party`); re-run. Expected: EC=1 naming `test_the_speaker_is_not_their_own_ally`. Revert. Remove `ctx.party.size() >= 2 and` from `none_down`; re-run. Expected: EC=1 naming the none_down arm. Revert.

- [ ] **Step 6: Commit**

```bash
git add src/llm/VoiceLineTags.gd test/unit/test_a_line_naming_an_ally_needs_that_ally.gd
git commit -m "feat(llm): a line naming an ally plays only when that ally is there"
```

---

### Task 3: The pick prefers a line written for the moment

**Files:**
- Modify: `src/llm/PartyPersonas.gd` (`pick_trigger_voice`, new `eligible_trigger_entries`)
- Test: `test/unit/test_a_tagged_line_wins_its_moment.gd`

**Interfaces:**
- Consumes: `VoiceLines.entries_of`, `VoiceLines.variant_key`, `VoiceLineTags.is_eligible`, `_pick_no_repeat` (Task 1).
- Produces: `PartyPersonas.eligible_trigger_entries(job_id: String, event_kind: String, ctx: PartyCombatLineContext) -> Array` (the preferred eligible set: tagged-eligible if any, else untagged); `PartyPersonas.pick_trigger_voice(job_id: String, event_kind: String, ctx: PartyCombatLineContext = null) -> Dictionary`.

- [ ] **Step 1: Write the failing test**

`test/unit/test_a_tagged_line_wins_its_moment.gd`:
```gdscript
extends GutTest

## Eligible tagged lines outrank generic ones; with no context, tagged lines are never guessed at.

var _saved_rogue: Dictionary = {}
var _saved_last: Dictionary = {}


func before_each() -> void:
	_saved_rogue = (PartyPersonas._data.get("rogue", {}) as Dictionary).duplicate(true)
	_saved_last = PartyPersonas._last_variant.duplicate()


func after_each() -> void:
	PartyPersonas._data["rogue"] = _saved_rogue
	PartyPersonas._last_variant = _saved_last


func _rogue_says(lines: Variant) -> void:
	var entry: Dictionary = _saved_rogue.duplicate(true)
	var tv: Dictionary = entry.get("trigger_voices", {})
	tv["low_hp"] = lines
	entry["trigger_voices"] = tv
	PartyPersonas._data["rogue"] = entry


func _ctx(party: Array) -> PartyCombatLineContext:
	var c := PartyCombatLineContext.new()
	c.speaker_name = "Vex"
	c.party = party
	c.enemies = [{"name": "Slime", "hp_pct": 100.0}]
	return c


const LINES := ["Generic one.", "Generic two.", {"line": "Cleric, now.", "when": "ally_alive:cleric"}]


func test_in_a_duel_the_ally_line_never_plays() -> void:
	_rogue_says(LINES)
	var duel := _ctx([{"name": "Vex", "job_id": "rogue", "hp_pct": 20.0, "is_alive": true}])
	for i in 80:
		var p: Dictionary = PartyPersonas.pick_trigger_voice("rogue", "low_hp", duel)
		assert_ne(p["line"], "Cleric, now.", "no Cleric in a solo duel, so this line must never play")


func test_when_its_moment_comes_the_tagged_line_wins() -> void:
	_rogue_says(LINES)
	var party := _ctx([{"name": "Vex", "job_id": "rogue", "hp_pct": 20.0, "is_alive": true},
		{"name": "Mira", "job_id": "cleric", "hp_pct": 90.0, "is_alive": true}])
	var p: Dictionary = PartyPersonas.pick_trigger_voice("rogue", "low_hp", party)
	assert_eq(p["line"], "Cleric, now.", "an eligible line written for this moment must outrank the generic ones")
	assert_eq(p["voice_key"], "low_hp_2", "and it keeps its own clip, index 2")


func test_without_context_a_tagged_line_is_not_guessed_at() -> void:
	_rogue_says(LINES)
	for i in 60:
		var p: Dictionary = PartyPersonas.pick_trigger_voice("rogue", "low_hp")
		assert_ne(p["line"], "Cleric, now.", "a caller with no context cannot know the tag holds")


func test_the_eligible_set_is_what_the_llm_chooses_among() -> void:
	_rogue_says(LINES)
	var duel := _ctx([{"name": "Vex", "job_id": "rogue", "hp_pct": 20.0, "is_alive": true}])
	var e: Array = PartyPersonas.eligible_trigger_entries("rogue", "low_hp", duel)
	var texts: Array = e.map(func(x): return x["line"])
	assert_eq(texts, ["Generic one.", "Generic two."], "the LLM must only ever see lines that are true")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `XDG_DATA_HOME=$PWD/tmp/xdg tools/run_tests.sh a_tagged_line_wins_its_moment`
Expected: EC=1 or EC=3 (`pick_trigger_voice` takes 2 args / `eligible_trigger_entries` missing).

- [ ] **Step 3: Implement in `src/llm/PartyPersonas.gd`**

Replace `pick_trigger_voice` (keep `_pick_no_repeat` from Task 1) with:
```gdscript
## The entries to pick among: eligible tagged lines if any hold, else untagged ones; no context means untagged only.
func eligible_trigger_entries(job_id: String, event_kind: String, ctx: PartyCombatLineContext) -> Array:
	var entries: Array = get_trigger_entries(job_id, event_kind)
	var untagged: Array = entries.filter(func(e): return (e["tags"] as Array).is_empty())
	if ctx == null:
		return untagged
	var tagged: Array = entries.filter(func(e): return not (e["tags"] as Array).is_empty() and VoiceLineTags.is_eligible(e["tags"], ctx))
	return tagged if not tagged.is_empty() else untagged


## {"line", "voice_key"}: a random eligible entry, never the same one twice running.
func pick_trigger_voice(job_id: String, event_kind: String, ctx: PartyCombatLineContext = null) -> Dictionary:
	var entries: Array = eligible_trigger_entries(job_id, event_kind, ctx)
	if entries.is_empty():
		return {"line": "", "voice_key": ""}
	var e: Dictionary = _pick_no_repeat(job_id + "|" + event_kind, entries)
	return {"line": str(e["line"]), "voice_key": VoiceLines.variant_key(event_kind, int(e["index"]))}
```

- [ ] **Step 4: Run the new test and Task 1's**

```bash
for t in a_tagged_line_wins_its_moment a_tagged_line_keeps_its_clip a_trigger_can_speak_many_lines; do
  XDG_DATA_HOME=$PWD/tmp/xdg tools/run_tests.sh $t > tmp/t.log 2>&1; echo "$t EC=$?"; done
```
Expected: all `EC=0`.

- [ ] **Step 5: Mutation check**

Change `return tagged if not tagged.is_empty() else untagged` to `return untagged + tagged`; re-run. Expected: EC=1 naming `test_when_its_moment_comes_the_tagged_line_wins`. Revert. Drop the `VoiceLineTags.is_eligible` filter; re-run. Expected: EC=1 naming the duel arm. Revert.

- [ ] **Step 6: Commit**

```bash
git add src/llm/PartyPersonas.gd test/unit/test_a_tagged_line_wins_its_moment.gd
git commit -m "feat(llm): a line written for the moment outranks a generic one"
```

---

### Task 4: `choose()` reads "17" as 17, not 1 and 7

**Files:**
- Modify: `src/llm/LLMService.gd:667-669` (`_guard_choice`, whole-token check)
- Test: `test/unit/test_a_numbered_choice_is_not_read_inside_a_bigger_number.gd`

**Interfaces:**
- Produces: `_guard_choice` treats `a-z` **and `0-9`** as word characters. No signature change.

- [ ] **Step 1: Write the failing test**

`test/unit/test_a_numbered_choice_is_not_read_inside_a_bigger_number.gd`:
```gdscript
extends GutTest

## choose()'s whole-token match counted only letters as word characters, so "17" matched options "1" and "7".


func _labels(n: int) -> Array[String]:
	var out: Array[String] = []
	for i in range(1, n + 1):
		out.append(str(i))
	return out


func test_a_prose_reply_picks_the_whole_number() -> void:
	assert_eq(LLMService._guard_choice("I pick 17.", _labels(20), "1"), "17",
		"'17' must not also match '1' and '7' and fall back")


func test_a_number_past_the_list_is_not_read_as_its_first_digit() -> void:
	assert_eq(LLMService._guard_choice("20", _labels(15), "1"), "1",
		"with 15 options, '20' is invalid and must fall back, not become option 2")


func test_json_and_bare_replies_still_work() -> void:
	assert_eq(LLMService._guard_choice("12", _labels(20), "1"), "12")
	assert_eq(LLMService._guard_choice('{"choice": "10"}', _labels(20), "1"), "10")


func test_word_options_are_unaffected() -> void:
	var opts: Array[String] = ["attack", "defend"]
	assert_eq(LLMService._guard_choice("I will attack now", opts, "defend"), "attack")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `XDG_DATA_HOME=$PWD/tmp/xdg tools/run_tests.sh a_numbered_choice_is_not_read_inside_a_bigger_number`
Expected: EC=1 on the first two arms.

- [ ] **Step 3: Implement**

In `src/llm/LLMService.gd`, replace lines 667 and 669:
```gdscript
			var before_ok: bool = (idx == 0) or not _is_word_char(lower[idx - 1])
			var after_idx: int = idx + pattern.length()
			var after_ok: bool = (after_idx >= lower.length()) or not _is_word_char(lower[after_idx])
```
and add below `_guard_choice`:
```gdscript
## Letters and digits both continue a word, so option "1" is not found inside "17".
static func _is_word_char(ch: String) -> bool:
	var c: int = ch.unicode_at(0)
	return (c >= 97 and c <= 122) or (c >= 48 and c <= 57)
```

- [ ] **Step 4: Run it and the existing choose tests**

```bash
for t in a_numbered_choice_is_not_read_inside_a_bigger_number llm_infra the_choice_json_wrapper_is_actually_reached; do
  XDG_DATA_HOME=$PWD/tmp/xdg tools/run_tests.sh $t > tmp/t.log 2>&1; echo "$t EC=$?"; done
```
Expected: all `EC=0`.

- [ ] **Step 5: Mutation check**

Change `_is_word_char` back to letters only; re-run the new test. Expected: EC=1 on the first two arms. Revert.

- [ ] **Step 6: Commit**

```bash
git add src/llm/LLMService.gd test/unit/test_a_numbered_choice_is_not_read_inside_a_bigger_number.gd
git commit -m "fix(llm): choose() read '17' as options 1 and 7"
```

---

### Task 5: With the LLM on, it chooses a voiced line

**Files:**
- Modify: `src/llm/VoiceLines.gd` (choice labels and mapping)
- Modify: `src/llm/DialoguePrompts.gd` (`build_party_line_choice`)
- Modify: `src/battle/BattleManager.gd:9037-9112` (`_run_party_line_async`)
- Modify: `test/unit/test_party_scripted_fallback_fires_when_llm_off.gd` (source pins, only if a pinned string moves)
- Test: `test/unit/test_the_llm_picks_a_voiced_line.gd`

**Interfaces:**
- Consumes: `PartyPersonas.eligible_trigger_entries`, `PartyPersonas.pick_trigger_voice(job, event, ctx)`, `LLMService.choose(prompt: String, valid_options: Array[String], fallback: String) -> String`.
- Produces: `VoiceLines.choice_labels(n: int) -> Array[String]` (`"1".."n"`), `VoiceLines.entry_for_choice(entries: Array, label: String) -> Dictionary` (`{}` when invalid), `DialoguePrompts.build_party_line_choice(persona: String, signature_phrases: Array, ctx: Dictionary, lines: Array) -> String`.

- [ ] **Step 1: Write the failing test**

`test/unit/test_the_llm_picks_a_voiced_line.gd`:
```gdscript
extends GutTest

## With LLM dialogue on, the LLM chose to WRITE a line that had no clip, so party lines went silent; now it picks a voiced one.

const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"


func _run_async_body() -> String:
	var src: String = FileAccess.get_file_as_string(BATTLE_MANAGER)
	var idx: int = src.find("func _run_party_line_async")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx)


func test_labels_are_numbers_from_one() -> void:
	assert_eq(VoiceLines.choice_labels(3), ["1", "2", "3"] as Array[String])


func test_a_label_maps_back_to_its_entry_and_clip() -> void:
	var entries: Array = [{"index": 0, "line": "a", "tags": []}, {"index": 4, "line": "e", "tags": []}]
	assert_eq(VoiceLines.entry_for_choice(entries, "2")["index"], 4, "label 2 is the second ELIGIBLE entry, index 4")
	assert_true(VoiceLines.entry_for_choice(entries, "3").is_empty(), "an out-of-range label maps to nothing")
	assert_true(VoiceLines.entry_for_choice(entries, "x").is_empty())


func test_the_prompt_numbers_every_line_and_asks_for_a_number() -> void:
	var ctx := {"event_kind": "low_hp", "speaker_name": "Vex", "speaker_job_id": "rogue",
		"speaker_hp_pct": 20.0, "party": [], "enemies": []}
	var p: String = DialoguePrompts.build_party_line_choice("A wry thief.", [], ctx, ["First line.", "Second line."])
	assert_true(p.contains("1. First line."))
	assert_true(p.contains("2. Second line."))
	assert_true(p.contains("Reply with only the number"), "the reply must be a number, which choose() can read exactly")


func test_the_context_is_built_before_the_line_is_picked() -> void:
	var body := _run_async_body()
	var ctx_at: int = body.find("_build_party_line_context(")
	var pick_at: int = body.find("pick_trigger_voice(")
	assert_gt(ctx_at, -1)
	assert_gt(pick_at, -1)
	assert_lt(ctx_at, pick_at, "eligibility needs the context on EVERY branch, including LLM off, so it is built first")
	assert_true(body.contains("pick_trigger_voice(job_id, event_kind, ctx)"), "the pick must be given the context")


func test_the_llm_branch_chooses_among_eligible_lines_and_voices_the_choice() -> void:
	var body := _run_async_body()
	assert_true(body.contains("eligible_trigger_entries(job_id, event_kind, ctx)"))
	assert_true(body.contains("llm.choose("), "the LLM must choose among authored lines")
	assert_true(body.contains("VoiceLines.variant_key(event_kind, int(chosen[\"index\"]))"),
		"the chosen line must be emitted WITH its clip key")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `XDG_DATA_HOME=$PWD/tmp/xdg tools/run_tests.sh the_llm_picks_a_voiced_line`
Expected: EC=1 or EC=3.

- [ ] **Step 3: Add choice helpers to `src/llm/VoiceLines.gd`**

```gdscript
## "1".."n": a small model can answer a number exactly, where it would paraphrase a line.
static func choice_labels(n: int) -> Array[String]:
	var out: Array[String] = []
	for i in range(1, n + 1):
		out.append(str(i))
	return out


## The entry a label names, or {} when the label is not one of them.
static func entry_for_choice(entries: Array, label: String) -> Dictionary:
	if not label.is_valid_int():
		return {}
	var i: int = int(label) - 1
	return entries[i] if i >= 0 and i < entries.size() else {}
```

- [ ] **Step 4: Add `build_party_line_choice` to `src/llm/DialoguePrompts.gd`** (after `build_party_line`)

```gdscript
## The LLM picks which authored line fits; every option is already true, so it only judges fit.
static func build_party_line_choice(persona: String, signature_phrases: Array, ctx: Dictionary, lines: Array) -> String:
	var speaker: String = str(ctx.get("speaker_name", "the character"))
	var job: String = str(ctx.get("speaker_job_id", ""))
	var event: String = str(ctx.get("event_kind", "turn_start")).replace("_", " ")
	var out: String = "You are choosing a combat line for %s, the %s.\n" % [speaker, job]
	out += "Persona: %s\n" % persona
	if not signature_phrases.is_empty():
		out += "Signature phrases: %s\n" % ", ".join(PackedStringArray(signature_phrases.map(func(s): return str(s))))
	out += "Moment: %s. %s is at %d%% HP.\n" % [event, speaker, int(float(ctx.get("speaker_hp_pct", 100.0)))]
	var party: Array = ctx.get("party", [])
	if not party.is_empty():
		out += "Party: %s\n" % ", ".join(PackedStringArray(party.map(func(m): return "%s (%s, %s)" % [m.get("name", "?"), m.get("job_id", "?"), "up" if m.get("is_alive", true) else "down"])))
	var enemies: Array = ctx.get("enemies", [])
	if not enemies.is_empty():
		out += "Enemies: %s\n" % ", ".join(PackedStringArray(enemies.map(func(e): return str(e.get("name", "?")))))
	out += "\nPick the ONE line below this character would say right now:\n"
	for i in lines.size():
		out += "%d. %s\n" % [i + 1, str(lines[i])]
	out += "\nReply with only the number."
	return out
```

- [ ] **Step 5: Rewire `_run_party_line_async` in `src/battle/BattleManager.gd`**

Replace the head of the function (from `var pp = get_node_or_null("/root/PartyPersonas")` through the `elif pp != null and pp.has_method("get_trigger_voice"):` block) with:
```gdscript
	var pp = get_node_or_null("/root/PartyPersonas")
	var job_id: String = _resolve_party_job_id(combatant)
	## Built first: tag eligibility needs it on every branch, LLM off included.
	var ctx := _build_party_line_context(combatant, event_kind, event_data)
	var fallback: String = ""
	var fallback_key: String = event_kind
	if pp != null and pp.has_method("pick_trigger_voice"):
		var picked: Dictionary = pp.pick_trigger_voice(job_id, event_kind, ctx)
		fallback = str(picked.get("line", ""))
		fallback_key = str(picked.get("voice_key", event_kind))
	elif pp != null and pp.has_method("get_trigger_voice"):
		fallback = str(pp.get_trigger_voice(job_id, event_kind))
```
Delete the later `var ctx := _build_party_line_context(combatant, event_kind, event_data)` line (keep its `if ctx == null:` guard). Then, immediately after the `if persona.is_empty():` block and before `var DialoguePromptsScript = load(...)`, insert:
```gdscript
	## Authored lines exist: the LLM chooses among the eligible ones, so the line stays voiced.
	var options: Array = pp.eligible_trigger_entries(job_id, event_kind, ctx) if pp != null and pp.has_method("eligible_trigger_entries") else []
	if not options.is_empty():
		var labels: Array[String] = VoiceLines.choice_labels(options.size())
		var fb_label: String = "1"
		for i in options.size():
			if VoiceLines.variant_key(event_kind, int(options[i]["index"])) == fallback_key:
				fb_label = labels[i]
		var choice_prompt: String = DialoguePrompts.build_party_line_choice(persona, sig, ctx.to_dict(), options.map(func(e): return e["line"]))
		var label: String = await llm.choose(choice_prompt, labels, fb_label)
		if not is_instance_valid(combatant) or not combatant.is_alive:
			return
		var chosen: Dictionary = VoiceLines.entry_for_choice(options, label)
		if chosen.is_empty():
			chosen = VoiceLines.entry_for_choice(options, fb_label)
		_emit_party_line(combatant, str(chosen["line"]), VoiceLines.variant_key(event_kind, int(chosen["index"])))
		return
```
The existing `complete_json` free-form path below it now runs only when a trigger has no authored lines.

- [ ] **Step 6: Run the new test plus every party-line test**

```bash
for t in the_llm_picks_a_voiced_line party_scripted_fallback_fires_when_llm_off party_llm_dialogue_regression \
  a_trigger_can_speak_many_lines party_line_skipped_when_pc_dies_during_await battle_speech_bubble_regression \
  a_tagged_line_wins_its_moment a_tagged_line_keeps_its_clip; do
  XDG_DATA_HOME=$PWD/tmp/xdg tools/run_tests.sh $t > tmp/t.log 2>&1; echo "$t EC=$?"; done
```
Expected: all `EC=0`. If a source pin in `test_party_scripted_fallback_fires_when_llm_off.gd` or `test_party_llm_dialogue_regression.gd` reds because a pinned string moved, **read what the pin defends** and update it to the new equivalent string only if the behaviour it defends is unchanged (the LLM-off branch still emits the scripted fallback before any LLM check). Record each pin changed in the commit message.

- [ ] **Step 7: Mutation check**

Emit `str(chosen["line"])` with `""` as the voice key; re-run `the_llm_picks_a_voiced_line`. Expected: EC=1 naming the voicing arm. Revert. Move the `_build_party_line_context` line back below the pick; re-run. Expected: EC=1 naming the ordering arm. Revert.

- [ ] **Step 8: Commit**

```bash
git add src/llm/VoiceLines.gd src/llm/DialoguePrompts.gd src/battle/BattleManager.gd test/unit/test_the_llm_picks_a_voiced_line.gd
git commit -m "feat(llm): with LLM dialogue on, the party speaks a voiced line it chose"
```

---

### Task 6: Every tag in the data is one the picker knows

**Files:**
- Test: `test/unit/test_every_voice_line_tag_is_one_the_picker_knows.gd`

**Interfaces:**
- Consumes: `VoiceLines.tags_of`, `VoiceLineTags.is_known_tag`.

- [ ] **Step 1: Write the test**

`test/unit/test_every_voice_line_tag_is_one_the_picker_knows.gd`:
```gdscript
extends GutTest

## An unknown tag makes its line ineligible forever, silently; a typo in the data must red here instead.


func test_every_tag_in_job_personas_is_known() -> void:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/job_personas.json"))
	assert_true(d is Dictionary and (d as Dictionary).has("jobs"), "job_personas.json did not parse")
	var entries := 0
	var tagged := 0
	var unknown: Array[String] = []
	for job in (d["jobs"] as Dictionary).keys():
		var tv: Variant = d["jobs"][job].get("trigger_voices", {})
		if not (tv is Dictionary):
			continue
		for trig in (tv as Dictionary).keys():
			var raw: Variant = tv[trig]
			for el in (raw if raw is Array else [raw]):
				entries += 1
				var tags: Array[String] = VoiceLines.tags_of(el)
				if not tags.is_empty():
					tagged += 1
				for t in tags:
					if not VoiceLineTags.is_known_tag(t):
						unknown.append("%s/%s: %s" % [job, trig, t])
	gut.p("corpus: %d entries, %d tagged" % [entries, tagged])
	assert_gt(entries, 0, "VOID: no trigger_voices entries were read, so nothing was checked")
	assert_eq(unknown, [] as Array[String], "unknown tags make their lines unplayable: %s" % [unknown])
```

- [ ] **Step 2: Run it**

Run: `XDG_DATA_HOME=$PWD/tmp/xdg tools/run_tests.sh every_voice_line_tag_is_one_the_picker_knows; echo EC=$?`
Expected: `EC=0`, and the log prints the corpus count.

- [ ] **Step 3: Mutation check**

Temporarily add `{"line": "x", "when": "ally_dwon"}` to one list in `data/job_personas.json`; re-run. Expected: EC=1 naming the typo. `git checkout data/job_personas.json` to revert.

- [ ] **Step 4: Commit**

```bash
git add test/unit/test_every_voice_line_tag_is_one_the_picker_knows.gd
git commit -m "test(llm): an unknown voice-line tag reds instead of muting its line"
```

---

## Handoff after Task 6

- Push `llm/voice-line-eligibility`; tell cowir-main it is ready to fold (list the test files added).
- Tell cowir-story the picker and all readers accept object entries, so the 17 waiting lines can be tagged. Note `none_down` requires a party of two or more, which is what "Nobody fell" means.
