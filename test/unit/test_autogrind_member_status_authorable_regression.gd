extends GutTest

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

## Whole-surface autoload restore — this file left autoload state for every later file.
var _ag_state: Dictionary

const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## member_status could not be authored in the console, so a console-made rule could never fire.
##
## The evaluator reads the status NAME from `value` — AutogrindSystem:1912, and the LLM grammar
## says so explicitly ("member_status takes the status name in value"). The console's type table
## declared it has_value: false with default_value 0, and there was no picker: member and ability
## have cycling rings, status had none. So a rule authored in the console asked has_status("0")
## and was permanently false, while its own display arm rendered value as a status name.
##
## Found by censusing the 19 party conditions after the six actions (fd8b794f). Same shape as
## member_ability's target one hour earlier and the same shape as the frozen turn counter: the
## authoring path cannot produce what the evaluator needs, and nothing between them disagrees
## loudly enough to notice.

const UI := "res://src/ui/autogrind/AutogrindUI.gd"
const BATTLE_SCENE := "res://src/battle/BattleScene.gd"


func _ui() -> Node:
	var u = load(UI).new()
	add_child_autofree(u)
	return u


func _member(cname: String, job_id: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": cname, "max_hp": 1000, "max_mp": 100,
		"attack": 20, "defense": 20, "magic": 20, "speed": 20})
	c.job = JobSystem.get_job(job_id)
	add_child_autofree(c)
	return c


func before_each() -> void:
	_ag_state = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true


func test_every_offered_status_is_one_the_game_can_actually_show() -> void:
	## Derived guard rather than a restated list: the ring must be a subset of the statuses
	## BattleScene has icons for, so it can never offer something the player cannot even see on
	## their party.
	var displayable: Dictionary = load(BATTLE_SCENE).STATUS_ICON_CONFIG
	assert_gt(displayable.size(), 0, "control: the icon config must be readable, or this proves nothing")
	var ring: Array = load(UI).MEMBER_STATUS_RING
	assert_gt(ring.size(), 0, "control: the ring must be non-empty")
	var undisplayable: Array = []
	for st in ring:
		if not displayable.has(str(st)):
			undisplayable.append(str(st))
	assert_eq(undisplayable.size(), 0,
		"the status ring offers statuses the game has no icon for: %s" % str(undisplayable))


func test_a_freshly_typed_member_status_condition_is_not_numeric() -> void:
	## default_value 0 is what made the condition dead on creation — has_status("0") is false for
	## every character forever.
	## ⚠️ THE FACT MOVED, THE QUESTION DID NOT. The seeded defaults lived in the console's
	## CONDITION_TYPES until 2026-09-17; they are now AutogrindSystem.CONDITION_DEFAULTS, because the
	## grid editor could not reach the console's copy and grew its own with six of nine operators
	## wrong. This arm follows the owner rather than the file it used to sit in — asking the console
	## for a default it no longer authors would pass on a `.get(…, 0)` fallback, which is the exact
	## numeric seed the arm exists to forbid.
	assert_true(AutogrindSystem.PARTY_CONDITION_TYPES.has("member_status"),
		"control: member_status must still be a condition type the grammar knows")
	var dv = AutogrindSystem.condition_defaults_for("member_status").get("value", 0)
	assert_eq(typeof(dv), TYPE_STRING,
		"a member_status condition seeded with a NUMBER asks has_status('0') and can never fire")
	assert_true(load(UI).MEMBER_STATUS_RING.has(str(dv)),
		"the seeded default must be a status the ring can cycle from, or the first press jumps")


func test_cycling_the_status_writes_a_name_the_evaluator_can_use() -> void:
	var u := _ui()
	u.rules = [{
		"conditions": [{"type": "member_status", "member": "cleric", "value": "poison"}],
		"actions": [{"type": "stop_grinding"}], "enabled": true,
	}]
	u.cursor_row = 0
	var before: String = str(u.rules[0]["conditions"][0]["value"])
	u._cycle_status_on_cursor_cell()
	var after: String = str(u.rules[0]["conditions"][0]["value"])
	assert_ne(after, before, "cycling must change the status")
	assert_true(load(UI).MEMBER_STATUS_RING.has(after),
		"cycling must land on a ring entry, not an arbitrary value: %s" % after)


func test_a_console_authored_status_rule_fires_when_the_member_has_it() -> void:
	## End-to-end against the real evaluator: the console's own default, evaluated by
	## AutogrindSystem, must discriminate between an afflicted member and a healthy one.
	var cleric := _member("Status Cleric", "cleric")
	var mage := _member("Status Mage", "mage")
	var party: Array = [cleric, mage]

	## From the owner — see the note in the arm above; the console no longer authors this.
	var seeded := str(AutogrindSystem.condition_defaults_for("member_status").get("value", ""))
	## The expectation is DERIVED from the table, so it would move with a mutation of that table —
	## add_status("0") / has_status("0") round-trips happily and this test would pass while the
	## condition was dead in practice. Pin the value's shape here as well.
	assert_eq(typeof(seeded), TYPE_STRING, "precondition: the seeded default is a status NAME")
	assert_true(load(UI).MEMBER_STATUS_RING.has(seeded),
		"precondition: the seeded default is a real affliction, not any string that round-trips")
	var cond := {"type": "member_status", "member": "cleric", "value": seeded}

	assert_false(AutogrindSystem._evaluate_party_condition(party, cond),
		"control: a healthy party must NOT satisfy the condition, or the assertion below is meaningless")
	cleric.add_status(seeded, 3)
	assert_true(cleric.has_status(seeded), "precondition: the status actually landed on the member")
	assert_true(AutogrindSystem._evaluate_party_condition(party, cond),
		"the console's own seeded rule must fire once the named member has that status")


func test_the_ring_row_is_offered_so_the_control_is_reachable() -> void:
	## A cycler nothing can call is the same defect one layer up.
	var u := _ui()
	u.rules = [{
		"conditions": [{"type": "member_status", "member": "cleric", "value": "poison"}],
		"actions": [{"type": "stop_grinding"}], "enabled": true,
	}]
	u.cursor_row = 0
	var ids: Array = []
	for opt in u._options_ring_spec().get("options", []):
		ids.append(str((opt as Dictionary).get("id", "")))
	assert_true(ids.has("cycle_status"),
		"the OPTIONS ring must offer the status cycler, or it is unreachable on a pad")


## FLOOR. A renamed member on the AutogrindSystem autoload does not fail — it ABORTS the arm at
## runtime, and GUT scores that Passing when the abort lands after the last assert (rung 3),
## which `.366`'s exit 4 cannot reach. `get()` / `has_method()` ANSWER rather than raise.
## ⚠️ Generated by scanning this file, and the first generation produced a key `"gd"` — the
## pattern matched `AutogrindSystem.gd` inside a res:// PATH LITERAL. Lines carrying a path are
## excluded now; a regex reading source cannot tell a member reach from a filename by shape.
## ⚠️ THIS LIST IS A SNAPSHOT, NOT A DERIVATION, and that is the live limit. It was derived once by
## a script from this file's own `_res.` / AutogrindSystem reaches and then written as literals — so
## a member reached by a NEW arm added later is not covered, and the list goes quietly incomplete
## rather than loudly wrong. @cowir-cutscenes' rule puts it on the wrong side of the line: a figure
## the guard's claim DEPENDS on should be derived, and this is one.
## Deliberately not converted to a runtime derivation, per @cowir-sfx's reasoning: doing that needs
## @cowir-ai's bare-Object exclusion, because a runtime scan of this file would collect the `get` and
## `has_method` calls THIS ARM ITSELF makes and pin the mechanism it is written in. That is a real
## defence against a real hazard, and writing it tonight would be shipping it untested. Correct as of
## 2026-09-16; if you add an arm that reaches a new member, add it here or derive the set properly.
const _FLOOR_ARM_NAME := "test_every_autogrind_member_this_file_reaches_still_exists"
## ⚠️ GREW on 2026-09-17 when the seeded defaults moved from the console's CONDITION_TYPES to
## AutogrindSystem.CONDITION_DEFAULTS: this file now asks the SYSTEM for the default it used to read
## off the UI table, so it reaches two more members. The floor red rather than letting the new
## reaches go uncovered, which is the whole point of deriving it from the file's own source.
const _PINNED_MEMBERS := ["_evaluate_party_condition", "PARTY_CONDITION_TYPES", "condition_defaults_for"]

func test_every_autogrind_member_this_file_reaches_still_exists() -> void:
	## @cowir-ai's counter to the snapshot limit above, and it converts the failure mode rather than
	## documenting it: a static list fails toward INCOMPLETENESS — add a reach tomorrow and the floor
	## silently covers all-but-one. This counts the distinct members reached in the text BEFORE this
	## function, so the arm cannot count its own `get`/`has_method` calls — @cowir-ai's bare-Object
	## exclusion replaced by SCOPING, which they named as the alternative. A new reach reds here.
	## ⛔ THE SHARED STRIPPER, not a tenth private one. My first version split each line on "#" —
	## adding another inline comment-strip on the day this fleet counted EIGHTEEN redundant
	## private ones (@cowir-music, who used gd_source rather than writing a sixth). It is
	## quote-aware and escape-aware, which a split on "#" is not: a `#` inside a string
	## literal truncates the line and can hide a real reach.
	var own_src: String = GdSource.code_of(get_script().resource_path)
	var cut: int = own_src.find("func %s(" % _FLOOR_ARM_NAME)
	assert_gt(cut, 0, "CONTROL: located this arm, so the scoped slice is real")
	var before: String = own_src.substr(0, cut)
	var reached: Dictionary = {}
	## ⛔ SKIP PATH LITERALS. `AutogrindSystem.gd` inside a res:// string matched as a member named
	## "gd" — the same false positive fixed in the generator and reintroduced here.
	for raw_line in before.split("\n"):
		if raw_line.contains("res://"):
			continue
		## ⛔ TRAILING COMMENTS TOO, per @cowir-sprites: a floor exists to catch a RENAME, and the commit
		## that renames a member is the one whose prose explains the rename BY NAME. `_res.foo()  #
		## renamed from _res.bar` would inflate this count and red a CORRECT file. Leading-## lines were
		## already skipped; this drops the trailing half. Measured 2026-09-16: strict and lenient
		## extraction agree on all ten floored files, so this is latent rather than a live repair.
		## NOT stripped: a member named inside a triple-quoted block. Measured absent in these files,
		## and recorded rather than handled — a quote-aware stripper here would be its own hazard.
		for m in RegEx.create_from_string("(?:_res|AutogrindSystem)\\.([A-Za-z_][A-Za-z_0-9]*)").search_all(raw_line):
			reached[m.get_string(1)] = true
	reached.erase("_test_disable_persistence")
	reached.erase("PER_BATTLE_METAS")   ## read from SOURCE on purpose — see the arm above
	## ⛔ SETS, NOT SIZES. This compared COUNTS until 2026-09-16, and @cowir-cutscenes' completeness
	## finding is why that is not enough: pin {A,B,X} where X exists but is never reached, while the
	## file reaches {A,B,C}, and the existence arm passes (all three exist) AND the count passes
	## (3 == 3) — with C unpinned and X spurious. Equal cardinality is not equal membership, and an
	## over-count is the same defect as an under-count in a louder coat.
	var pinned: Dictionary = {}
	for x in _PINNED_MEMBERS:
		pinned[x] = true
	assert_gt(reached.size(), 0, "CONTROL: the scan found reaches, or this comparison proves nothing")
	var unpinned: Array = []
	for k in reached:
		if not pinned.has(k):
			unpinned.append(k)
	var spurious: Array = []
	for k in pinned:
		if not reached.has(k):
			spurious.append(k)
	gut.p("    reaches: %d | pinned: %d | unpinned: %s | spurious: %s" % [reached.size(), pinned.size(), str(unpinned), str(spurious)])
	assert_eq(unpinned, [], "this file reaches members the floor does not pin — the list is a snapshot: %s" % str(unpinned))
	assert_eq(spurious, [], "the floor pins members this file no longer reaches — stale entries: %s" % str(spurious))

	var missing: Array = []
	if not AutogrindSystem.has_method("_evaluate_party_condition"): missing.append("_evaluate_party_condition()")
	assert_eq(missing, [],
		"AutogrindSystem no longer has these, so the arms above would ABORT into a silent pass: %s" % str(missing))


func after_each() -> void:
	AutogrindState.restore(_ag_state)
