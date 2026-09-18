extends GutTest

## Every AudioStreamPlayer SoundManager builds needs four steps: a name, a level, a BUS and
## add_child. Miss the bus and the player escapes set_sfx_volume entirely — that is the 2026-07-28
## defect, where BattleTransition's sting and CutsceneDialogue's blip played at full volume with the
## slider at zero. Miss add_child and it is silent. Both fail without an error.
##
## ⚠️ DERIVED from SoundManager's own source, NOT a hand-list. A hand-list is covered for the
## players that existed when it was written and blind to the next one — which is added exactly the
## way the existing sixteen were, by copying a neighbouring block.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const SOUND_MANAGER := "res://src/audio/SoundManager.gd"

## _music_player_b is seeded from A each crossfade and starts at -80.0; it is a real exception to
## "every player is built at a design-intent base", not an oversight. Named, not suppressed.
const LEVEL_EXEMPT := ["_music_player_b"]


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


## Every `_x = AudioStreamPlayer.new()` in the file, in declaration order.
func _declared_players() -> Array:
	var out: Array = []
	var code: String = GdSource.code_of(SOUND_MANAGER)
	for m in RegEx.create_from_string('(_\\w+) = AudioStreamPlayer\\.new\\(\\)').search_all(code):
		if not out.has(m.get_string(1)):
			out.append(m.get_string(1))
	return out


func test_the_derivation_finds_the_players() -> void:
	## Without this the arms below pass by iterating an empty list — the shrinking-corpus failure.
	var players: Array = _declared_players()
	assert_gt(players.size(), 10,
		"CONTROL: derived only %d players from SoundManager; the constructor pattern changed and every arm below is measuring nothing" % players.size())


func test_every_declared_player_is_named_levelled_bussed_and_parented() -> void:
	var code: String = GdSource.code_of(SOUND_MANAGER)
	assert_ne(code, "", "CONTROL: SoundManager code must survive the comment strip")
	var missing: Array = []
	for p in _declared_players():
		var lacks: Array = []
		if not code.contains("%s.name =" % p):
			lacks.append("name")
		if not code.contains("%s.volume_db =" % p) and not LEVEL_EXEMPT.has(p):
			lacks.append("volume_db")
		if not code.contains("%s.bus =" % p):
			lacks.append("bus — it would escape set_sfx_volume entirely")
		if not code.contains("add_child(%s)" % p):
			lacks.append("add_child — it would never sound")
		if not lacks.is_empty():
			missing.append("%s lacks %s" % [p, ", ".join(lacks)])
	missing.sort()
	assert_eq(missing, [], "audio players are missing setup steps their siblings all have: %s" % str(missing))


func test_every_declared_player_exists_at_runtime_and_is_a_child() -> void:
	## The source arms prove the LINES are there. This proves they ran: a player built inside a
	## branch that never executes reads identically in source and is null in the tree.
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	var bad: Array = []
	for p in _declared_players():
		var node = sm.get(p)
		if node == null:
			bad.append("%s is null at runtime" % p)
		elif not (node is AudioStreamPlayer):
			bad.append("%s is not an AudioStreamPlayer" % p)
		elif node.get_parent() != sm:
			bad.append("%s is not parented to SoundManager" % p)
	bad.sort()
	assert_eq(bad, [], "declared players that did not survive to runtime: %s" % str(bad))


func test_every_sfx_player_rides_the_sfx_bus() -> void:
	## The bus is what set_sfx_volume attenuates. Music/ambient ride their own chains by design —
	## derived from the runtime node, so a new SFX player on the wrong bus is named here.
	var sm: Node = _sm()
	if sm == null:
		return
	var sfx_bus: String = str(sm.get_script().get_script_constant_map()["SFX_BUS"])
	var expected_elsewhere := {"_music_player": true, "_music_player_b": true, "_ambient_player": true}
	var wrong: Array = []
	var on_sfx: int = 0
	for p in _declared_players():
		var node = sm.get(p)
		if node == null:
			continue
		if expected_elsewhere.has(p):
			continue
		if str(node.bus) != sfx_bus:
			wrong.append("%s rides '%s', not '%s' — the SFX slider would not reach it" % [p, node.bus, sfx_bus])
		else:
			on_sfx += 1
	assert_gt(on_sfx, 8, "CONTROL: only %d players on the SFX bus — the derivation or the exemption map is wrong" % on_sfx)
	wrong.sort()
	assert_eq(wrong, [], "players off the SFX bus: %s" % str(wrong))
