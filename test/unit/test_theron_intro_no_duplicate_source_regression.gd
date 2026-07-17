extends GutTest

## Playtest 2026-07-12: struktured flagged that Elder Theron's first-talk
## scripted intro deflated chapter1's briefing (redundant cave-warnings,
## voice clash). cowir-story rewrote HarmoniaVillage.gd's constructor lines
## with a pre/post chapter1 conditional branch. BUT the same content lived
## in npc_showcase_personas.json as `fallbacks`, which
## OverworldNPC._setup_persona_data unconditionally uses to OVERRIDE the
## constructor's dialogue_lines — silently no-op'ing the rewrite. This test
## pins the hidden-duplication class so a future contributor doesn't
## re-introduce a persona `fallbacks` array that shadows a constructor's
## conditional lines.

const PERSONAS_PATH := "res://data/cutscenes/npc_showcase_personas.json"

## Anti-strings from the OLD deflating intro. If any of these show up in
## Theron's persona fallbacks OR his constructor lines, the redundant-
## warning class regressed.
const OLD_INTRO_ANTIPATTERNS := [
	"dark rumors",
	"May the light guide",
	"peaceful village has stood",
]


func test_theron_persona_fallbacks_do_not_shadow_the_constructor_lines() -> void:
	var raw := FileAccess.get_file_as_string(PERSONAS_PATH)
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "personas JSON must parse")
	var personas: Dictionary = parsed
	if parsed.has("personas") and (parsed as Dictionary).get("personas") is Dictionary:
		personas = (parsed as Dictionary).get("personas")
	assert_true(personas.has("Elder Theron"), "Elder Theron persona must exist")
	var theron: Dictionary = personas.get("Elder Theron", {})
	# Explicit contract: NPCs with constructor-time conditional dialogue
	# (HarmoniaVillage picks pre/post chapter1) MUST NOT also define
	# `fallbacks` in the persona JSON — persona fallbacks unconditionally
	# override constructor lines (OverworldNPC._setup_persona_data:203-210).
	assert_false(theron.has("fallbacks"),
		"Elder Theron's persona must not carry a `fallbacks` array — the constructor's conditional lines (HarmoniaVillage.gd) are the authoritative source; a persona fallbacks array here silently overrides them.")
	# 2026-07-16 (cowir-story ask, msg 2619): Boris joined the constructor-conditional club with his post-cave lines — same shadow contract now applies to him.
	assert_true(personas.has("Guard Boris"), "Guard Boris persona must exist")
	assert_false((personas.get("Guard Boris", {}) as Dictionary).has("fallbacks"),
		"Guard Boris's persona must not carry `fallbacks` — his pre/post-cave constructor lines are authoritative (same shadow class as Theron, msg 2443)")


func test_no_source_still_contains_the_old_deflating_intro() -> void:
	# Belt-and-suspenders: even outside the persona JSON, no live source
	# should still ship the old warning-cliché lines.
	var checked := 0
	for path in ["res://src/maps/villages/HarmoniaVillage.gd", PERSONAS_PATH]:
		var src := FileAccess.get_file_as_string(path)
		assert_true(src.length() > 0, "must be able to read %s" % path)
		for phrase in OLD_INTRO_ANTIPATTERNS:
			assert_false(src.contains(phrase),
				"%s still contains old deflating-intro phrase %s — chapter1 punchline is undermined" % [path.get_file(), phrase])
		checked += 1
	assert_gt(checked, 0)
