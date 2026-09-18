extends GutTest

## ⛔ ONE BOSS KEY, TWO DERIVATIONS. Every BossDialogue call site resolves the boss by reading
## `llm_persona_id` first and falling back to `monster_type` — opening lines, display name, jailbreak,
## boss insight. `_maybe_boss_phase_bark` read `monster_type` ALONE, so a boss authored under a
## persona name looked up the wrong key, got `{}`, and `continue`d in silence.
##
## ⚠️ LATENT WHEN FIXED, WHICH IS WHY IT NEEDS A GUARD RATHER THAN JUST A FIX. Only `the_calibrant`
## authors phase_barks today and it carries no override, so the repair changes nothing observable —
## and a revert would change nothing observable either. The trigger is ordinary content work: author
## a phase bark for any of the four W1 dragons and it would never have fired. (cowir-ai, 2026-09-17.)

const GdSourceHelper = preload("res://test/unit/helpers/gd_source.gd")
const BM_PATH := "res://src/battle/BattleManager.gd"
const MONSTERS := "res://data/monsters.json"


func _body(fn: String) -> String:
	var code: String = GdSourceHelper.code_of(BM_PATH)
	var at: int = code.find("func %s(" % fn)
	assert_gt(at, -1, "CONTROL: %s survives stripping" % fn)
	var nxt: int = code.find("\nfunc ", at + 1)
	return code.substr(at, (nxt - at) if nxt > at else 4000)


func _monsters() -> Dictionary:
	var f := FileAccess.open(MONSTERS, FileAccess.READ)
	assert_not_null(f, "monsters.json must load")
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	return d.get("monsters", d)


## The DATA control: without an override in the tree there is nothing for the two derivations to
## disagree about, and both arms below would pass on a corpus that cannot express the defect.
func test_some_boss_actually_carries_an_override() -> void:
	var overrides: Array = []
	for mid in _monsters():
		var m = _monsters()[mid]
		if m is Dictionary and str(m.get("boss_llm_persona_id", "")) != "":
			overrides.append(mid)
	assert_gt(overrides.size(), 0,
		"VOID, not clean: no monster carries boss_llm_persona_id, so nothing can disagree")
	for dragon in ["fire_dragon", "ice_dragon", "lightning_dragon", "shadow_dragon"]:
		assert_true(overrides.has(dragon),
			"%s is authored under a persona name and must still carry the override" % dragon)


func test_the_bark_site_consults_the_override() -> void:
	var body: String = _body("_maybe_boss_phase_bark")
	assert_true(body.contains("llm_persona_id"),
		"the bark site must resolve the boss the way every other BossDialogue site does — reading monster_type alone looks up the wrong key for the four dragons and continues in silence")
	assert_true(body.contains("monster_type"),
		"and must still FALL BACK to monster_type, or every boss without an override loses its barks")


## Anti-drift: the two sites must agree, so fixing one and not the other cannot pass.
func test_both_sites_derive_the_key_the_same_way() -> void:
	## ⚠️ THE SIBLING LIST IS MEASURED, NOT GUESSED. My first version named `_maybe_emit_boss_insight`
	## from memory and this arm red on it — that function reads neither key. These six are every
	## function in BattleManager that reads `llm_persona_id`, derived rather than recalled.
	for fn in ["_maybe_boss_phase_bark", "_update_boss_dialogue_phase", "_on_boss_jailbreak_succeeded",
			"try_player_jailbreak_directive", "_resolve_gloat_boss_persona", "_resolve_boss_display_name"]:
		var body: String = _body(fn)
		var persona_at: int = body.find("llm_persona_id")
		var type_at: int = body.find("monster_type")
		assert_gt(persona_at, -1, "%s must read llm_persona_id" % fn)
		assert_gt(type_at, -1, "%s must read monster_type" % fn)
		assert_lt(persona_at, type_at,
			"%s must read the OVERRIDE FIRST and monster_type as the fallback — the reverse order makes the override dead" % fn)
