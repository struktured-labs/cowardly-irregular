Self-improvement loop for Cowardly Irregular codebase. Run one cycle per invocation — pick the highest-priority unfixed item, fix it, validate, and report what's left.

## Priority Queue (work top-down, skip items marked DONE)

### Tier 1: Critical Bugs
1. DONE — SaveSystem now finds OverworldPlayer via "player" group instead of nonexistent PlayerController. Player position actually saves now.
2. DONE — Escape emits battle_ended with `"escaped"` result directly instead of calling end_battle(false) defeat path.
3. DONE — `time_distortion` now stores original speed in `_base_speed` metadata on first mutation, reads from it each round instead of compounding.
4. DONE — Double `_get_alive_enemies()` call replaced with single local var.
5. DONE — Summoned enemy signals now use lambda closures that look up index via `test_enemies.find(enemy)` at call time instead of binding stale index.
6. DONE — `pivot_offset = label.size / 2` now deferred with `await get_tree().process_frame` so Control has valid size.

### Tier 2: Dead Code Removal
7. DONE — Removed dead `_start_battle()` sync version, `_show_menu()`/`LoopState.MENU`, `_on_continue_pressed()`, `_load_battle_behind_transition()`, `MenuSceneRes` preload, `_party_customizations` var. Kept autogrind dashboard/overlay/controller overlay (actually used by autogrind system).
8. SKIPPED — Legacy pipeline functions are actually used by `create_default_character_script` and default script builders. Not dead code.
9. DONE — Removed dead `_create_character_sprite`, `_create_enemy_sprite`, `_on_player_hp_changed`, `_on_player_ap_changed` from BattleScene.
10. DONE — Deleted VirtualGamepad.gd (also removed autoload), AdaptiveAI.gd, OverworldInteractable.gd.
11. DONE — Sprite agent already replaced `_try_load_artist_sprites` with `_try_build_artist_sprites` which has no dead walk_frames code.
12. SKIPPED — MapSystem.load_map is called from SaveSystem on game load. Transition functions are partially live.

### Tier 3: Architecture Improvements
13. Extract village base class — 10 village scripts share ~150 lines of identical boilerplate (`_setup_scene`, `_setup_camera`, `_setup_controller`, `_setup_transition_collision`, `spawn_player_at`, `resume`, `pause`, `set_player_job`, `set_player_appearance`). Create `BaseVillage.gd` and refactor.
14. Consolidate border constants — `BORDER_LIGHT`/`BORDER_SHADOW` duplicated in 10+ files. Move to `RetroPanel.gd` as class constants, reference from menus.
15. DONE — Removed dead `apply_retro_theme()`, `generate_bitmap_font_texture()`, `_draw_character()`, `_get_character_patterns()` (~125 lines).
16. DONE — Moved `JOB_DISPLAY_HEIGHTS` from function-level to class-level const.
17. `src/GameState.gd` — Remove or gate dead Time Mage rewind infrastructure, dead `macro_volatility`, dead parallel save system (`save_game`/`load_game`/`get_save_list`/`delete_save`).

### Tier 4: Performance
18. `src/battle/BattleScene.gd` — `_check_danger_music()` runs every frame in `_process`. Move to event-driven (call from `_on_party_hp_changed` only).
19. `src/exploration/AreaTransition.gd` — 11+ instances all call `queue_redraw()` every frame. Use `set_process(false)` when off-screen or use a shared timer.
20. `src/battle/BattleScene.gd` — `_process_idle_animations` calls `is_instance_valid` on every sprite every frame. Cache valid sprite list, update only on spawn/death.
21. `src/ui/autogrind/AutogrindDashboard.gd:176-197` — CRT scanline overlay spawns ~120 ColorRect nodes. Replace with shader or single `_draw()` call.
22. `src/exploration/OverworldScene.gd` — `_update_encounter_zone` tile division runs every frame even when player is still. Add `_last_tile_pos` guard.

### Tier 5: Polish
23. `src/audio/SoundManager.gd:344` — `_generate_double_blip()` never pushes audio frames. Fix or remove.
24. `src/exploration/OverworldScene.gd` — Mode 7 overlay sprite position hardcoded `(640, 400)`. Make viewport-relative.
25. `src/ui/OverworldMenu.gd:639` — Settings menu uses `load()` instead of `preload()`. Change to preload.
26. `src/jobs/PassiveSystem.gd:341` — `can_equip_passive` restriction check never called. Wire into `equip_passive`.
27. `src/save/SaveSystem.gd:331` — `_serialize_inventory` is a stub. Implement or document as TODO.
28. Consolidate duplicate `_input` handlers in `AutogrindMonitor.gd` and `AutogrindDashboard.gd` into shared base/utility.
29. Delete redundant sprite gen scripts in `tools/` (keep only `gen_fighter_walk_release.py`, remove 6 others).

## Rules
- Fix ONE item per cycle (or a small related cluster)
- Validate with `godot --headless --import` after every change
- Run tests if touching battle/combat code: `godot --headless -s test/run_tests.gd`
- Add regression test for any bug fix
- Mark completed items as DONE in this file
- Report: what was fixed, what's next, total remaining count
