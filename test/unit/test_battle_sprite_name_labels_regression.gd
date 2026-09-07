extends GutTest

## struktured cap 2026-08-15: the floating "FIGHTER" label rendered nowhere near
## the fighter in the stacked party formation, and the PARTY panel already names
## everyone. Party sprites get NO floating name label; enemies KEEP theirs — with
## multiple same-species monsters the under-sprite name is the targeting aid
## ("the monster ones are helpful tho").

func test_party_sprites_have_no_name_label_but_enemies_keep_theirs() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var party_idx := src.find("party_sprite_nodes.append(sprite)")
	assert_gt(party_idx, -1, "party sprite build block present")
	var enemy_idx := src.find("enemy_sprite_nodes.append", party_idx)
	assert_gt(enemy_idx, party_idx, "enemy sprite build follows in the same function")
	var party_block := src.substr(party_idx, enemy_idx - party_idx)
	assert_false("_add_sprite_label" in party_block,
		"party members must NOT get a floating name label — the PARTY panel names them")
	assert_gte(src.count("_add_sprite_label(sprite, enemy.combatant_name"), 2,
		"both enemy spawn paths (battle start + mid-battle summon) keep the name label")
