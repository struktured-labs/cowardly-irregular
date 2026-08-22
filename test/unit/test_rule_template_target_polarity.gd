extends GutTest

## A preset template names an ability AND a target group, and the two can disagree.
## data/abilities.json says who an ability is FOR; the template says who to aim it AT.
## Nothing reconciled them, so reruling an ability silently inverted a shipped preset.
##
## LIVE INSTANCE, 2026-08-22: Riff was an all_allies MP restore, and the Bard "Defensive"
## and "Balanced" presets fired it at `all_allies` on a low-MP condition. Riff was reruled
## into a 0.4x physical strike with a 70% blind (struktured's playtest note) — and
## AutobattleSystem._resolve_ability_targets only expands when the ABILITY's own
## target_type is a group, so a now-single_enemy ability fell through to the RULE's string
## and was handed the entire living party. A Bard on a shipped preset attacked its own
## party, and the low-MP condition stayed true because Riff no longer restores MP.
## Found by cowir-autogrind tracing it end to end; nothing on the battle side could see it.

const ALLY_TARGETS := ["all_allies", "lowest_hp_ally", "self"]
const ENEMY_TARGETS := ["lowest_hp_enemy", "highest_hp_enemy", "random_enemy",
	"highest_speed_enemy", "highest_atk_enemy", "lowest_magic_defense_enemy", "weakest_to_ability"]


func _abilities() -> Dictionary:
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var list = raw.get("abilities", raw) if raw is Dictionary else raw
	var out := {}
	if list is Array:
		for a in list:
			if a is Dictionary and a.has("id"):
				out[str(a["id"])] = a
	else:
		for k in list:
			out[str(k)] = list[k]
	return out


func _template_ability_actions() -> Array:
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/autobattle_rule_templates.json"))
	var tpls = raw.get("templates", raw) if raw is Dictionary else raw
	var seq = tpls if tpls is Array else tpls.values()
	var out: Array = []
	for t in seq:
		if not (t is Dictionary):
			continue
		for r in t.get("rules", []):
			for a in r.get("actions", []):
				if a is Dictionary and str(a.get("type", "")) == "ability":
					out.append({"template": str(t.get("name", "?")), "id": str(a.get("id", "")), "target": str(a.get("target", ""))})
	return out


func test_the_readers_find_real_data() -> void:
	## CONTROL: both assertions below are vacuous if either file reads empty.
	var ab := _abilities()
	var acts := _template_ability_actions()
	assert_gt(ab.size(), 100, "read a real ability set (%d)" % ab.size())
	assert_gt(acts.size(), 5, "read real template ability actions (%d)" % acts.size())
	assert_true(ab.has("riff"), "and the ability this guard was written for is present")


func test_no_preset_aims_an_ability_at_the_wrong_side() -> void:
	var ab := _abilities()
	var offenders: Array = []
	var checked := 0
	for act in _template_ability_actions():
		var a: Dictionary = ab.get(act["id"], {})
		if a.is_empty():
			offenders.append("%s: ability '%s' does not exist" % [act["template"], act["id"]])
			continue
		var at := str(a.get("target_type", ""))
		if at == "" or act["target"] == "":
			continue
		checked += 1
		var ability_hits_enemies := at.ends_with("enemy") or at.ends_with("enemies")
		var ability_hits_allies := at.ends_with("ally") or at.ends_with("allies") or at == "self"
		if ability_hits_enemies and act["target"] in ALLY_TARGETS:
			offenders.append("%s aims '%s' (%s) at %s — at the player's OWN party" % [act["template"], act["id"], at, act["target"]])
		elif ability_hits_allies and act["target"] in ENEMY_TARGETS:
			offenders.append("%s aims '%s' (%s) at %s — a support ability at an enemy" % [act["template"], act["id"], at, act["target"]])
	assert_gt(checked, 3, "CONTROL: actually compared real pairs (%d)" % checked)
	assert_eq(offenders.size(), 0, "preset actions aimed at the wrong side: " + str(offenders))
