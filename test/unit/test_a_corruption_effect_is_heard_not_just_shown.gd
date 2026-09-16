extends GutTest

## Five cues were authored one-per-effect AND given levels in SoundManager's battle trim table — and nothing ever played them.
## Gaining a corruption effect showed a Toast and made no sound, on a pillar CLAUDE.md lists as fully wired.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const GAME_LOOP := "res://src/GameLoop.gd"
const GAME_STATE := "res://src/meta/GameState.gd"
## The expression GameLoop composes the key with — cited so the excuse expires with the code that earns it.
const COMPOSE_EXPR := 'SoundManager.play_battle("corruption_gain_" + effect)'


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


## The effects GameState can actually grant, read from its own list rather than restated here.
func _granted_effects() -> Array[String]:
	var code := GdSource.code_of(GAME_STATE)
	var at := code.find("func _apply_random_corruption_effect(")
	if at == -1:
		return [] as Array[String]
	var open_at := code.find("[", at)
	var close_at := code.find("]", open_at)
	var out: Array[String] = []
	if open_at == -1 or close_at == -1:
		return out
	for raw in code.substr(open_at + 1, close_at - open_at - 1).split(","):
		var s := raw.strip_edges().replace("\"", "")
		if s != "":
			out.append(s)
	return out


func before_each() -> void:
	var sm: Node = _sm()
	if sm:
		sm._sfx_cooldowns.clear()


func test_every_grantable_effect_has_an_authored_cue() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	var effects := _granted_effects()
	assert_gt(effects.size(), 3, "CONTROL: read %d effects out of GameState — the scrape is broken" % effects.size())
	var missing: Array[String] = []
	for e in effects:
		if not sm._sfx_manifest.has("corruption_gain_" + e):
			missing.append(e)
	assert_eq(missing, ([] as Array[String]), "corruption effects a player can be given with no cue: %s" % [missing])


func test_each_cue_resolves_to_a_real_stream() -> void:
	# Behavioural: a renamed or missing file reds here, where a source arm would stay green.
	var sm: Node = _sm()
	if sm == null:
		return
	var unresolved: Array[String] = []
	for e in _granted_effects():
		var key := "corruption_gain_" + e
		sm._sfx_cooldowns.clear()
		sm._battle_player.stream = null
		sm.play_battle(key)
		var s = sm._battle_player.stream
		if s == null or not str(s.resource_path).contains(key):
			unresolved.append(key)
	assert_eq(unresolved, ([] as Array[String]), "cues that did not load through play_battle: %s" % [unresolved])


func test_a_fabricated_effect_stays_silent() -> void:
	# Anti-vacuity: the arm above must be able to FAIL, or "every cue resolved" means nothing.
	var sm: Node = _sm()
	if sm == null:
		return
	sm._battle_player.stream = null
	sm.play_battle("corruption_gain___never_authored__")
	assert_null(sm._battle_player.stream, "a fabricated corruption cue resolved — the arm above cannot fail")


func test_the_authored_mix_survives() -> void:
	# The trim entries are how this was found: a level set for a cue nothing plays.
	var sm: Node = _sm()
	if sm == null:
		return
	var untrimmed: Array[String] = []
	for e in _granted_effects():
		if not sm._BATTLE_VOLUME_TRIM_DB.has("corruption_gain_" + e):
			untrimmed.append(e)
	assert_eq(untrimmed, ([] as Array[String]),
		"these cues lost the level they were authored with — they land startling rather than unsettling: %s" % [untrimmed])


func test_the_handler_composes_the_cue_from_the_effect() -> void:
	# Source-shaped because GameLoop is not an autoload; it is the pattern this surface's other guards use.
	# It pins the WIRING, which the behavioural arms above cannot see — they prove the cues exist, not that anything plays them.
	var code := GdSource.code_of(GAME_LOOP)
	var at := code.find("func _on_corruption_effect_added(")
	assert_gt(at, -1, "CONTROL: the handler must survive the comment strip, or the assert below reads nothing")
	if at == -1:
		return
	var end := code.find("\nfunc ", at + 1)
	var body := code.substr(at, (end - at) if end > at else -1)
	assert_true(body.contains(COMPOSE_EXPR),
		"the corruption cue is no longer played from the handler — the effect lands with a Toast and no sound again")
