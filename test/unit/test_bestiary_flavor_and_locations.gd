extends GutTest

## tick 193: two fixes in one tick.
##
## BUG: BestiaryMenu._refresh_detail never assigned _detail_flavor.text
## in the positive path. The flavor field — the WHOLE POINT of the
## bottom panel — was silently empty for every entry. Class docstring
## says "Right pane: idle sprite + stats + flavor text" but flavor
## never rendered. A real regression that source review missed.
##
## FEATURE: Location hint for completionists. The bestiary shows
## "Found in: Cave Floor 1, Overworld Plains" so players who've
## seen a monster but want to re-encounter it know where to grind.
## Backed by a new BestiarySystem.get_pools_for_monster() helper
## that walks data/enemy_pools.json and prettifies pool ids via
## a proper _titlecase (not String.capitalize() which only does
## the first letter — see tick 186).

const BESTIARY_SYSTEM := "res://src/bestiary/BestiarySystem.gd"
const BESTIARY_MENU := "res://src/ui/BestiaryMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── BUG fix: flavor text now actually gets set ─────────────────────────

func test_flavor_text_is_assigned_in_positive_path() -> void:
	# Pin: _detail_flavor.text is set with non-trivial content in the
	# positive path of _refresh_detail. Pre-fix the only assignment was
	# in the early-return clear block.
	var src := _read(BESTIARY_MENU)
	var fn_idx: int = src.find("func _refresh_detail")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	# Body must assign _detail_flavor.text to something derived from
	# blocks (the new builder).
	assert_true(body.contains("_detail_flavor.text = \"\\n\\n\".join(blocks)"),
		"_refresh_detail must assign _detail_flavor.text using the blocks builder")


func test_flavor_extracted_from_entry() -> void:
	var src := _read(BESTIARY_MENU)
	var fn_idx: int = src.find("func _refresh_detail")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	# Pin: flavor is pulled from entry (BestiarySystem already populates this).
	assert_true(body.contains("var flavor: String = str(entry.get(\"flavor\", \"\"))"),
		"_refresh_detail must read entry.flavor (populated by get_seen_entries_sorted)")


# ── FEATURE: location hint ─────────────────────────────────────────────

func test_pools_prefix_assembly() -> void:
	var src := _read(BESTIARY_MENU)
	var fn_idx: int = src.find("func _refresh_detail")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	# Pin: pools array extracted, joined into "Found in: A, B, C"
	assert_true(body.contains("var pools: Array = entry.get(\"pools\", [])"),
		"_refresh_detail must pull pools from entry")
	assert_true(body.contains("\"Found in: %s\" % \", \".join(PackedStringArray(pools))"),
		"location line must format as 'Found in: A, B, C'")


func test_empty_blocks_yields_empty_text() -> void:
	# Negative pin: if both pools and flavor are empty (e.g., custom
	# Scriptweaver enemy not in any pool, no bestiary entry), the
	# join produces "" — no broken "Found in: " header.
	var src := _read(BESTIARY_MENU)
	var fn_idx: int = src.find("func _refresh_detail")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	# Pin both guards: pools.size() > 0 and flavor != "" must each gate.
	assert_true(body.contains("if pools.size() > 0:"),
		"pools must be guarded so empty arrays don't render 'Found in: '")
	assert_true(body.contains("if flavor != \"\":"),
		"flavor must be guarded so empty string doesn't add a blank block")


# ── BestiarySystem helpers ─────────────────────────────────────────────

func test_titlecase_helper_proper_case() -> void:
	# Pin: _titlecase produces proper title case across multiple words,
	# not String.capitalize()'s first-letter-only behavior.
	# (Calling via class-level access — static method.)
	var BS = load(BESTIARY_SYSTEM)
	assert_eq(BS._titlecase("cave_floor_1"), "Cave Floor 1",
		"snake_case 3 parts → proper title case")
	assert_eq(BS._titlecase("overworld_central"), "Overworld Central",
		"snake_case 2 parts")
	assert_eq(BS._titlecase("miniboss_corrupted"), "Miniboss Corrupted",
		"snake_case 2 parts")
	assert_eq(BS._titlecase(""), "",
		"empty string passes through")
	assert_eq(BS._titlecase("single"), "Single",
		"single word capitalized")


func test_get_pools_for_monster_finds_real_pools() -> void:
	# Pin: slime appears in multiple pools across the live data.
	# Catches future enemy_pools.json edits that orphan a monster.
	var BS = load(BESTIARY_SYSTEM)
	var pools: Array = BS.get_pools_for_monster("slime")
	assert_gt(pools.size(), 0,
		"slime must be in at least one pool (sanity)")
	# Prettified — no underscores.
	for p in pools:
		assert_false("_" in p,
			"pool name must be prettified (no underscores): %s" % p)
		# First char of first word uppercase.
		assert_true(p.length() > 0 and p[0] == p[0].to_upper(),
			"pool name must be title-cased: %s" % p)


func test_get_pools_for_monster_empty_for_unknown() -> void:
	var BS = load(BESTIARY_SYSTEM)
	var pools: Array = BS.get_pools_for_monster("definitely_not_a_real_monster_xyz123")
	assert_eq(pools.size(), 0,
		"unknown monster → empty pool list (no false positives)")


func test_get_pools_for_monster_empty_id() -> void:
	var BS = load(BESTIARY_SYSTEM)
	assert_eq(BS.get_pools_for_monster("").size(), 0,
		"empty monster_id → empty list (defensive)")


# ── Integration: get_seen_entries_sorted includes pools ───────────────

func test_entries_carry_pools_field() -> void:
	# Pin: the entries shape produced by get_seen_entries_sorted
	# now has a "pools" field (or the bestiary couldn't display it).
	# Whole-file contains is sufficient — there's only one such literal.
	var src := _read(BESTIARY_SYSTEM)
	assert_true(src.contains("\"pools\": get_pools_for_monster(id),"),
		"get_seen_entries_sorted must populate pools field per entry")


# ── Cross-pin: existing flavor/get_flavor pipeline still in place ──────

func test_get_flavor_helper_preserved() -> void:
	# The new feature relies on get_flavor still working — it's the
	# source of entry.flavor used in the menu.
	var src := _read(BESTIARY_SYSTEM)
	assert_true(src.contains("static func get_flavor(monster_id: String) -> String:"),
		"get_flavor helper preserved")
	# And get_seen_entries_sorted still calls it.
	assert_true(src.contains("\"flavor\": get_flavor(id),"),
		"get_seen_entries_sorted still calls get_flavor")


func test_pools_cache_loads_separately() -> void:
	# Pin: _pools_cache is a separate static cache, distinct from
	# _monsters_cache / _bestiary_cache.
	var src := _read(BESTIARY_SYSTEM)
	assert_true(src.contains("static var _pools_cache: Dictionary = {}"),
		"_pools_cache must be its own static var")
	assert_true(src.contains("_pools_cache = _load_json(ENEMY_POOLS_JSON)"),
		"_ensure_loaded must load pools via the shared loud-fail helper")


func test_reload_clears_pools_cache() -> void:
	# Pin: reload() includes pools so story-agent edits to
	# enemy_pools.json hot-reload like the others.
	var src := _read(BESTIARY_SYSTEM)
	var fn_idx: int = src.find("static func reload")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nstatic func ", fn_idx + 1)
	if next_fn < 0:
		next_fn = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > -1 else src.substr(fn_idx)
	assert_true(body.contains("_pools_cache.clear()"),
		"reload() must clear _pools_cache for hot-reload symmetry")
