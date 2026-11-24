extends GutTest
## 2026-11-24 (cowir-story): an authored charge_line REPLACES the generic "X is gathering power for <Signature>!" (BattleManager
## ._execute_boss_charge), so Glacius's charge turn stopped naming Absolute Zero: the one warning turn no longer said what was coming.
## Every authored charge_line of a cadence boss must name its signature by the ability's display name.


func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _ability_name(abilities: Variant, id: String) -> String:
	if abilities is Dictionary:
		var row: Variant = (abilities as Dictionary).get(id, {})
		return str((row as Dictionary).get("name", "")) if row is Dictionary else ""
	for row in abilities:
		if row is Dictionary and str(row.get("id", "")) == id:
			return str(row.get("name", ""))
	return ""


func test_every_authored_charge_line_names_its_signature() -> void:
	var monsters := _json("res://data/monsters.json")
	var dialogue := _json("res://data/boss_dialogue.json")
	var abilities: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var judged := 0
	var silent_on_what: Array = []
	for id in monsters:
		var row: Variant = monsters[id]
		if not (row is Dictionary) or not ((row as Dictionary).get("cadence") is Dictionary):
			continue
		var persona := str(row.get("boss_llm_persona_id", "")) if str(row.get("boss_llm_persona_id", "")) != "" else str(id)
		var entry: Variant = dialogue.get(persona, {})
		var line := str((entry as Dictionary).get("charge_line", "")) if entry is Dictionary else ""
		if line.strip_edges() == "":
			continue
		var sig_name := _ability_name(abilities, str(row["cadence"].get("signature", "")))
		assert_ne(sig_name, "", "CONTROL: %s's signature has a display name to name" % id)
		judged += 1
		if not line.contains(sig_name):
			silent_on_what.append("%s: never says '%s'" % [persona, sig_name])
	assert_gt(judged, 0, "CONTROL: at least one cadence boss authors a charge line (Glacius)")
	assert_eq(silent_on_what, [], "a charge line replaces the warning that names the attack, so it must name it itself")


func test_the_generic_warning_names_the_attack() -> void:
	## CONTROL for the premise: without an authored line, the log already names the signature.
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_true(src.contains("is gathering power for %s!"), "the unauthored charge log names the ability")
