extends GutTest

## tick 136 regression: the "[persona] does not react." log line
## fired when an Address directive doesn't land must use the
## canonical boss display name (BattleManager._resolve_boss_display_name)
## not the raw prettifier on persona_id. Pre-fix
## "the_warden" displayed as "The Warden" (which happened to match
## prettified id since that's how the persona_id is structured) —
## but for personas with shorthand ids like "mordaine" or
## "umbraxis", the prettifier just capitalized first letter while
## the canonical name has the full title ("Chancellor Mordaine",
## "Umbraxis, the Void Render").

const BATTLE_COMMAND := "res://src/battle/BattleCommandMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_address_does_not_react_uses_canonical_resolver() -> void:
	var src := _read(BATTLE_COMMAND)
	# The exact log line must call _resolve_boss_display_name.
	assert_true(src.contains("BattleManager._resolve_boss_display_name(persona_id)"),
		"'does not react' log line must use BattleManager._resolve_boss_display_name(persona_id) — canonical title from BossDialogue")
	# Negative pin: the old prettifier must be gone from this line.
	assert_false(src.contains("does not react.[/color]\" % persona_id.replace(\"_\", \" \").capitalize()"),
		"old direct prettifier path must be gone")


func test_address_log_format_preserved() -> void:
	var src := _read(BATTLE_COMMAND)
	# Don't regress the visible format string itself.
	assert_true(src.contains("[color=gray]%s does not react.[/color]"),
		"visible format string '[gray] X does not react.' must remain")


func test_resolve_boss_display_name_exists_on_battle_manager() -> void:
	# Caller-side check: the function we're calling actually exists.
	# Without this, the new call site silently crashes at runtime
	# the first time a directive misses.
	var bm_src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_true(bm_src.contains("func _resolve_boss_display_name(persona_id: String)"),
		"BattleManager._resolve_boss_display_name must exist — BattleCommandMenu calls it")


func test_resolve_boss_display_name_falls_back_to_prettifier() -> void:
	# The chosen resolver function tries enemy_party metadata, then
	# BossDialogue, then prettifier. Pin: prettifier fallback exists
	# for unknown personas (graceful degradation).
	var bm_src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	# Find the function body window and check it contains the
	# prettifier fallback.
	var idx: int = bm_src.find("func _resolve_boss_display_name")
	assert_gt(idx, -1, "function must exist")
	var next_fn: int = bm_src.find("\nfunc ", idx + 1)
	var body: String = bm_src.substr(idx, next_fn - idx) if next_fn > -1 else bm_src.substr(idx)
	assert_true(body.contains("persona_id.replace(\"_\", \" \").capitalize()"),
		"_resolve_boss_display_name must keep prettifier fallback for unknown personas")
	assert_true(body.contains("BossDialogue"),
		"_resolve_boss_display_name must consult BossDialogue.get_display_name")
