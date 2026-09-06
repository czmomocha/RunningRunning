extends Node
## 游戏总控：连接世界（3D）与界面（UI/HUD），管理 菜单 -> 对局 -> 结算 的状态机。

enum State { MENU, PLAYING, RESULT }

@onready var world: World = $World
@onready var hud: HUD = $HUD
@onready var ui: UIManager = $UI

var _state: State = State.MENU
## 本局受到的伤害次数（成就「无伤通关」判定用）
var _hits_taken: int = 0
## 本局已使用的复活次数（C4）
var _revives_used: int = 0
## 是否正在等待玩家决定「要不要复活」
var _awaiting_revive: bool = false
## 死亡时的成绩快照：复活超时 / 放弃后用它进入结算
var _death_result: Dictionary = {}


func _ready() -> void:
	# 暂停时 SceneTree 会冻结所有「继承 / 可暂停」的节点，
	# 因此总控与界面必须设为 ALWAYS，否则暂停后 ESC 与面板按钮都收不到输入
	#（这正是「点了继续 / 放弃没反应」的原因）；
	# 世界则显式设为 PAUSABLE，保证暂停时 3D 逻辑真的停下。
	process_mode = Node.PROCESS_MODE_ALWAYS
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	world.process_mode = Node.PROCESS_MODE_PAUSABLE

	hud.setup(world)
	hud.visible = false

	world.player.hp_changed.connect(hud.set_hp)
	world.player.hit_taken.connect(hud.flash_damage)
	world.player.shield_blocked.connect(hud.flash_shield)
	world.player.hit_taken.connect(func() -> void: _hits_taken += 1)
	world.player_died.connect(_on_player_died)
	world.level_completed.connect(_on_level_completed)
	hud.pause_requested.connect(_toggle_pause)
	hud.quit_requested.connect(_abandon_run)
	hud.restart_requested.connect(_restart_run)
	hud.revive_requested.connect(_do_revive)
	hud.revive_declined.connect(_decline_revive)
	# 视角切换（D8）：HUD 按钮 / V 键共用同一条链路，按钮文案随状态同步
	hud.view_toggle_requested.connect(_toggle_view)
	world.view_mode_changed.connect(hud.set_view_mode)

	ui.start_requested.connect(_start_game)
	ui.result_replay.connect(_start_game)
	ui.result_next.connect(_next_level)
	ui.result_map.connect(_goto_map)
	ui.result_difficulty.connect(_goto_difficulty)

	_enter_menu()

	# 调试用：命令行附加 --auto-start 可跳过菜单直接开局
	if OS.get_cmdline_args().has("--auto-start"):
		_start_game()


# ---------------------------------------------------------------- 状态切换
func _enter_menu() -> void:
	_state = State.MENU
	get_tree().paused = false
	hud.set_paused(false)
	hud.visible = false
	world.visible = false
	world.running = false
	ui.show_menu()


func _start_game() -> void:
	get_tree().paused = false
	hud.set_paused(false)
	_state = State.PLAYING
	_hits_taken = 0
	_revives_used = 0
	_awaiting_revive = false
	_death_result = {}
	ui.hide_all()

	world.visible = true
	world.start_run(GameState.current_level)

	hud.visible = true
	hud.begin_run()
	Sfx.play("start")


func _goto_map() -> void:
	_enter_menu()
	ui.show_level_map()


func _goto_difficulty() -> void:
	_enter_menu()
	ui.show_difficulty()


func _next_level() -> void:
	if GameState.current_level + 1 < GameConfig.LEVELS.size():
		GameState.current_level += 1
	_start_game()


func _finish(completed: bool, score: int, coins: int, distance: float) -> void:
	_state = State.RESULT
	hud.visible = false
	ui.show_result(GameState.current_level, completed, score, coins, distance, _hits_taken,
		world.trick_score, world.max_combo, _revives_used)


func _on_player_died(score: int, coins: int, distance: float) -> void:
	# 还有复活机会时先问一句，别急着进结算（C4）
	if _revives_used < GameConfig.REVIVE_MAX_PER_RUN and GameState.can_revive():
		_death_result = {"score": score, "coins": coins, "distance": distance}
		_awaiting_revive = true
		hud.show_revive(GameConfig.REVIVE_COST)
		return
	await get_tree().create_timer(0.9).timeout
	_finish(false, score, coins, distance)


## 复活：扣货币后原地继续本局
func _do_revive() -> void:
	if not _awaiting_revive:
		return
	_awaiting_revive = false
	hud.hide_revive()
	if not GameState.spend_revive():
		await get_tree().create_timer(0.3).timeout
		_finish_death()
		return
	_revives_used += 1
	world.revive()


## 放弃复活 / 倒计时结束：照常进结算
func _decline_revive() -> void:
	if not _awaiting_revive:
		return
	_awaiting_revive = false
	hud.hide_revive()
	await get_tree().create_timer(0.35).timeout
	_finish_death()


func _finish_death() -> void:
	_finish(false, int(_death_result.get("score", 0)), int(_death_result.get("coins", 0)),
		float(_death_result.get("distance", 0.0)))


func _on_level_completed(score: int, coins: int, distance: float) -> void:
	await get_tree().create_timer(0.5).timeout
	_finish(true, score, coins, distance)


# ---------------------------------------------------------------- 输入
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed \
			or (event as InputEventKey).echo:
		return
	var key := event as InputEventKey
	var code: int = key.physical_keycode
	if code == KEY_NONE:
		code = key.keycode

	# 复活提示期间（C4）：R 续命、ESC 结束，此时不该再触发暂停
	if _awaiting_revive:
		if code == KEY_R:
			_do_revive()
			get_viewport().set_input_as_handled()
		elif code == KEY_ESCAPE:
			_decline_revive()
			get_viewport().set_input_as_handled()
		return

	# 对局中 V 键切换第一 / 第三人称（D8）
	if code == KEY_V and _state == State.PLAYING and not get_tree().paused:
		_toggle_view()
		get_viewport().set_input_as_handled()

	if code == KEY_ESCAPE:
		_toggle_pause()
		get_viewport().set_input_as_handled()


## 切换第一 / 第三人称（D8）
func _toggle_view() -> void:
	if _state != State.PLAYING:
		return
	world.set_view_mode(not world.first_person)


func _toggle_pause() -> void:
	if _state != State.PLAYING:
		return
	var paused := not get_tree().paused
	get_tree().paused = paused
	hud.set_paused(paused)
	Sfx.play("pause" if paused else "resume")


## 暂停中重开本局
func _restart_run() -> void:
	get_tree().paused = false
	hud.set_paused(false)
	_start_game()


## 中途放弃：取消暂停并回到关卡地图
func _abandon_run() -> void:
	get_tree().paused = false
	hud.set_paused(false)
	_goto_map()
