extends GutTest

## Regression: AutogrindController must restore the player's pre-grind
## autobattle script for any character whose script it overwrote with a
## default during _force_autobattle_on. Previously the controller only
## tracked the enabled-state bool — the default script that the
## controller wrote for unscripted characters persisted forever, silently
## mutating the player's authored autobattle state.
##
## Trigger surface: any character who enters autogrind with an empty
## script (the typical case for newly-acquired PCs, or a player who
## opened the editor and saved a stub). After one autogrind session,
## that character would silently get the autogrind default rules baked
## into their script — visible the next time the player opened the
## autobattle editor.
##
## Tests:
##   • A character with an empty pre-grind script gets the default
##     written during _force_autobattle_on (existing behavior intact)
##   • _restore_autobattle_states puts the empty/original script back
##   • A character with a real pre-grind script is NOT touched
##     (regression against over-restoration)
##   • Snapshot dict reset by _save_autobattle_states (no cross-session
##     leak)
##   • Source pin: the snapshot var, the snapshot capture, and the
##     restore loop all exist

const AUTOGRIND_CONTROLLER_PATH := "res://src/autogrind/AutogrindController.gd"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


# ── Source pins ───────────────────────────────────────────────────────────────

func test_authored_scripts_var_declared() -> void:
	var text := _read(AUTOGRIND_CONTROLLER_PATH)
	assert_true(text.contains("var _autogrind_authored_scripts"),
		"AutogrindController must declare _autogrind_authored_scripts to snapshot per-char scripts")


func test_force_autobattle_on_snapshots_pre_grind_script() -> void:
	var text := _read(AUTOGRIND_CONTROLLER_PATH)
	var idx := text.find("func _force_autobattle_on")
	assert_gt(idx, -1, "_force_autobattle_on must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	# The snapshot capture must live inside the "empty/no-rules" branch,
	# BEFORE the set_character_script call that overwrites with the default.
	var has_snapshot := body.contains("_autogrind_authored_scripts[char_id] = active_script")
	assert_true(has_snapshot,
		"_force_autobattle_on must snapshot active_script into _autogrind_authored_scripts before overwriting")


func test_restore_autobattle_states_restores_authored_scripts() -> void:
	var text := _read(AUTOGRIND_CONTROLLER_PATH)
	var idx := text.find("func _restore_autobattle_states")
	assert_gt(idx, -1, "_restore_autobattle_states must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("_autogrind_authored_scripts"),
		"_restore_autobattle_states must read _autogrind_authored_scripts to undo defaults")
	assert_true(body.contains("set_character_script"),
		"_restore_autobattle_states must call set_character_script to put authored state back")
	# And it must clear the snapshot dict so a future grind starts clean.
	assert_true(body.contains("_autogrind_authored_scripts.clear()"),
		"_restore_autobattle_states must clear the snapshot dict (no cross-session leak)")


func test_save_autobattle_states_resets_authored_snapshot() -> void:
	var text := _read(AUTOGRIND_CONTROLLER_PATH)
	var idx := text.find("func _save_autobattle_states")
	assert_gt(idx, -1, "_save_autobattle_states must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("_autogrind_authored_scripts.clear()"),
		"_save_autobattle_states must reset the authored-scripts snapshot at the start of a new grind")


# ── Behavioural ──────────────────────────────────────────────────────────────

func _abs() -> Node:
	return get_node_or_null("/root/AutobattleSystem")


func _make_combatant(name: String) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = name
	c.max_hp = 100
	c.max_mp = 50
	add_child_autofree(c)
	# Combatant._ready resets HP/MP after add_child.
	c.current_hp = 100
	c.current_mp = 50
	return c


func test_empty_script_gets_restored_after_force_then_restore() -> void:
	# End-to-end: character has NO script → force writes a default →
	# restore puts the empty state back.
	var abs := _abs()
	if abs == null:
		pending("AutobattleSystem autoload unavailable")
		return
	var name := "TestRestoredCharacter"
	var char_id: String = name.to_lower()
	# Snapshot any prior script for hygiene; we'll restore after.
	var prior_script: Variant = abs.get_character_script(char_id)
	# Force an empty starting state.
	abs.set_character_script(char_id, {})
	# Standalone controller — not the autoload — so each test runs clean.
	var AGCScript: GDScript = load(AUTOGRIND_CONTROLLER_PATH)
	var ctrl: Node = AGCScript.new()
	add_child_autofree(ctrl)
	var c := _make_combatant(name)
	ctrl._party = [c]
	# Drive the lifecycle manually.
	ctrl._save_autobattle_states()
	ctrl._force_autobattle_on()
	var script_during_grind: Dictionary = abs.get_character_script(char_id)
	assert_false(script_during_grind.is_empty(),
		"after force_autobattle_on, the empty character must have a default script")
	assert_true(script_during_grind.has("rules"),
		"the default script must include rules")
	ctrl._restore_autobattle_states()
	var script_after_restore: Variant = abs.get_character_script(char_id)
	# The pre-grind state was an empty dict — restore must put it back.
	# (Dictionary == {} compares by content in GDScript.)
	assert_true(script_after_restore is Dictionary and (script_after_restore as Dictionary).is_empty(),
		"restore must put the pre-grind empty script back, not leave the autogrind default in place")
	# Cleanup so we don't pollute the autoload across tests.
	if prior_script is Dictionary:
		abs.set_character_script(char_id, prior_script)


func test_real_pre_grind_script_is_not_touched() -> void:
	# Regression against over-restoration: if the player had a real script
	# with rules, _force_autobattle_on must NOT snapshot/overwrite it, and
	# _restore_autobattle_states must NOT touch it either.
	var abs := _abs()
	if abs == null:
		pending("AutobattleSystem autoload unavailable")
		return
	var name := "TestRealScriptCharacter"
	var char_id: String = name.to_lower()
	var prior_script: Variant = abs.get_character_script(char_id)
	# Install a real, distinctive starting script.
	var authored: Dictionary = {
		"rules": [
			{"conditions": [{"type": "always"}], "actions": [{"type": "attack"}]},
		],
		"version": 1,
	}
	abs.set_character_script(char_id, authored)
	var AGCScript: GDScript = load(AUTOGRIND_CONTROLLER_PATH)
	var ctrl: Node = AGCScript.new()
	add_child_autofree(ctrl)
	var c := _make_combatant(name)
	ctrl._party = [c]
	ctrl._save_autobattle_states()
	ctrl._force_autobattle_on()
	var during: Dictionary = abs.get_character_script(char_id)
	assert_eq(during.get("version", -1), 1,
		"authored real script must NOT be overwritten by _force_autobattle_on")
	ctrl._restore_autobattle_states()
	var after: Dictionary = abs.get_character_script(char_id)
	assert_eq(after.get("version", -1), 1,
		"authored real script must still be in place after restore (and not silently re-baked)")
	# Cleanup.
	if prior_script is Dictionary:
		abs.set_character_script(char_id, prior_script)
