extends GutTest

## tick 161 regression: Combatant.from_dict must apply the same
## constraints to recent_abilities and pinned_abilities that the
## add_to_mru helper enforces at write time:
##
##   1. recent_abilities capped at MRU_SIZE (2). A corrupted save
##      with 99 entries propagates to the quick-slot menu, which
##      only has 2 rendering slots — overflow silently visible in
##      data access (size() comparisons, equality checks).
##
##   2. recent_abilities filters pinned-overlap. add_to_mru's
##      line 314 guard: "Pinned abilities don't pollute the MRU
##      list." A corrupted save with the same ability in both
##      lists would render it twice in the menu.
##
##   3. Both lists dedupe + filter empty strings.

const COMBATANT := "res://src/battle/Combatant.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Source pins ──────────────────────────────────────────────────────────

func test_pinned_abilities_load_dedupes() -> void:
	var src := _read(COMBATANT)
	var idx: int = src.find("if data.has(\"pinned_abilities\"):")
	assert_gt(idx, -1, "pinned_abilities load branch must exist")
	var window: String = src.substr(idx, 800)
	assert_true(window.contains("var seen_pinned: Dictionary = {}"),
		"pinned_abilities load must build a seen dict for dedupe")
	assert_true(window.contains("pinned_abilities = typed_pinned"),
		"pinned_abilities load must assign the typed result back")


func test_recent_abilities_load_enforces_mru_size() -> void:
	var src := _read(COMBATANT)
	var idx: int = src.find("if data.has(\"recent_abilities\"):")
	assert_gt(idx, -1, "recent_abilities load branch must exist")
	var window: String = src.substr(idx, 1200)
	assert_true(window.contains("if typed_recent.size() >= MRU_SIZE:"),
		"recent_abilities load must enforce MRU_SIZE cap")
	assert_true(window.contains("break"),
		"cap branch must break, not continue (early exit cleanly)")


func test_recent_abilities_load_dedupes_and_filters_pinned() -> void:
	var src := _read(COMBATANT)
	var idx: int = src.find("if data.has(\"recent_abilities\"):")
	var window: String = src.substr(idx, 1200)
	assert_true(window.contains("var seen_recent: Dictionary = {}"),
		"recent_abilities load must have its own seen dict")
	assert_true(window.contains("var pinned_set: Dictionary = {}"),
		"recent_abilities load must build a pinned_set for overlap filtering")
	# The skip condition includes pinned_set.has(sid).
	assert_true(window.contains("seen_recent.has(sid) or pinned_set.has(sid)"),
		"recent_abilities load must skip both duplicates AND pinned-overlap entries")


func test_recent_branch_runs_AFTER_pinned_branch() -> void:
	# Critical ordering: pinned must be loaded BEFORE recent so the
	# pinned_set lookup uses the freshly-loaded pinned array.
	var src := _read(COMBATANT)
	var pinned_idx: int = src.find("if data.has(\"pinned_abilities\"):")
	var recent_idx: int = src.find("if data.has(\"recent_abilities\"):")
	assert_gt(pinned_idx, -1)
	assert_gt(recent_idx, -1)
	assert_lt(pinned_idx, recent_idx,
		"pinned_abilities must be loaded BEFORE recent_abilities — else pinned_set is empty when recent dedupes")


# ── Runtime behavior ────────────────────────────────────────────────────

func test_runtime_99_recent_caps_at_mru_size() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	# MRU_SIZE = 2.
	var oversized: Array = []
	for i in 99:
		oversized.append("ability_%d" % i)
	c.from_dict({"recent_abilities": oversized})
	assert_eq(c.recent_abilities.size(), 2,
		"99 recent abilities must cap at MRU_SIZE=2")
	# Keep-first-N: oldest entries preserved.
	assert_eq(c.recent_abilities[0], "ability_0")
	assert_eq(c.recent_abilities[1], "ability_1")


func test_runtime_recent_filters_pinned_overlap() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({
		"pinned_abilities": ["fire", "cure"],
		"recent_abilities": ["fire", "thunder", "cure", "ice"],  # fire+cure overlap pins
	})
	assert_eq(c.pinned_abilities.size(), 2,
		"pinned passes through")
	# recent filters fire+cure (in pinned) and caps at MRU_SIZE=2.
	# After filter: [thunder, ice]. Caps at 2 — both fit.
	assert_eq(c.recent_abilities.size(), 2,
		"recent after pinned-overlap filter caps at MRU_SIZE")
	assert_false(c.recent_abilities.has("fire"),
		"fire must be filtered from recent (already pinned)")
	assert_false(c.recent_abilities.has("cure"),
		"cure must be filtered from recent (already pinned)")
	assert_true(c.recent_abilities.has("thunder"),
		"thunder kept (not pinned)")
	assert_true(c.recent_abilities.has("ice"),
		"ice kept (not pinned)")


func test_runtime_recent_dedupes_within_list() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({"recent_abilities": ["fire", "fire", "thunder", "fire", "thunder"]})
	assert_eq(c.recent_abilities.size(), 2,
		"5 entries with 2 unique cap at MRU_SIZE=2 after dedupe")
	assert_eq(c.recent_abilities[0], "fire")
	assert_eq(c.recent_abilities[1], "thunder")


func test_runtime_pinned_dedupes() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({"pinned_abilities": ["fire", "fire", "cure", "fire"]})
	assert_eq(c.pinned_abilities.size(), 2,
		"pinned dedupes — fire only once")


func test_runtime_pinned_no_size_cap() -> void:
	# Pinned has no documented cap. Don't accidentally cap it.
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	var many: Array = []
	for i in 30:
		many.append("ability_%d" % i)
	c.from_dict({"pinned_abilities": many})
	assert_eq(c.pinned_abilities.size(), 30,
		"pinned has NO size cap — player can pin many abilities")


func test_runtime_empty_strings_filtered() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({
		"pinned_abilities": ["", "fire", "", "cure"],
		"recent_abilities": ["", "thunder", "", "ice"],
	})
	assert_eq(c.pinned_abilities.size(), 2,
		"empty strings filtered from pinned")
	assert_eq(c.recent_abilities.size(), 2,
		"empty strings filtered from recent")


# ── Non-regression ──────────────────────────────────────────────────────

func test_runtime_normal_load_passes_through() -> void:
	var CombatantScript = load(COMBATANT)
	var c = CombatantScript.new()
	add_child_autofree(c)
	c.from_dict({
		"pinned_abilities": ["fire", "cure"],
		"recent_abilities": ["thunder", "ice"],
	})
	assert_eq(c.pinned_abilities, ["fire", "cure"])
	assert_eq(c.recent_abilities, ["thunder", "ice"])
