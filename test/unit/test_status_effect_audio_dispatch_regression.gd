extends GutTest

## Regression (2026-07-08, cowir-sfx finding): F1 activated 26 enemy status
## effects but BattleScene's status-audio match only dispatched 4 of them —
## doom/curse/silence/stun/burn/freeze/... landed with ZERO audio. The match
## now ends in a play_status(effect) catch-all (manifest lookup + generic
## fallback) so no future effect can land silently, and the scary statuses
## got bespoke assets. This pins the catch-all, the empty-effect guard, and
## the bespoke manifest keys.

const BS_PATH := "res://src/battle/BattleScene.gd"


func test_bespoke_status_assets_registered() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json"))
	var sfx: Dictionary = manifest.get("sfx", {})
	for key in ["status_doom", "status_curse", "status_silence"]:
		assert_true(sfx.has(key), "%s must be in sfx_manifest (cowir-sfx status branch)" % key)
		var path := "res://assets/audio/sfx/%s.ogg" % key
		assert_true(ResourceLoader.exists(path), "%s asset must exist on disk" % path)


func test_dispatch_has_catch_all_after_empty_guard() -> void:
	## The window was a fixed 2200 chars and the function is 2709, so the catch-all sat at
	## 2312 — OUTSIDE it. Adding one correct match arm pushed it over and this went red on a
	## fix; it had ~70 chars of slack left on main. A byte count is a coincidental value:
	## it fails a correct change and would equally pass a wrong one that happened to be short.
	## Bounded by the next `func ` instead, which is what the assertion was always about.
	##
	## The arms are also located as ARM LINES now, not as bare substrings. `find("_:")`
	## matched the token inside a COMMENT that merely mentioned the catch-all, reporting the
	## arms out of order — a true statement about the text and a false one about the code.
	var src := FileAccess.get_file_as_string(BS_PATH)
	var block_start := src.find("func _on_action_executed")
	assert_gt(block_start, 0, "dispatch host must exist")

	var rest := src.substr(block_start)
	var next_func := rest.find("\nfunc ")
	var block := rest.substr(0, next_func) if next_func > 0 else rest
	assert_gt(block.length(), 200,
		"SCOPE control: extracted %d chars for _on_action_executed — a valid pattern does not imply a non-empty region" % block.length())

	var empty_guard := -1
	var catch_all := -1
	var offset := 0
	for line in block.split("\n"):
		var stripped := line.strip_edges()
		if stripped == "\"\":" and empty_guard < 0:
			empty_guard = offset
		elif stripped == "_:" and catch_all < 0:
			catch_all = offset
		offset += line.length() + 1

	assert_gt(empty_guard, 0, "match must guard the empty effect BEFORE the catch-all (most abilities have no effect)")
	assert_gt(catch_all, empty_guard, "match must end in a play_status(effect) catch-all so no status lands silently")
	assert_true("SoundManager.play_status(effect)" in block,
		"catch-all must route through play_status (manifest lookup + generic fallback)")


func test_every_live_ability_effect_routes_to_audio() -> void:
	# Every effect that can actually fire (effect_chance > 0 or random_debuff)
	# must hit a non-empty match arm. With the catch-all this is true by
	# construction — this asserts the DATA side stays inside the match's
	# reachable space (an empty-string effect with a chance would be silent).
	var abilities = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	for aid in abilities:
		var ab = abilities[aid]
		if typeof(ab) != TYPE_DICTIONARY:
			continue
		var eff := str(ab.get("effect", ""))
		var live: bool = float(ab.get("effect_chance", 0.0)) > 0.0 or eff == "random_debuff"
		if live:
			assert_ne(eff, "", "ability '%s' has an effect_chance but an empty effect — audio (and the effect itself) would silently no-op" % aid)
