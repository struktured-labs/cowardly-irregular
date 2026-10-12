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
	## Same subject as before, one layer up: the bark site used to derive the key itself and this arm
	## pinned both reads. On 2026-10-12 it delegates instead, so the override reaches it through the
	## shared reader — which is what the arm was ever really asserting.
	assert_true(_body("_maybe_boss_phase_bark").contains("_boss_persona_id("),
		"the bark site must resolve the boss the way every other BossDialogue site does — reading monster_type alone looks up the wrong key for the four dragons and continues in silence")


## ⛔ ONE DERIVATION FOR THE WHOLE SUBSYSTEM. This arm used to list every function that derived the
## key inline and require each to read the override before the fallback. As of 2026-10-12 exactly one
## function derives it, so the invariant is stronger and shorter: nobody else may read the override.
func test_only_the_shared_reader_derives_the_boss_key() -> void:
	var code: String = GdSourceHelper.code_of(BM_PATH)
	var offenders: Array[String] = []
	var at: int = code.find('get_meta("llm_persona_id"')
	while at > -1:
		var fn_at: int = code.rfind("\nfunc ", at)
		var fn_end: int = code.find("(", fn_at + 6)
		var fn: String = code.substr(fn_at + 6, fn_end - fn_at - 6) if fn_at > -1 and fn_end > fn_at else "(top level)"
		if fn != "_boss_persona_id" and not offenders.has(fn):
			offenders.append(fn)
		at = code.find('get_meta("llm_persona_id"', at + 1)
	assert_gt(code.find('get_meta("llm_persona_id"'), -1,
		"VOID: no function reads the override at all, so this arm cannot see a second one appear")
	assert_eq(offenders, ([] as Array[String]),
		"these derive the boss key themselves instead of calling _boss_persona_id, so they miss the catalog bridge and resolve a dragon's monster id: %s" % ", ".join(offenders))


func test_the_shared_reader_reads_the_override_before_any_fallback() -> void:
	var body: String = _body("_boss_persona_id")
	var persona_at: int = body.find("llm_persona_id")
	var bridge_at: int = body.find("boss_llm_persona_id")
	assert_gt(persona_at, -1, "the shared reader must read the explicit override")
	assert_lt(persona_at, bridge_at,
		"the override must be read BEFORE the catalog bridge — the reverse order makes the override dead")
	## Bridge-before-bare-return is pinned by test_the_shared_reader_is_what_bridges_a_boss_id_to_its_persona.
	## Reading monster_type is not the same as falling back to it: the id is read early to look the
	## bridge up, and only RETURNED last. My first version asserted on the read and red on correct code.


## The phase path and the intent bias reach the key through _boss_persona_id (2026-09-29), so they must still call it.
func test_the_phase_and_intent_paths_resolve_through_the_shared_reader() -> void:
	for fn in ["_update_boss_dialogue_phase", "_intent_ability_bias", "_resolve_gloat_boss_persona",
			"_maybe_boss_phase_bark", "_on_boss_jailbreak_succeeded", "try_player_jailbreak_directive",
			"_resolve_boss_display_name"]:
		assert_true(_body(fn).contains("_boss_persona_id("),
			"%s no longer resolves the boss through _boss_persona_id, so it can drop the persona override" % fn)


## The shared reader carries the catalog bridge (2026-10-12), so delegating to it is what earns the
## dragons their persona. A site that derives inline would resolve "fire_dragon" and find no section.
func test_the_shared_reader_is_what_bridges_a_boss_id_to_its_persona() -> void:
	var body: String = _body("_boss_persona_id")
	assert_true(body.contains("boss_llm_persona_id"),
		"_boss_persona_id must consult monsters.json's boss_llm_persona_id — without it the four dragons resolve their own id, which is not a boss_dialogue key")
	var bridge_at: int = body.find("boss_llm_persona_id")
	var type_return: int = body.rfind("return monster_id")
	assert_gt(type_return, bridge_at,
		"the bare monster id must be the LAST resort, after the catalog bridge")
