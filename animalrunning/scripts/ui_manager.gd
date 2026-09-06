class_name UIManager
extends CanvasLayer
## 界面管理器：持有所有菜单类界面并负责它们之间的导航。
## 对局中的 HUD 由 Main 单独管理（它是另一个 CanvasLayer）。

signal start_requested
signal result_replay
signal result_next
signal result_map
signal result_difficulty

var _menu: MainMenu
var _character: CharacterSelect
var _levels: LevelMap
var _difficulty: DifficultySelect
var _result: ResultScreen


func _ready() -> void:
	_menu = MainMenu.new()
	_menu.name = "MainMenu"
	add_child(_menu)

	_character = CharacterSelect.new()
	_character.name = "CharacterSelect"
	add_child(_character)

	_levels = LevelMap.new()
	_levels.name = "LevelMap"
	add_child(_levels)

	_difficulty = DifficultySelect.new()
	_difficulty.name = "DifficultySelect"
	add_child(_difficulty)

	_result = ResultScreen.new()
	_result.name = "ResultScreen"
	add_child(_result)

	_connect()
	hide_all()


func _connect() -> void:
	_menu.start_pressed.connect(show_character)
	_menu.characters_pressed.connect(show_character)
	_menu.levels_pressed.connect(show_level_map)

	_character.back_pressed.connect(show_menu)
	_character.next_pressed.connect(show_level_map)

	_levels.back_pressed.connect(show_menu)
	_levels.level_selected.connect(_on_level_selected)

	_difficulty.back_pressed.connect(show_level_map)
	_difficulty.start_pressed.connect(func() -> void:
		hide_all()
		start_requested.emit())

	_result.replay_pressed.connect(func() -> void: result_replay.emit())
	_result.next_pressed.connect(func() -> void: result_next.emit())
	_result.map_pressed.connect(func() -> void: result_map.emit())
	_result.difficulty_pressed.connect(func() -> void: result_difficulty.emit())


func _on_level_selected(index: int) -> void:
	show_difficulty()


# ---------------------------------------------------------------- 导航
func hide_all() -> void:
	for c in get_children():
		if c is Control:
			(c as Control).visible = false


func show_menu() -> void:
	hide_all()
	_menu.visible = true
	_menu.refresh()


func show_character() -> void:
	hide_all()
	_character.visible = true
	_character._update_selection()


func show_level_map() -> void:
	hide_all()
	_levels.visible = true
	_levels.refresh()


func show_difficulty() -> void:
	hide_all()
	_difficulty.visible = true
	_difficulty.refresh()


func show_result(level_index: int, completed: bool, score: int, coins: int,
		distance: float) -> void:
	hide_all()
	_result.visible = true
	_result.show_result(level_index, completed, score, coins, distance)
