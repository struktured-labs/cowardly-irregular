extends GutTest

## Cycle 19 (cowir-sfx msg 2893 / cowir-main GO msg 2903) — weakness_flash
## audio consumer.
##
## Cycle 16 shipped the VISUAL half of the weakness-hit reaction (element-
## colored deep flash + escalated knockback on elemental_mod > 1.0).
## cowir-sfx then shipped SoundManager.play_weakness_flash() as the audio
## half. This cycle wires them together at the same gate so sound and
## palette punch land on ONE frame rather than as two separate beats —
## struktured's standing "cinematic speed still needs more flash" note.
##
## Placement detail worth pinning: the audio call sits BEFORE the sprite
## lookup, so a weakness hit against a combatant with no resolvable
## sprite (off-screen summon, mid-teardown, sprite array desync) still
## gets the audio half rather than silently dropping both. Visual half
## degrades alone; audio is unconditional on the gate.

const BS_PATH: String = "res://src/battle/BattleScene.gd"
const SM_PATH: String = "res://src/audio/SoundManager.gd"


## ── (1) The consumer call exists at the weakness gate ─────────────────

func test_weakness_flash_called_in_damage_handler() -> void:
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _on_damage_dealt(target: Combatant")
	assert_gt(idx, -1)
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 3000)
	assert_string_contains(body, "SoundManager.play_weakness_flash()",
		"_on_damage_dealt must fire the weakness stinger — cycle 16 shipped the visual half, this is the audio half")


func test_weakness_flash_shares_the_cycle16_gate() -> void:
	# Same gate as the visuals: elemental_mod > 1.0 AND enemies-only.
	# A weakness stinger on a PLAYER taking elemental damage would
	# invert the feedback (the sound reads as "you did something
	# good"). Enemies-only is the correct asymmetry, matching the
	# visual half's rationale.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("SoundManager.play_weakness_flash()")
	assert_gt(idx, -1)
	var before: String = src.substr(maxi(0, idx - 500), 500)
	assert_string_contains(before, "elemental_mod > 1.0",
		"stinger must sit inside the elemental_mod > 1.0 gate — resist/immune hits must not play it")
	assert_string_contains(before, "target in BattleManager.enemy_party",
		"stinger must be enemies-only — a weakness hit ON the party shouldn't play a triumphant cue")


## ── (2) Audio fires even when the sprite lookup fails ────────────────

func test_flash_audio_precedes_sprite_lookup() -> void:
	# Deliberate ordering. _get_combatant_sprite can return null
	# (sprite arrays desync during teardown, summons that never got a
	# node, spotlight party swaps). If the audio call sat inside the
	# `if wsprite:` block, those cases would drop BOTH halves silently.
	# Audio before lookup means the visual degrades alone.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var sfx_idx: int = src.find("SoundManager.play_weakness_flash()")
	assert_gt(sfx_idx, -1)
	var lookup_idx: int = src.find("var wsprite: Node2D = _get_combatant_sprite(target)")
	assert_gt(lookup_idx, -1, "the cycle-16 sprite lookup must still exist")
	assert_lt(sfx_idx, lookup_idx,
		"audio call must PRECEDE the sprite lookup so a null sprite doesn't silently drop the audio half too")


func test_flash_audio_outside_the_sprite_null_guard() -> void:
	# Stronger form of the above: assert the call is not nested inside
	# the `if wsprite:` body. Text-check via indentation depth — the
	# audio line sits at the gate's indent level, the visual calls sit
	# one deeper.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var sfx_idx: int = src.find("SoundManager.play_weakness_flash()")
	assert_gt(sfx_idx, -1)
	# Walk back to the start of that line and count leading tabs.
	var line_start: int = src.rfind("\n", sfx_idx) + 1
	var line: String = src.substr(line_start, sfx_idx - line_start)
	var sfx_tabs: int = line.length()
	# Now do the same for the visuals call, which IS inside `if wsprite:`.
	var vis_idx: int = src.find("_apply_weakness_hit_visuals(wsprite")
	assert_gt(vis_idx, -1)
	var vis_line_start: int = src.rfind("\n", vis_idx) + 1
	var vis_line: String = src.substr(vis_line_start, vis_idx - vis_line_start)
	var vis_tabs: int = vis_line.length()
	assert_lt(sfx_tabs, vis_tabs,
		"audio call must be at a SHALLOWER indent than the visual calls — proves it's outside the `if wsprite:` null guard")


## ── (3) The SoundManager surface it depends on ───────────────────────

func test_sound_manager_exposes_weakness_flash() -> void:
	# Cross-lane dependency pin (cowir-sfx owns this side). If their
	# method is renamed or removed, this fails here with a clear
	# message rather than as a silent no-op at runtime.
	var src: String = FileAccess.get_file_as_string(SM_PATH)
	assert_string_contains(src, "func play_weakness_flash() -> void:",
		"SoundManager.play_weakness_flash must exist — cowir-sfx owns it; ping them before changing the signature")


func test_weakness_flash_manifest_key_present() -> void:
	# The method is manifest-guarded (safe no-op if the key is absent),
	# so a missing key would degrade silently rather than crash. Pin
	# the key so the degradation is caught at commit time instead of
	# by ear during playtest.
	var f: FileAccess = FileAccess.open("res://data/sfx_manifest.json", FileAccess.READ)
	assert_not_null(f, "sfx_manifest.json must be readable")
	var text: String = f.get_as_text()
	assert_true(text.find("weakness_flash") > -1,
		"sfx_manifest must carry the weakness_flash key — play_weakness_flash is manifest-guarded and would no-op silently without it")


## ── (4) Cycle-16 visual half still intact (no regression) ────────────

func test_cycle16_visual_half_still_wired() -> void:
	# The audio addition must not have displaced the visuals. Both
	# halves fire from the same gate; this cycle only ADDS.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _on_damage_dealt(target: Combatant")
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 3000)
	assert_string_contains(body, "_apply_weakness_hit_visuals(",
		"cycle-16 flash must survive the audio wire")
	assert_string_contains(body, "_apply_weakness_hit_knockback(",
		"cycle-16 knockback must survive the audio wire")
