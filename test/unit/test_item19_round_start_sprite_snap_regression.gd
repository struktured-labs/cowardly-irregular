extends GutTest

## User playtest item 19: "sometimes objects in battle are stuck on
## the wrong side of the batltefield (like last playthru bard was
## briefly stuck for a turn next to the monsters on the left he
## presumably recently attack)"
##
## Root cause: BattleScene had `_snap_party_sprites_home` — a safety
## net that force-snaps displaced party sprites back to their home
## positions — but it only fired AFTER group attacks (all_out_attack /
## combo_magic / limit_break / formation). Single-attacker
## interruptions (e.g. Bard's attack tween killed mid-return) had no
## catch and would render displaced through the next turn.
##
## Fix: wire the same snap logic to BattleManager.round_started so
## any stray displaced sprite gets caught at the top of every round.
## Extended to enemy_sprite_nodes too since monsters step-out+return
## on their attacks and can hit the same interruption.

const BATTLE_SCENE_PATH := "res://src/battle/BattleScene.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_handler_declared() -> void:
	var src := _read(BATTLE_SCENE_PATH)
	assert_true(src.contains("func _on_round_started_snap_home"),
		"BattleScene must declare _on_round_started_snap_home handler")


func test_round_started_signal_wired() -> void:
	var src := _read(BATTLE_SCENE_PATH)
	assert_true(src.contains("BattleManager.round_started.connect(_on_round_started_snap_home)"),
		"BattleScene._ready must connect BattleManager.round_started to _on_round_started_snap_home")


func test_disconnect_on_tree_exit() -> void:
	# Signal must disconnect symmetric with connect — otherwise stale
	# connections leak when the scene is freed + re-instantiated in
	# subsequent battles.
	var src := _read(BATTLE_SCENE_PATH)
	assert_true(src.contains("BattleManager.round_started.is_connected(_on_round_started_snap_home)"),
		"disconnect block must guard the disconnect with is_connected")
	assert_true(src.contains("BattleManager.round_started.disconnect(_on_round_started_snap_home)"),
		"disconnect block must actually disconnect on tree exit")


func test_handler_snaps_both_sides() -> void:
	# The handler must snap party AND enemies — user's bug was Bard
	# (party) but monsters have the same shape.
	var src := _read(BATTLE_SCENE_PATH)
	var fn_idx: int = src.find("func _on_round_started_snap_home")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_snap_party_sprites_home()"),
		"handler must call _snap_party_sprites_home (reuses existing party-side logic)")
	assert_true(body.contains("enemy_sprite_nodes"),
		"handler must also scan enemy_sprite_nodes — monsters step-out+return too")


func test_20px_displacement_threshold_preserved() -> void:
	# Sanity: the 20px threshold on the party-side snap that avoids
	# unnecessary tweens must also apply on the enemy-side snap.
	# Otherwise every round would fire a tween on every enemy for no
	# visible reason (cost + jitter).
	var src := _read(BATTLE_SCENE_PATH)
	var fn_idx: int = src.find("func _on_round_started_snap_home")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("distance_to(home) > 20"),
		"enemy-side snap must also use the 20px displacement threshold — otherwise every round fires unnecessary tweens")
