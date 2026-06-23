extends GutTest

## User feedback 2026-06-22: "change the advance sfx to something more
## pleasing, see cowir-sfx's setup for how that is accomplished. I was
## thinking of something like a coin dropping into an arcade machine
## indicating u got another credit"
##
## The pre-fix advance_queue.ogg was a 'toned-down gunshot with chorus
## + phaser + multi-tap reverb' — the source of the dislike.
##
## Until cowir-sfx delivers advance_queue_arcade.ogg, the manifest
## points at a not-yet-existing file and falls back to menu_select via
## the fallback_to chain shipped in tick 8. Net result: player
## immediately stops hearing the disliked gunshot SFX — they hear the
## menu_select chirp instead until the new file lands.

const SFX_MANIFEST := "res://data/sfx_manifest.json"


func _manifest() -> Dictionary:
	var f := FileAccess.open(SFX_MANIFEST, FileAccess.READ)
	assert_not_null(f, "sfx_manifest.json must be readable")
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	assert_true(parsed is Dictionary and (parsed as Dictionary).has("sfx"),
		"sfx_manifest.json must have 'sfx' Dictionary")
	return (parsed as Dictionary)["sfx"]


func test_advance_queue_points_at_arcade_file() -> void:
	var sfx := _manifest()
	assert_true(sfx.has("advance_queue"),
		"advance_queue manifest entry must exist")
	var entry: Dictionary = sfx["advance_queue"]
	assert_eq(str(entry.get("file", "")), "assets/audio/sfx/advance_queue_arcade.ogg",
		"advance_queue must point at the new arcade file path so the old gunshot SFX stops being loaded")


func test_advance_queue_prompt_describes_arcade_coin() -> void:
	# The contract with cowir-sfx is the prompt string. It must
	# capture the user's request specifically — generic 'chiptune'
	# wouldn't drive the same output.
	var sfx := _manifest()
	var entry: Dictionary = sfx["advance_queue"]
	var prompt: String = str(entry.get("prompt", ""))
	assert_true(prompt.contains("coin"),
		"prompt must mention 'coin' — the user's specific aesthetic ask")
	assert_true(prompt.contains("arcade") or prompt.contains("Arcade"),
		"prompt must mention arcade — the user's aesthetic reference")
	assert_true(prompt.contains("chiptune") or prompt.contains("FreeBoy") or prompt.contains("Game Boy"),
		"prompt must reference a chiptune source so the SFX team uses the synth path, not the elevenlabs-gunshot path the user disliked")


func test_advance_queue_has_menu_select_fallback() -> void:
	# Until cowir-sfx delivers the new file, the SoundManager fallback
	# chain (tick 8) routes the missing path to menu_select. Without
	# this, the player would hear nothing on Advance.
	var sfx := _manifest()
	var entry: Dictionary = sfx["advance_queue"]
	assert_eq(str(entry.get("fallback_to", "")), "menu_select",
		"advance_queue must fall back to menu_select until the arcade file lands — otherwise Advance fires silently")
	# Sanity: menu_select must exist as a real entry so the fallback
	# isn't itself broken.
	assert_true(sfx.has("menu_select"),
		"menu_select fallback target must exist in the manifest")
