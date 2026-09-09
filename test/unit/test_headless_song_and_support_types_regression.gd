extends GutTest

## The FOURTH layer of the Bard bug (VFX / anim / audio were the other three, found by three other
## lanes on 2026-09-09). Theirs were presentation; this one is mechanics, which is why no
## lane-scoped presentation guard could see it.
##
## _resolve_ability matches on `type` with arms for healing / magic / physical / support only.
## Nine types exist in abilities.json. The `_:` default deals MAGIC DAMAGE to targets[0] — and
## AutobattleSystem builds `targets` from target_type, so an all_allies buff arrives with the
## PARTY in it. battle_hymn, a rallying song, damages the ally it is meant to buff.
##
## 39 abilities author a type with no arm: meta 24 · summon 7 · song 4 · mp_restore 2 ·
## revival 1 · escape 1.


func _combatant(cname: String, magic: int = 30) -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": cname, "max_hp": 500, "max_mp": 60,
		"attack": 10, "defense": 10, "magic": magic, "speed": 10
	})
	add_child_autofree(c)
	return c


func test_a_rallying_song_does_not_damage_the_ally_it_targets() -> void:
	## battle_hymn is type "song", target_type all_allies, effect attack_up.
	var resolver := HeadlessBattleResolver.new()
	var bard := _combatant("Bard")
	var ally := _combatant("Ally")
	var before: int = ally.current_hp
	resolver._resolve_ability(bard, "battle_hymn", [ally])
	assert_eq(ally.current_hp, before,
		"battle_hymn must never damage a party member — it lost %d HP to its own buff" % (before - ally.current_hp))


func test_an_ally_targeted_song_is_not_silently_inert_either() -> void:
	## ARM+ against over-correcting into a no-op: the fix must APPLY the buff, not just stop the
	## damage. Without this, `return` on an unknown type would pass the assertion above.
	var resolver := HeadlessBattleResolver.new()
	var bard := _combatant("Bard")
	var ally := _combatant("Ally")
	resolver._resolve_ability(bard, "battle_hymn", [ally])
	assert_true(ally.has_method("get_buffed_stat"), "precondition: buffs are readable")
	assert_gt(ally.get_buffed_stat("attack", ally.attack), ally.attack,
		"battle_hymn grants attack_up — a song that does nothing is the other way to be wrong")


func test_a_debuff_song_still_reaches_the_enemy() -> void:
	## discord is all_enemies / defense_down. The fix must not make every song ally-only.
	var resolver := HeadlessBattleResolver.new()
	var bard := _combatant("Bard")
	var foe := _combatant("Foe")
	resolver._resolve_ability(bard, "discord", [foe])
	assert_lt(foe.get_buffed_stat("defense", foe.defense), foe.defense,
		"discord must lower enemy defense, not deal damage")


func test_the_unhandled_type_default_no_longer_swallows_whole_families() -> void:
	## summon/meta/mp_restore/revival/escape share the same default. Pin the one that is
	## unambiguously self-harm: an ally-targeted restore must not damage the ally.
	var resolver := HeadlessBattleResolver.new()
	var caster := _combatant("Caster")
	var ally := _combatant("Ally")
	var before: int = ally.current_hp
	resolver._resolve_ability(caster, "inspiring_melody", [ally])
	assert_eq(ally.current_hp, before,
		"inspiring_melody restores MP/AP to allies — it must never damage them")


func test_a_free_move_mp_restore_does_not_damage_the_ally() -> void:
	## `pray` is the Cleric's per-job Free Move (mp_restore / single_ally). It reaches the `_:`
	## arm, so pre-fix it DAMAGED the ally it exists to restore. Found because mutation showed
	## the friendly-fire refusal was untested once songs stopped reaching that arm.
	var resolver := HeadlessBattleResolver.new()
	var cleric := _combatant("Cleric")
	var ally := _combatant("Ally")
	resolver._player_party = [cleric, ally]
	var before: int = ally.current_hp
	resolver._resolve_ability(cleric, "pray", [ally])
	assert_eq(ally.current_hp, before,
		"Pray restores MP to an ally — it must never damage them (lost %d HP)" % (before - ally.current_hp))


func test_a_self_targeted_free_move_does_not_damage_the_caster() -> void:
	## `channel` is the Mage's Free Move (mp_restore / self). Same arm, and the target is the
	## caster, so pre-fix the Mage damaged themselves every time the script fired it.
	var resolver := HeadlessBattleResolver.new()
	var mage := _combatant("Mage")
	resolver._player_party = [mage]
	var before: int = mage.current_hp
	resolver._resolve_ability(mage, "channel", [mage])
	assert_eq(mage.current_hp, before,
		"Channel restores the Mage's own MP — it must never damage them (lost %d HP)" % (before - mage.current_hp))


func test_an_unmodelled_type_still_damages_a_genuine_ENEMY() -> void:
	## ARM+ for the refusal: it must be side-aware, not a blanket "unknown types do nothing".
	## An offensive summon landing on an enemy should still hurt.
	var resolver := HeadlessBattleResolver.new()
	var caster := _combatant("Caster")
	var foe := _combatant("Foe")
	resolver._player_party = [caster]
	resolver._enemy_party = [foe]
	var before: int = foe.current_hp
	resolver._resolve_ability(caster, "rat_swarm", [foe])
	assert_lt(foe.current_hp, before,
		"the refusal must be side-aware — an unmodelled offensive ability on an ENEMY still lands")


func test_pray_actually_restores_mp_not_merely_stops_hurting() -> void:
	## Union with cowir-battle's a0e74614: my friendly-fire refusal alone made pray a NO-OP —
	## harmless but still broken. Their mp_restore arm makes it do its job. Refusing harm and
	## doing the right thing are different bars and only the second one is a fix.
	var resolver := HeadlessBattleResolver.new()
	var cleric := _combatant("Cleric")
	var ally := _combatant("Ally")
	resolver._player_party = [cleric, ally]
	ally.current_mp = 0
	resolver._resolve_ability(cleric, "pray", [ally])
	assert_gt(ally.current_mp, 0, "pray must actually restore the ally's MP")
	assert_eq(ally.current_hp, ally.max_hp, "and must still not damage them")
