extends GutTest

## Phase B: hit sparks come from a pooled emitter set, CPU particles BY DESIGN — one code
## path, no WebGL2 first-emission shader-compile hitch, trivial cost at <=20-particle
## bursts. Pins the single-type decision and the pool discipline (one-shot, bounded,
## reused via restart, torn down with the battle context).

func test_pool_is_cpu_particles_single_path() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleJuice.gd")
	assert_gt(src.length(), 1000, "CONTROL: read a real file")
	assert_true("CPUParticles2D.new()" in src, "emitters are CPUParticles2D")
	assert_false("GPUParticles2D.new()" in src, "no GPU branch — a dual path was the buggy draft; one type by design")
	assert_true("one_shot = true" in src, "emitters are one-shot bursts")
	assert_true("BURST_POOL_SIZE" in src, "pool is bounded")
	assert_true("restart()" in src, "emitters are REUSED, not churned")


func test_burst_noop_without_host_and_pool_cleared_on_exit() -> void:
	var prev_host = BattleJuice.burst_host
	BattleJuice.burst_host = null
	BattleJuice.spawn_burst(Vector2.ZERO, Vector2.UP, 12, Color.WHITE)
	assert_eq(BattleJuice._burst_pool.size(), 0, "no host -> no emitters created")
	var host := Node2D.new()
	add_child_autofree(host)
	BattleJuice.burst_host = host
	BattleJuice.spawn_burst(Vector2(10, 10), Vector2.LEFT, 8, Color.RED)
	assert_gt(BattleJuice._burst_pool.size(), 0, "host registered -> emitter pooled")
	BattleJuice.clear_battle_context()
	assert_eq(BattleJuice._burst_pool.size(), 0, "battle teardown clears the pool")
	assert_null(BattleJuice.burst_host, "teardown unregisters the host")
	BattleJuice.burst_host = prev_host


func test_scene_registers_and_clears_context() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_true("BattleJuice.burst_host = self" in src, "BattleScene registers itself as burst host")
	assert_true("BattleJuice.clear_battle_context()" in src, "_exit_tree clears the juice context")
