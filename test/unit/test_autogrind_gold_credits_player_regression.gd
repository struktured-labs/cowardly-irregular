extends GutTest

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

## Whole-surface autoload restore — this file leaked state a hand-listed teardown cannot name.
var _ag_state: Dictionary

const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## tick 342: autogrind battles now credit the player's actual gold
## pool. Pre-fix the entire autogrind pipeline DROPPED gold:
##
##   - HeadlessBattleResolver computed gold (line ~748) and returned
##     it in result["gold_gained"].
##   - GameLoop._resolve_headless_battle IGNORED result["gold_gained"]
##     and called controller.on_battle_ended(..., {}) — empty
##     items_gained dict.
##   - GameLoop._on_autogrind_battle_ended (live path) used items_gained
##     = {} and never computed gold from the live BattleManager.enemy_party.
##   - AutogrindSystem.on_battle_victory tracked total_gold via
##     items_gained.get("gold", 0) — got 0 from the empty dict.
##   - GameState.party_gold NEVER moved.
##
## Symptom: "I autogrind for 30 minutes and the gold counter says I
## earned 5000 G, but my actual party gold didn't change at all."
## The grind_stats display showed 0 because items_gained was empty.
## Both numbers were wrong but the player only saw the second one
## change (it didn't).
##
## Fix has 3 parts:
##   1. Live autogrind path computes gold from enemies + applies
##      gold_multiplier + forwards via items_gained["gold"].
##   2. Headless autogrind path forwards result["gold_gained"] via
##      items_gained["gold"].
##   3. AutogrindSystem.on_battle_victory updates GameState.party_gold
##      directly (bypassing add_gold so the gold_multiplier doesn't
##      apply twice — already applied upstream).

const GAME_LOOP_PATH := "res://src/GameLoop.gd"
const AUTOGRIND_SYSTEM_PATH := "res://src/autogrind/AutogrindSystem.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: live autogrind path computes + forwards gold ────────

func before_each() -> void:
	_ag_state = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true


func test_live_path_computes_gold() -> void:
	var src := _read(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func _on_autogrind_battle_ended")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("gold_gained_live"),
		"live autogrind path must compute gold_gained_live from enemy_party")
	assert_true(body.contains("items_gained[\"gold\"]"),
		"live autogrind path must forward gold via items_gained['gold']")
	assert_true(body.contains("gold_multiplier"),
		"live autogrind gold formula must apply gold_multiplier")


# ── Source pin: headless path forwards gold_gained ──────────────────

func test_headless_path_forwards_gold() -> void:
	var src := _read(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func _resolve_headless_battle")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("result.get(\"gold_gained\""),
		"headless path must pick up result.gold_gained")
	assert_true(body.contains("{\"gold\": gold_gained_headless}"),
		"headless path must forward gold via items_gained dict to on_battle_ended")


# ── Source pin: AutogrindSystem credits party_gold ──────────────────

func test_autogrind_system_credits_party_gold() -> void:
	var src := _read(AUTOGRIND_SYSTEM_PATH)
	var fn_idx: int = src.find("func on_battle_victory")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("party_gold"),
		"on_battle_victory must credit GameState.party_gold (was display-only pre-fix)")
	assert_true(body.contains("gs.party_gold += scaled_gold"),
		"must add scaled_gold to party_gold directly (skip add_gold to avoid double-multiply)")


# ── Behavioral: end-to-end gold flow updates party_gold ─────────────

func test_on_battle_victory_updates_party_gold() -> void:
	assert_not_null(GameState, "GameState autoload required")
	assert_not_null(AutogrindSystem, "AutogrindSystem autoload required")
	if GameState == null or AutogrindSystem == null:
		return

	# Snapshot and reset.
	var prior_gold: int = GameState.party_gold
	GameState.party_gold = 100
	AutogrindSystem._grind_stats["total_gold"] = 0
	# Provide a non-zero reward_scale by setting current_region_id empty
	# (yield_mult defaults to 1.0) and clearing crack penalty cache.
	AutogrindSystem.current_region_id = ""
	# Need a non-empty grind_party so the function doesn't early-return.
	# It iterates members for gain_job_exp — empty party is fine for the
	# gold-credit assertion path.
	AutogrindSystem.grind_party = []

	# Drive: pass items_gained with a known gold amount.
	AutogrindSystem.on_battle_victory(0, {"gold": 50})

	# party_gold should have increased by ~50 * reward_scale * 1.0.
	# (reward_scale = 1.0 since yield_mult=1.0 and crack_penalty=0)
	assert_eq(GameState.party_gold, 150,
		"party_gold must have increased by the gold amount (50) — pre-fix it stayed at 100 because the gold-credit path didn't exist")

	# Cleanup.
	GameState.party_gold = prior_gold
	AutogrindSystem._grind_stats["total_gold"] = 0


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
const _PINNED_MEMBERS := ["_grind_stats", "current_region_id", "grind_party", "on_battle_victory"]

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
	if AutogrindSystem.get("_grind_stats") == null: missing.append("_grind_stats")
	if AutogrindSystem.get("current_region_id") == null: missing.append("current_region_id")
	if AutogrindSystem.get("grind_party") == null: missing.append("grind_party")
	if not AutogrindSystem.has_method("on_battle_victory"): missing.append("on_battle_victory()")
	assert_eq(missing, [],
		"AutogrindSystem no longer has these, so the arms above would ABORT into a silent pass: %s" % str(missing))


func after_each() -> void:
	AutogrindState.restore(_ag_state)
