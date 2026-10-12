extends GutTest

## A live engine error from struktured's 2026-10-12 session (headed GPU, 23 battles), handed over by
## @cowir-battle with their own lead marked weak:
##
##     [SFX] surprised_chime -> surprised_chime pitch=0.97 (UIPlayer)
##     ERROR: Can't change this state while flushing queries. Use call_deferred() or
##            set_deferred() to change monitoring state instead.
##        at: area_set_shape_disabled (godot_physics_server_2d.cpp:355)
##
## `surprised_chime` is played in exactly one place — `DungeonPuzzleLayer.activate_switch`'s TRAP
## branch — which is what located this. `activate_switch` calls `rebuild_floor`, which calls
## `_spawn_portals` and `_spawn_switches`, and both construct `Area2D`s with collision shapes.
## Building an area's shape while the physics server is flushing queries is exactly the error.
##
## 🔑 ONE-SIBLING-FIX, AND THE SURVIVING COMMENT INDEXES IT. The PRESSURE PLATE path was found and
## fixed — `:323 activate_switch.call_deferred(sw_id)  # rebuild_floor adds areas; never during a
## physics flush` — and the LEVER path, the only other caller, was left synchronous. `interact()` is
## dispatched by `OverworldController` immediately after its `intersect_point` query, so the lever
## ran the whole rebuild inside that window. Same defect, same file, one line apart in intent.
##
## ⚠️ THE ARM BELOW IS DERIVED, NOT A LIST OF THE TWO KNOWN CALLERS. The bug was that a second
## caller existed; a guard naming plate-and-lever would be green on the third one. It finds every
## call of `activate_switch` outside its own definition and requires each to be deferred — so a new
## trigger type is covered on arrival rather than after the next session log.
##
## 📌 Two hypotheses died before this one, recorded so nobody re-walks them: `RoamingMonster`'s two
## non-deferred `_collision.disabled` writes (@cowir-battle's lead — real smell, but both are driven
## from `_process`, not a flush), and `RoamingMonster._begin_fade` reached from `body_entered`, which
## sets two floats and touches no physics state at all.

const PUZZLE_FILE := "res://src/exploration/DungeonPuzzleLayer.gd"


func _source() -> String:
	var src := FileAccess.get_file_as_string(PUZZLE_FILE)
	assert_ne(src, "", "CONTROL: DungeonPuzzleLayer.gd must be readable or every arm here is vacuous")
	return src


## Every line that CALLS activate_switch, excluding its own `func` declaration.
func _call_sites() -> Array:
	var out: Array = []
	var lines := _source().split("\n")
	for i in range(lines.size()):
		var line: String = str(lines[i])
		if not line.contains("activate_switch"):
			continue
		if line.strip_edges().begins_with("func "):
			continue
		if line.strip_edges().begins_with("#"):
			continue
		out.append("%d: %s" % [i + 1, line.strip_edges()])
	return out


func test_the_call_sites_are_found() -> void:
	var sites := _call_sites()
	assert_gte(sites.size(), 2,
		"CONTROL: found %d call sites of activate_switch — the plate and the lever both exist, so a " % sites.size() +
		"smaller number means the scan is broken and the arm below is free: %s" % str(sites))
	gut.p("  activate_switch call sites (%d):" % sites.size())
	for s in sites:
		gut.p("    %s" % s)


## The load-bearing arm. Every caller must defer, because the callee builds Area2D shapes.
func test_every_switch_activation_is_deferred() -> void:
	var sync: Array = []
	for site in _call_sites():
		if not str(site).contains("activate_switch.call_deferred"):
			sync.append(str(site))
	assert_eq(sync, [],
		"a switch activation runs SYNCHRONOUSLY, and activate_switch -> rebuild_floor builds Area2D " +
		"shapes: from a body_entered handler or an interact() dispatched after an intersect_point " +
		"query that errors with 'Can't change this state while flushing queries'. Defer it like " +
		"the plate at :323 does: %s" % ", ".join(sync))


## The callee really does build areas — if it ever stopped, this guard would be defending nothing
## and should be deleted rather than left as decoration.
func test_the_rebuild_still_builds_areas() -> void:
	var src := _source()
	var at := src.find("func rebuild_floor")
	assert_gt(at, -1, "rebuild_floor must exist")
	var end := src.find("\nfunc ", at + 10)
	assert_gt(end, at, "CONTROL: rebuild_floor ends before the next function")
	var body := src.substr(at, end - at)
	var spawns := body.contains("_spawn_portals") and body.contains("_spawn_switches")
	assert_true(spawns, "rebuild_floor must still reach the spawners, or this guard defends nothing")
	assert_true(src.contains("Area2D.new()"),
		"the spawners must still construct Area2Ds — that construction is why deferring is required")


## The trap branch is what put the chime next to the error in his log, and it is the branch that
## reaches the rebuild. If the chime moves, the next reader loses the thread that located this.
func test_the_trap_branch_still_announces_itself() -> void:
	var src := _source()
	assert_true(src.contains("surprised_chime"),
		"the trap cue is the only thing that located this error in a 23-battle log; keep it or " +
		"leave a note where it went")
