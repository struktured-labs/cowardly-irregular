extends GutTest

## struktured 2026-08-14: "sometimes the menu obscures the monsters im selecting in battle".
## During target selection the menu CHAIN dims (ancestors 0.35, active list 0.65) so
## monsters read through it; cleanup restores the PRE-dim alpha (menus already run reduced
## alpha over the actor — restoring to 1.0 would fight that system).

const Win98MenuClass = preload("res://src/ui/Win98Menu.gd")


func test_chain_dims_and_restores_pre_dim_alpha() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var root: Node = Win98MenuClass.new()
	var leaf: Node = Win98MenuClass.new()
	host.add_child(root)
	host.add_child(leaf)
	root.submenu = leaf
	leaf.parent_menu = root
	root.modulate.a = 0.8
	leaf.modulate.a = 1.0
	leaf._set_chain_dim(true)
	assert_almost_eq(root.modulate.a, 0.35, 0.001, "ancestor dims hard — monsters must read through it")
	assert_almost_eq(leaf.modulate.a, 0.65, 0.001, "active target list stays readable")
	leaf._set_chain_dim(false)
	assert_almost_eq(root.modulate.a, 0.8, 0.001, "restore returns the PRE-dim alpha, not 1.0")
	assert_almost_eq(leaf.modulate.a, 1.0, 0.001, "leaf restored")


func test_dim_wired_to_targeting_lifecycle() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")
	assert_gt(src.length(), 1000, "CONTROL: read a real file")
	var vis_on := src.find("_target_highlight.visible = true")
	assert_gt(vis_on, -1)
	assert_true("_set_chain_dim(true)" in src.substr(vis_on, 80), "dim engages when the target highlight shows")
	var cleanup := src.find("func _cleanup_target_highlight")
	assert_true("_set_chain_dim(false)" in src.substr(cleanup, 250), "cleanup restores — covers every close path")


func test_audio_liveness_probe_wired() -> void:
	var sm := FileAccess.get_file_as_string("res://src/audio/SoundManager.gd")
	assert_true("func audio_liveness_check" in sm, "probe exists")
	assert_true("playback position frozen" in sm, "probe names the frozen-mixer class loudly")
	var bs := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_true("SoundManager.audio_liveness_check()" in bs, "probe runs every battle round")
