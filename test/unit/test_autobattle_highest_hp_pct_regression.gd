extends GutTest

## _get_highest_hp_enemy must sort by HP PERCENTAGE, not by absolute current_hp —
## matches its symmetric pair (_get_lowest_hp_enemy / _get_lowest_hp_ally, both
## already pct-based). Otherwise a 500-HP tank at 50% (current=250) wins over a
## 100-HP enemy at 100% (current=100), which is the opposite of the player-
## facing 'attack the healthiest enemy first' rule semantic.

const AutobattleSystemPath := "res://src/autobattle/AutobattleSystem.gd"


func test_source_uses_get_hp_percentage() -> void:
	var text: String = FileAccess.get_file_as_string(AutobattleSystemPath)
	assert_ne(text, "", "AutobattleSystem.gd must be readable")
	var idx := text.find("func _get_highest_hp_enemy")
	assert_gt(idx, -1, "_get_highest_hp_enemy must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("get_hp_percentage()"),
		"_get_highest_hp_enemy must sort on get_hp_percentage() — symmetric with the lowest_hp picker")
	var lines := body.split("\n")
	var saw_bad := false
	for line in lines:
		var s: String = str(line).strip_edges()
		if s.begins_with("#"):
			continue
		# Old shape was: a.current_hp > b.current_hp
		if s.contains("a.current_hp >") or s.contains("a.current_hp <"):
			saw_bad = true
			break
	assert_false(saw_bad,
		"_get_highest_hp_enemy must not compare a.current_hp directly (asymmetric with the rest of the family)")
