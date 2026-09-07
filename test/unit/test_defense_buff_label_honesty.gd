extends GutTest

## Guards the lie-in-the-label class created by the 2026-07-28 magic_defense split.
##
## Before the split, `defense * 0.5` mitigated magic inline, so a defense buff really
## did reduce every kind of damage and "reduces all damage taken" was true. After it,
## Combatant.take_damage picks the mitigating stat:
##     get_buffed_stat("magic_defense", …) if is_magical else get_buffed_stat("defense", …)
## and BattleManager's _SECONDARY_STAT_BUFF_MAP routes "defense_up" to "defense" alone.
## So any defense_up ability advertising blanket damage reduction now lies to the player,
## and AbilitiesMenu renders that text verbatim.
##
## packet_filter (firewall_sentinel, L13) said "reducing all damage taken for 2 turns".
##
## This pins the RELATIONSHIP — effect vs what the description claims — not the spelling
## of any one ability, so a new defense_up ability with blanket wording fails on arrival.

const ABILITIES := "res://data/abilities.json"
const COMBATANT := "res://src/battle/Combatant.gd"
const BATTLE_MGR := "res://src/battle/BattleManager.gd"

## Wording that promises mitigation of damage in general rather than of one damage kind.
const BLANKET := ["all damage", "damage taken", "any damage", "damage reduction"]


func _abilities() -> Dictionary:
	var f := FileAccess.get_file_as_string(ABILITIES)
	var d = JSON.parse_string(f)
	return d.get("abilities", d) if d is Dictionary else {}


## Positive control: the corpus loaded and actually contains defense_up abilities.
## Without this, an empty parse would make every assertion below vacuously true.
func test_control_corpus_has_defense_buffs() -> void:
	var ab := _abilities()
	assert_gt(ab.size(), 50, "abilities.json must parse with a real corpus")
	var n := 0
	for k in ab:
		if ab[k] is Dictionary and ab[k].get("effect", "") == "defense_up":
			n += 1
	assert_gt(n, 2, "must find defense_up abilities to check — if 0, this file guards nothing")


## The behavioural premise. If either of these stops being true the split was undone,
## and the label rule below is no longer the right rule.
func test_premise_magic_and_physical_mitigate_via_different_stats() -> void:
	var src := FileAccess.get_file_as_string(COMBATANT)
	assert_true(src.contains("get_buffed_stat(\"magic_defense\", magic_defense) if is_magical"),
		"take_damage must select magic_defense for magical damage — if this changed, revisit this file")
	var bm := FileAccess.get_file_as_string(BATTLE_MGR)
	assert_true(bm.contains("\"defense_up\": [\"defense\""),
		"defense_up must still buff `defense` alone — if it also buffs magic_defense, blanket wording becomes honest again")


## THE GUARD. A defense_up ability may not promise blanket damage reduction.
func test_defense_buffs_do_not_advertise_blanket_mitigation() -> void:
	var ab := _abilities()
	var liars: Array = []
	for k in ab:
		var v = ab[k]
		if not (v is Dictionary) or v.get("effect", "") != "defense_up":
			continue
		var desc: String = str(v.get("description", "")).to_lower()
		for phrase in BLANKET:
			if desc.contains(phrase):
				liars.append("%s: \"%s\"" % [k, v.get("description", "")])
				break
	assert_eq(liars, [], "defense_up buffs only `defense`, which mitigates PHYSICAL damage only "
		+ "(Combatant.take_damage routes magic through magic_defense). These descriptions promise "
		+ "blanket reduction and are shown verbatim by AbilitiesMenu: %s" % [liars])
