extends GutTest

## tick 65: eleventh interior, first in W5 (futuristic). NodePrime
## gets SUDO-1's Daemon Lounge — foreshadows BOTH the RootProcess
## (W5) AND NullChamber (W6) dungeons. Only W5 interior, so it has
## to do double duty.

const LOUNGE := "res://src/maps/interiors/NodePrimeDaemonLoungeInterior.gd"
const NODE_PRIME := "res://src/maps/villages/NodePrimeVillage.gd"
const GAME_LOOP := "res://src/GameLoop.gd"
const TELEPORT_MENU := "res://src/ui/TeleportMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_lounge_extends_base_interior() -> void:
	var src := _read(LOUNGE)
	assert_true(src.contains("extends BaseInterior"),
		"lounge must extend BaseInterior — eleventh interior, abstraction holds")
	assert_true(src.contains("class_name NodePrimeDaemonLoungeInterior"),
		"class_name must exist for GameLoop preload")


func test_lounge_foreshadows_w5_root_and_w6_null() -> void:
	# SUDO-1's lines must reference BOTH dungeons. Single-target
	# interiors are the norm; double-target is intentional for the
	# end-game W5/W6 hand-off.
	var src := _read(LOUNGE)
	assert_true(src.contains("SUDO-1"),
		"lounge must spawn SUDO-1 — the room's payload NPC")
	assert_true(src.contains("Root") and src.contains("Process 1"),
		"SUDO-1 must name 'the Root' AND 'Process 1' — RootProcess (W5) dungeon hook")
	assert_true(src.contains("Null Chamber"),
		"SUDO-1 must name 'the Null Chamber' — NullChamber (W6) dungeon hook")


func test_lounge_uses_terminal_horror_frame() -> void:
	# The unique narrative angle: legitimately-tech jargon + cosmic
	# horror. Pin the 'terminals are listeners' line — it's the
	# room's signature paranoia.
	var src := _read(LOUNGE)
	assert_true(src.contains("LISTENERS") or src.contains("listeners"),
		"SUDO-1 must drop the 'terminals are LISTENERS' line — terminal-horror signature")
	# 'Don't bring a name. It writes you over.' — Null Chamber's
	# erasure threat.
	assert_true(src.contains("don't bring a name") or src.contains("writes you over"),
		"SUDO-1 must warn about bringing a name to the Null Chamber — direct erasure-threat warning")


func test_lounge_exit_returns_to_node_prime() -> void:
	var src := _read(LOUNGE)
	assert_true(src.contains("target_map = \"node_prime_village\""),
		"lounge exit must target node_prime_village")
	assert_true(src.contains("target_spawn = \"daemon_lounge_exit\""),
		"lounge exit must spawn at daemon_lounge_exit")


func test_game_loop_routes_node_prime_daemon_lounge() -> void:
	var src := _read(GAME_LOOP)
	assert_true(src.contains("NodePrimeDaemonLoungeInteriorScript = preload"),
		"GameLoop must preload the lounge script")
	assert_true(src.contains("\"node_prime_daemon_lounge\":"),
		"GameLoop scene routing must include node_prime_daemon_lounge")
	assert_true(src.contains("\"node_prime_daemon_lounge\":\n\t\t\treturn \"futuristic\""),
		"node_prime_daemon_lounge must map to 'futuristic' terrain — W5's battle backdrop")


func test_node_prime_has_door_via_helper() -> void:
	var src := _read(NODE_PRIME)
	assert_true(src.contains("spawn_points[\"daemon_lounge_exit\"]"),
		"NodePrimeVillage must define daemon_lounge_exit return spawn")
	assert_true(src.contains("_add_interior_door(\"DaemonLoungeDoor\", \"node_prime_daemon_lounge\""),
		"lounge door must use the shared _add_interior_door helper from BaseVillage")


func test_teleport_menu_lists_lounge() -> void:
	var src := _read(TELEPORT_MENU)
	assert_true(src.contains("node_prime_daemon_lounge"),
		"TeleportMenu must list node_prime_daemon_lounge")
