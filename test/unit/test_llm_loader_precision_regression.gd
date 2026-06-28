extends GutTest

## tick 345: BossDialogue._load_data and PartyPersonas._load_data
## now distinguish JSON parse-error from non-Dict-root in their
## post-fail diagnostics.
##
## Pre-fix both files used:
##   var parsed = JSON.parse_string(raw)
##   if not (parsed is Dictionary):
##       push_warning("data root is not a Dictionary")
##       return
##
## JSON.parse_string returns null on parse error. `not (parsed is
## Dictionary)` is true for null too. So a JSON syntax error was
## misreported as a root-type error — dev opens the file expecting
## "wrong shape" and sees valid Dictionary-style JSON with a missing
## comma; spends 20 min debugging the wrong thing.
##
## Same precision class as the 4-stage loud-fail pattern in ticks
## 322 (load_monsters_data) and 344 (load_grind_snapshot).

const BOSS_DIALOGUE_PATH := "res://src/llm/BossDialogue.gd"
const PARTY_PERSONAS_PATH := "res://src/llm/PartyPersonas.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: BossDialogue distinguishes the two cases ────────────

func test_boss_dialogue_distinguishes_parse_vs_root() -> void:
	var src := _read(BOSS_DIALOGUE_PATH)
	var fn_idx: int = src.find("func _load_data")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("if parsed == null:"),
		"BossDialogue must check parsed == null separately to identify JSON parse errors")
	assert_true(body.contains("parse error"),
		"parse-error warning must say 'parse error' explicitly")
	assert_true(body.contains("root is not a Dictionary"),
		"non-Dict warning must still exist for the type-mismatch case")


# ── Source pin: PartyPersonas distinguishes the two cases ───────────

func test_party_personas_distinguishes_parse_vs_root() -> void:
	var src := _read(PARTY_PERSONAS_PATH)
	var fn_idx: int = src.find("func _load_data")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("if parsed == null:"),
		"PartyPersonas must check parsed == null separately")
	assert_true(body.contains("parse error"),
		"parse-error warning must say 'parse error' explicitly")
	assert_true(body.contains("root is not a Dictionary"),
		"non-Dict warning must still exist")


# ── Both warnings name the path so devs know which file ─────────────

func test_each_warning_includes_path_or_class_tag() -> void:
	var boss_src := _read(BOSS_DIALOGUE_PATH)
	var personas_src := _read(PARTY_PERSONAS_PATH)

	# BossDialogue warnings should include "[BossDialogue]" prefix.
	var boss_fn_idx: int = boss_src.find("func _load_data")
	var boss_next_fn: int = boss_src.find("\nfunc ", boss_fn_idx + 1)
	var boss_body: String = boss_src.substr(boss_fn_idx, boss_next_fn - boss_fn_idx) if boss_next_fn > 0 else boss_src.substr(boss_fn_idx)
	var boss_warn_count: int = boss_body.count("[BossDialogue]")
	assert_gte(boss_warn_count, 4,
		"BossDialogue warnings must all carry the [BossDialogue] prefix tag. Found: %d" % boss_warn_count)

	# PartyPersonas warnings should include "[PartyPersonas]" prefix.
	var personas_fn_idx: int = personas_src.find("func _load_data")
	var personas_next_fn: int = personas_src.find("\nfunc ", personas_fn_idx + 1)
	var personas_body: String = personas_src.substr(personas_fn_idx, personas_next_fn - personas_fn_idx) if personas_next_fn > 0 else personas_src.substr(personas_fn_idx)
	var personas_warn_count: int = personas_body.count("[PartyPersonas]")
	assert_gte(personas_warn_count, 3,
		"PartyPersonas warnings must all carry the [PartyPersonas] prefix tag. Found: %d" % personas_warn_count)


# ── Behavioral: real autoload still loads valid data ────────────────

func test_real_autoload_still_loads() -> void:
	# Regression guard — make sure the precision tightening didn't
	# break the happy path.
	if BossDialogue:
		BossDialogue._load_data()
		# Should have loaded (_loaded flag set) without crashing.
		assert_true(BossDialogue._loaded,
			"BossDialogue must finish loading via the happy path")
	if PartyPersonas:
		PartyPersonas._load_data()
		assert_true(PartyPersonas._loaded,
			"PartyPersonas must finish loading via the happy path")
