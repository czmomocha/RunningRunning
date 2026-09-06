class_name LevelMap
extends Control
## 关卡地图：以节点路线图展示所有关卡，已通关 / 可挑战 / 未解锁三态。

signal back_pressed
signal level_selected(index: int)

const MAP_SIZE := Vector2(1120.0, 480.0)
const NODE_SIZE := 128.0
## 节点中心坐标（相对地图容器），交错排列形成路线
const CENTERS: Array[Vector2] = [
	Vector2(100.0, 150.0),
	Vector2(284.0, 330.0),
	Vector2(468.0, 150.0),
	Vector2(652.0, 330.0),
	Vector2(836.0, 150.0),
	Vector2(1020.0, 330.0),
]

var _nodes: Array[Button] = []
var _lines: Control
var _hint: Label


func _ready() -> void:
	_build()
	refresh()


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiTheme.add_background(self)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 34.0
	root.offset_right = -34.0
	root.offset_top = 20.0
	root.offset_bottom = -20.0
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)

	var back_btn := UiTheme.button("返回", Color8(0x9a, 0xaa, 0xc4), Vector2(150.0, 46.0), 18, true)
	back_btn.pressed.connect(func() -> void: back_pressed.emit())
	header.add_child(back_btn)

	var title := UiTheme.title("关卡地图", 36)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(150.0, 0.0)
	header.add_child(spacer)

	# ---------------------------------------------------------- 地图主体
	var map_holder := Control.new()
	map_holder.custom_minimum_size = MAP_SIZE
	map_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	map_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(map_holder)

	var map := Control.new()
	map.set_anchors_preset(Control.PRESET_CENTER)
	map.offset_left = -MAP_SIZE.x * 0.5
	map.offset_right = MAP_SIZE.x * 0.5
	map.offset_top = -MAP_SIZE.y * 0.5
	map.offset_bottom = MAP_SIZE.y * 0.5
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_holder.add_child(map)

	_lines = Control.new()
	_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.draw.connect(_draw_lines)
	map.add_child(_lines)

	for i in GameConfig.LEVELS.size():
		var node := UiTheme.node_button("", Color8(0x7e, 0xd9, 0x8d), NODE_SIZE)
		node.position = CENTERS[i] - Vector2(NODE_SIZE * 0.5, NODE_SIZE * 0.5)
		node.pressed.connect(func() -> void: _on_node_pressed(i))
		map.add_child(node)
		_nodes.append(node)

	_hint = UiTheme.label("", 16, GameConfig.COLOR_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(_hint)

	# ---------------------------------------------------------- 无限模式 / 每日挑战（B1）
	var special_row := HBoxContainer.new()
	special_row.alignment = BoxContainer.ALIGNMENT_CENTER
	special_row.add_theme_constant_override("separation", 20)
	root.add_child(special_row)

	var infinite_btn := UiTheme.button("∞ 无限模式", GameConfig.COLOR_INFO,
		Vector2(220.0, 50.0), 19)
	infinite_btn.pressed.connect(func() -> void: _on_special_pressed(GameConfig.INFINITE_LEVEL))
	special_row.add_child(infinite_btn)

	var daily_btn := UiTheme.button("每日挑战", Color8(0xb8, 0xa4, 0xff),
		Vector2(220.0, 50.0), 19)
	daily_btn.pressed.connect(func() -> void: _on_special_pressed(GameConfig.DAILY_LEVEL))
	special_row.add_child(daily_btn)


func refresh() -> void:
	for i in _nodes.size():
		var lv := GameConfig.level(i)
		var unlocked := GameState.is_level_unlocked(i)
		var cleared := i < GameState.unlocked_levels - 1
		var node := _nodes[i]

		node.disabled = not unlocked

		var best := GameState.get_best(i, String(GameConfig.difficulty(GameState.difficulty_index)["id"]))
		var text := "%d\n%s" % [i + 1, lv["name"]]
		if not unlocked:
			text = "第 %d 关\n未解锁" % (i + 1)
		elif cleared:
			text += "\n最佳 %d" % best
		else:
			text += "\n%d m" % int(lv["distance"])
		node.text = text

		var accent: Color
		if not unlocked:
			accent = Color8(0x4a, 0x54, 0x66)
		elif cleared:
			accent = GameConfig.COLOR_GOOD
		else:
			accent = GameConfig.COLOR_ACCENT

		var r := int(NODE_SIZE / 2)
		node.add_theme_stylebox_override("normal",
			UiTheme.stylebox(accent.darkened(0.08), r, accent.lightened(0.3), 4, 10))
		node.add_theme_stylebox_override("hover",
			UiTheme.stylebox(accent.lightened(0.14), r, Color.WHITE, 4, 14))
		node.add_theme_stylebox_override("pressed",
			UiTheme.stylebox(accent.darkened(0.32), r, accent, 4))
		node.add_theme_stylebox_override("disabled",
			UiTheme.stylebox(Color8(0x22, 0x2b, 0x3c), r, Color8(0x35, 0x3f, 0x54), 2))
		node.add_theme_color_override("font_color", UiTheme.ink_for(accent))

	var ch := GameConfig.character(GameState.character_index)
	var diff := GameConfig.difficulty(GameState.difficulty_index)
	_hint.text = "已解锁 %d / %d 关　·　出战：%s　·　难度：%s　·　点击关卡后选择难度出发" % [
		GameState.unlocked_levels, GameConfig.LEVELS.size(), ch["name"], diff["name"]]

	_lines.queue_redraw()


func _draw_lines() -> void:
	for i in CENTERS.size() - 1:
		var done := GameState.is_level_unlocked(i + 1)
		# 底色粗线 + 亮色细线，做出「路线」的层次
		_lines.draw_line(CENTERS[i], CENTERS[i + 1], Color8(0x14, 0x1c, 0x2e, 220), 14.0, true)
		var color := Color8(0x74, 0xdd, 0x9c, 230) if done else Color8(0x3d, 0x49, 0x60, 220)
		_lines.draw_line(CENTERS[i], CENTERS[i + 1], color, 6.0, true)


func _on_node_pressed(index: int) -> void:
	if not GameState.is_level_unlocked(index):
		return
	GameState.current_level = index
	level_selected.emit(index)


## 无限模式 / 每日挑战入口（B1）：负数关卡索引，进难度选择后出发
func _on_special_pressed(level_index: int) -> void:
	GameState.current_level = level_index
	level_selected.emit(level_index)
