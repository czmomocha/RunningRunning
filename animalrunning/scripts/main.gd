extends Node
## 游戏总控：连接世界（3D）与界面（UI/HUD），管理 菜单 -> 对局 -> 结算 的状态机。

enum State { MENU, PLAYING, RESULT }

@onready var world: World = $World
@onready var hud: HUD = $HUD
@onready var ui: UIManager = $UI

var _state: State = State.MENU


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
	world.player_died.connect(_on_player_died)
	world.level_completed.connect(_on_level_completed)
	hud.pause_requested.connect(_toggle_pause)
	hud.quit_requested.connect(_abandon_run)
	hud.restart_requested.connect(_restart_run)

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
	ui.show_result(GameState.current_level, completed, score, coins, distance)


func _on_player_died(score: int, coins: int, distance: float) -> void:
	# 等倒地动画播完再弹结算
	await get_tree().create_timer(0.9).timeout
	_finish(false, score, coins, distance)


func _on_level_completed(score: int, coins: int, distance: float) -> void:
	await get_tree().create_timer(0.5).timeout
	_finish(true, score, coins, distance)


# ---------------------------------------------------------------- 输入
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		var code: int = key.physical_keycode
		if code == KEY_NONE:
			code = key.keycode
		if code == KEY_ESCAPE:
			_toggle_pause()
			get_viewport().set_input_as_handled()


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
