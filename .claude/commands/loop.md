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
17. DONE — Removed dead parallel save system (`save_game`/`load_game`/`get_save_list`/`delete_save`). Kept rewind infrastructure (used by BattleManager) and macro_volatility (used by VolatilitySystem).

### Tier 4: Performance
18. DONE — `_check_danger_music` already removed/refactored in earlier work.
19. DONE — AreaTransition queue_redraw throttled to every 0.1s instead of every frame.
20. SKIPPED — _process_idle_animations already guards with is_instance_valid, O(n) over 8 sprites, not a hotspot.
21. TODO — CRT scanline ColorRects are one-time spawn cost, not per-frame. Shader replacement deferred.
22. DONE — `_update_encounter_zone` now skips when player hasn't moved to a new tile (`_last_tile_pos` guard).

### Tier 5: Polish
23. DONE — `_generate_double_blip()` fixed: added missing `push_frame()` call and fixed integer division.
24. DONE — Mode 7 overlay sprite position now viewport-relative (`viewport_size / 2, viewport_size * 0.75`).
25. DONE — SettingsMenu changed from runtime `load()` to `preload()` class constant.
26. DONE — `equip_passive` now calls `can_equip_passive` as gate instead of duplicating logic.
27. DONE — `_serialize_inventory` stub marked with proper TODO.
28. TODO — Autogrind duplicate `_input` handlers are short and harmless, base class extraction deferred.
29. DONE — Deleted 6 redundant `gen_fighter_walk*.py` scripts, kept `gen_fighter_walk_release.py`.

## Rules
- Fix ONE item per cycle (or a small related cluster)
- Validate with `godot --headless --import` after every change
- Run tests if touching battle/combat code: `godot --headless -s test/run_tests.gd`
- Add regression test for any bug fix
- Mark completed items as DONE in this file
- Report: what was fixed, what's next, total remaining count
