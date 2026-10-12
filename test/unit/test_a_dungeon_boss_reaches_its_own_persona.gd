extends GutTest

## A dungeon boss arrives carrying ONLY monster_type — the encounter spawn path sets no is_boss and
## no llm_persona_id — so its intents and its gloat have to resolve from that one meta.

## What DragonCave and CastleHarmonia emit at `battle_triggered.emit([boss_id])`, not persona names.
const DUNGEON_BOSS_IDS: Array[String] = [
	"fire_dragon", "ice_dragon", "lightning_dragon", "shadow_dragon", "chancellor_mordaine",
]

## Authored gap, not a wiring bug: no boss_dialogue.json section exists for the tutorial boss, so it
## has no intents and no gloat by authoring. cowir-story's call; drop it here once a section lands.
const NO_SECTION_AUTHORED: Array[String] = ["cave_rat_king"]

var _saved_enemies: Array = []


func before_each() -> void:
	_saved_enemies = BattleManager.enemy_party.duplicate()


func after_each() -> void:
	BattleManager.enemy_party.assign(_saved_enemies.filter(func(c): return is_instance_valid(c)))


## Exactly the meta spawn_encounter_enemies leaves on a boss: its catalog id, nothing else.
func _as_encounter_spawn(monster_id: String) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = monster_id
	c.is_alive = true
	c.max_hp = 100
	c.current_hp = 100
	c.set_meta("monster_type", monster_id)
	return c


func test_the_catalog_bridges_a_boss_id_to_its_persona() -> void:
	## CONTROL on the fixture itself: these ids really are NOT persona keys, so the arms below are
	## about the bridge rather than about ids that happened to match.
	assert_false(BossDialogue.has_entry("fire_dragon"),
		"CONTROL: fire_dragon must not be a boss_dialogue key, or this file proves nothing")
	assert_eq(BattleManager._boss_persona_id(_as_encounter_spawn("fire_dragon")), "pyrroth",
		"the dragon's authored persona in monsters.json never reached the combatant")


func test_every_dungeon_boss_resolves_a_dialogue_persona() -> void:
	var dark: Array[String] = []
	for id in DUNGEON_BOSS_IDS:
		var persona: String = BattleManager._boss_persona_id(_as_encounter_spawn(id))
		if persona == "" or not BossDialogue.has_entry(persona):
			dark.append("%s->'%s'" % [id, persona])
	assert_eq(dark, ([] as Array[String]),
		"these reach no boss persona, so they pick no intent and never taunt: %s" % ", ".join(dark))


func test_every_dungeon_boss_resolves_a_gloat() -> void:
	var silent: Array[String] = []
	for id in DUNGEON_BOSS_IDS:
		BattleManager.enemy_party.assign([_as_encounter_spawn(id)] as Array[Combatant])
		if BattleManager._resolve_gloat_boss_persona() == "":
			silent.append(id)
	assert_eq(silent, ([] as Array[String]),
		"no victory or defeat gloat fires for these: %s" % ", ".join(silent))


func test_an_explicit_persona_handle_still_wins() -> void:
	## The forced path sets llm_persona_id; it must outrank the catalog bridge.
	var c := _as_encounter_spawn("fire_dragon")
	c.set_meta("llm_persona_id", "chancellor_mordaine")
	assert_eq(BattleManager._boss_persona_id(c), "chancellor_mordaine",
		"an explicit persona override lost to the catalog mapping")


func test_a_trash_mob_resolves_nothing() -> void:
	## CONTROL: the gloat gate is now the authored section, so an ordinary monster must still be
	## quiet — otherwise this change would make every slime a boss.
	var slime := _as_encounter_spawn("slime")
	assert_eq(BattleManager._boss_persona_id(slime), "slime",
		"a monster with no authored persona must resolve to its own id")
	assert_false(BossDialogue.has_entry("slime"), "CONTROL: slime must have no authored section")
	BattleManager.enemy_party.assign([slime] as Array[Combatant])
	assert_eq(BattleManager._resolve_gloat_boss_persona(), "",
		"a slime resolved a boss gloat")


func test_the_unauthored_boss_is_still_unauthored() -> void:
	## Pins the content gap so it cannot be mistaken for this wiring bug, and reds when a section is
	## authored — at which point the id moves into DUNGEON_BOSS_IDS above.
	for id in NO_SECTION_AUTHORED:
		var persona: String = BattleManager._boss_persona_id(_as_encounter_spawn(id))
		assert_false(BossDialogue.has_entry(persona),
			"'%s' now has an authored section as '%s' — move it into DUNGEON_BOSS_IDS" % [id, persona])
