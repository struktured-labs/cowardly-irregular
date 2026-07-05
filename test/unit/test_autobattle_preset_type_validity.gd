extends GutTest

## Data-integrity guard (2026-07-05): every rule in every built-in autobattle
## preset (data/autobattle_rule_templates.json — the Defensive/Balanced/
## Aggressive catalog) must reference only registered condition / action /
## target types. A preset pointing at a renamed or removed type would silently
## misbehave the moment a player loads it (unknown condition -> always false,
## unknown target -> falls back to lowest_hp_enemy). Same registry-drift net the
## LLM grammar (v3.33.5) and grid editor (v3.33.22/23) now have. 15 presets today.

const TEMPLATES_PATH := "res://data/autobattle_rule_templates.json"


func test_every_preset_uses_registered_types() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(TEMPLATES_PATH))
	assert_eq(typeof(data), TYPE_DICTIONARY, "templates json must parse to a Dictionary")
	var templates: Array = data.get("templates", [])
	assert_gt(templates.size(), 0, "there must be preset templates")

	var conds: Dictionary = AutobattleSystem.CONDITION_TYPES
	var acts: Dictionary = AutobattleSystem.ACTION_TYPES
	var tgts: Dictionary = AutobattleSystem.TARGET_TYPES

	var offenders: Array[String] = []
	for tpl in templates:
		if typeof(tpl) != TYPE_DICTIONARY:
			continue
		var tid: String = str(tpl.get("id", "?"))
		for rule in tpl.get("rules", []):
			if typeof(rule) != TYPE_DICTIONARY:
				continue
			for c in rule.get("conditions", []):
				var ct: String = str(c.get("type", ""))
				if not conds.has(ct):
					offenders.append("%s: unknown condition '%s'" % [tid, ct])
			for act in rule.get("actions", []):
				var at: String = str(act.get("type", ""))
				if not acts.has(at):
					offenders.append("%s: unknown action '%s'" % [tid, at])
				if act.has("target"):
					var tg: String = str(act.get("target", ""))
					if not tgts.has(tg):
						offenders.append("%s: unknown target '%s'" % [tid, tg])

	assert_eq(offenders.size(), 0,
		"built-in preset(s) reference a type the engine doesn't register — they'd silently " +
		"misbehave on load. Fix the preset or restore the type: %s" % str(offenders))
