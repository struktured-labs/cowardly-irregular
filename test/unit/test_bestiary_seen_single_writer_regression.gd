extends GutTest

## Code-quality regression: BattleScene._mark_monster_seen and _is_new_monster
## must delegate to BestiarySystem rather than inline duplicates of its
## is_seen / mark_seen logic.
##
## Bug shape: the seen-monsters discovery dict lived in
## GameState.game_constants["seen_monsters"]. BestiarySystem exposed
## `is_seen(id)` and `mark_seen(id)` static helpers that wrapped that dict
## access. BattleScene._is_new_monster and _mark_monster_seen reimplemented
## the SAME logic inline, byte-for-byte. The BestiarySystem versions had
## zero callers — dead code. If anyone later changed the seen-monsters
## storage shape (e.g. moved it onto a per-save key, started recording
## first-seen-timestamps, added schema versioning), the inlined BattleScene
## copies would silently drift from the canonical BestiarySystem path that
## the BestiaryMenu actually reads.
##
## Fix: BattleScene delegates to BestiarySystem so the discovery state has
## a single writer. The function signatures stay intact for BattleScene's
## internal callers; only the body changes.
##
## Tests:
##   • Source pin: BattleScene._is_new_monster delegates to BestiarySystem.is_seen
##   • Source pin: BattleScene._mark_monster_seen delegates to BestiarySystem.mark_seen
##   • Negative source pin: BattleScene._mark_monster_seen no longer touches
##     GameState.game_constants["seen_monsters"] directly
##   • Behavioural roundtrip: calling BestiarySystem.mark_seen marks an id as
##     seen via BestiarySystem.is_seen (the contract BattleScene now relies on)

const BATTLE_SCENE_PATH := "res://src/battle/BattleScene.gd"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


# ── Source pins ───────────────────────────────────────────────────────────────

func test_is_new_monster_delegates_to_bestiary_system() -> void:
	var text := _read(BATTLE_SCENE_PATH)
	var idx := text.find("func _is_new_monster")
	assert_gt(idx, -1, "_is_new_monster must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("BestiarySystem.is_seen"),
		"_is_new_monster must delegate to BestiarySystem.is_seen")


func test_mark_monster_seen_delegates_to_bestiary_system() -> void:
	var text := _read(BATTLE_SCENE_PATH)
	var idx := text.find("func _mark_monster_seen")
	assert_gt(idx, -1, "_mark_monster_seen must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("BestiarySystem.mark_seen"),
		"_mark_monster_seen must delegate to BestiarySystem.mark_seen")


func test_mark_monster_seen_no_longer_inlines_game_constants_write() -> void:
	# Negative pin: ensure the inline `GameState.game_constants["seen_monsters"]`
	# write that the BestiarySystem call replaces is GONE from this function.
	# (Other functions in the file may still reference seen_monsters — only
	# the _mark_monster_seen function should be clean.)
	var text := _read(BATTLE_SCENE_PATH)
	var idx := text.find("func _mark_monster_seen")
	assert_gt(idx, -1, "_mark_monster_seen must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	# Strip comments so the explanation can cite the legacy shape.
	var lines := body.split("\n")
	var code_only: PackedStringArray = PackedStringArray()
	for line in lines:
		var ln: String = str(line)
		if ln.strip_edges().begins_with("#"):
			continue
		code_only.append(ln)
	var code := "\n".join(code_only)
	assert_false(code.contains("game_constants[\"seen_monsters\"]"),
		"_mark_monster_seen must not inline a game_constants[\"seen_monsters\"] write — use BestiarySystem.mark_seen")


# ── Behavioural ──────────────────────────────────────────────────────────────

func test_mark_seen_roundtrips_through_is_seen() -> void:
	# The contract BattleScene now relies on: BestiarySystem.mark_seen(id)
	# makes BestiarySystem.is_seen(id) return true. Use a uniquely-named id
	# so we don't collide with any real bestiary data; restore the dict
	# afterwards.
	var test_id := "_test_unicorn_for_singlewriter_regression"
	var prior_seen: Dictionary = GameState.game_constants.get("seen_monsters", {}).duplicate(true)
	# Ensure starting state: NOT seen.
	if GameState.game_constants.has("seen_monsters"):
		(GameState.game_constants["seen_monsters"] as Dictionary).erase(test_id)
	assert_false(BestiarySystem.is_seen(test_id),
		"pre-condition: test id must not be marked seen")
	BestiarySystem.mark_seen(test_id)
	assert_true(BestiarySystem.is_seen(test_id),
		"after mark_seen, is_seen must return true for the same id")
	# Restore.
	GameState.game_constants["seen_monsters"] = prior_seen
