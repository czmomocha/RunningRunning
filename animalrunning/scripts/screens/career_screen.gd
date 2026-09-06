class_name CareerScreen
extends Control
## 生涯界面：左侧为生涯统计（总里程 / 总局数 / 总方块 / 最远单局 / 各关通关次数），
## 右侧为成就列表（含进度条）。数据全部来自 GameState 的存档字段。

signal back_pressed

var _stat_box: VBoxContainer
var _ach_box: VBoxContainer
var _ach_count: Label
var _coins_label: Label


func _ready() -> void:
	_build()
	refresh()


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiTheme.add_background(self)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 46.0
	root.offset_right = -46.0
	root.offset_top = 20.0
	root.offset_bottom = -18.0
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	root.add_child(header)

	var back_btn := UiTheme.button("返回", Color8(0x9a, 0xaa, 0xc4), Vector2(150.0, 46.0), 18, true)
	back_btn.pressed.connect(func() -> void: back_pressed.emit())
	header.add_child(back_btn)

	var title := UiTheme.title("生涯", 36)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(150.0, 0.0)
	header.add_child(spacer)

	_coins_label = UiTheme.label("", 18, GameConfig.COLOR_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(_coins_label)

	# ---------------------------------------------------------- 左右两栏
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)

	# 左：生涯统计
	var left_panel := UiTheme.panel(GameConfig.COLOR_PANEL, 18, GameConfig.COLOR_LINE, 2, 8)
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left_panel)

	var left_inner := VBoxContainer.new()
	left_inner.add_theme_constant_override("separation", 10)
	left_panel.add_child(left_inner)

	left_inner.add_child(UiTheme.label("生涯统计", 24, GameConfig.COLOR_TEXT))
	_stat_box = VBoxContainer.new()
	_stat_box.add_theme_constant_override("separation", 8)
	left_inner.add_child(_stat_box)

	# 右：成就列表（可滚动）
	var right_panel := UiTheme.panel(GameConfig.COLOR_PANEL, 18, GameConfig.COLOR_LINE, 2, 8)
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right_panel)

	var right_inner := VBoxContainer.new()
	right_inner.add_theme_constant_override("separation", 10)
	right_panel.add_child(right_inner)

	var ach_header := HBoxContainer.new()
	ach_header.add_theme_constant_override("separation", 12)
	right_inner.add_child(ach_header)
	var ach_title := UiTheme.label("成就", 24, GameConfig.COLOR_TEXT)
	ach_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ach_header.add_child(ach_title)
	_ach_count = UiTheme.label("", 18, GameConfig.COLOR_DIM)
	ach_header.add_child(_ach_count)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_inner.add_child(scroll)

	_ach_box = VBoxContainer.new()
	_ach_box.add_theme_constant_override("separation", 8)
	_ach_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_ach_box)


## 每次进入界面时刷新全部数据
func refresh() -> void:
	_coins_label.text = "能量方块：%d　·　在角色界面解锁新动物" % GameState.coins_total

	for c in _stat_box.get_children():
		c.queue_free()
	_stat_box.add_child(_stat_row("总里程", _fmt_distance(GameState.stats_distance)))
	_stat_box.add_child(_stat_row("总局数", "%d 局" % GameState.stats_runs))
	_stat_box.add_child(_stat_row("总能量方块", "%d 个" % GameState.stats_coins))
	_stat_box.add_child(_stat_row("最远单局", _fmt_distance(GameState.stats_best_distance)))
	_stat_box.add_child(_stat_row("无伤通关", "%d 次" % GameState.stats_hitless_clears))

	var sep := Panel.new()
	sep.custom_minimum_size = Vector2(0.0, 2.0)
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = GameConfig.COLOR_LINE
	sep.add_theme_stylebox_override("panel", ssb)
	_stat_box.add_child(sep)

	_stat_box.add_child(UiTheme.label("各关通关次数", 16, GameConfig.COLOR_MUTED))
	for i in GameConfig.LEVELS.size():
		var count := int(GameState.level_clears.get(str(i), 0))
		var lv := GameConfig.level(i)
		_stat_box.add_child(_stat_row(
			"第 %d 关 · %s" % [i + 1, String(lv["name"])],
			"%d 次" % count,
			GameConfig.COLOR_DIM if count == 0 else GameConfig.COLOR_TEXT))

	# ---- 成就列表
	for c in _ach_box.get_children():
		c.queue_free()
	for a in GameConfig.ACHIEVEMENTS:
		_ach_box.add_child(_ach_row(a))

	_ach_count.text = "%d / %d" % [GameState.achievement_count(),
		GameConfig.ACHIEVEMENTS.size()]


## 一行统计：左标题 右数值
func _stat_row(name_text: String, value_text: String,
		color: Color = GameConfig.COLOR_TEXT) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := UiTheme.label(name_text, 17, GameConfig.COLOR_MUTED)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(n)
	var v := UiTheme.label(value_text, 18, color, HORIZONTAL_ALIGNMENT_RIGHT)
	row.add_child(v)
	return row


## 一条成就：名称 + 条件 + 进度（已达成则高亮）
func _ach_row(a: Dictionary) -> Control:
	var id := String(a["id"])
	var done := GameState.achievements.has(id)
	var current: float = minf(GameState.achievement_progress(id), float(a["goal"]))
	var goal: float = float(a["goal"])
	var accent: Color = GameConfig.COLOR_ACCENT if done else GameConfig.COLOR_INFO

	var panel := UiTheme.panel(
		GameConfig.COLOR_CARD if not done else GameConfig.COLOR_CARD_SELECTED, 14,
		GameConfig.COLOR_ACCENT if done else GameConfig.COLOR_LINE, 2 if done else 1)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var title_row := HBoxContainer.new()
	box.add_child(title_row)
	var name_label := UiTheme.label(String(a["name"]), 18,
		GameConfig.COLOR_ACCENT if done else GameConfig.COLOR_TEXT)
	title_row.add_child(name_label)
	var status := UiTheme.label("已达成" if done else "", 14, GameConfig.COLOR_GOOD)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_row.add_child(status)

	box.add_child(UiTheme.label(String(a["desc"]), 13, GameConfig.COLOR_MUTED))

	var unit := String(a.get("unit", ""))
	var cur_text := _fmt_progress(id, current) if unit == "m" else "%d" % int(current)
	var goal_text := _fmt_progress(id, goal) if unit == "m" else "%d" % int(goal)
	box.add_child(UiTheme.stat_bar("进度", current / maxf(goal, 1.0),
		"%s / %s" % [cur_text, goal_text], accent, 120.0))

	return panel


## 米数超过 1000 时换算成 km 显示
func _fmt_distance(meters: float) -> String:
	if meters >= 1000.0:
		return "%.2f km" % (meters / 1000.0)
	return "%d m" % int(meters)


## 成就进度里距离类数值的显示（10 km / 50 km / 1000 m / 2000 m）
func _fmt_progress(id: String, value: float) -> String:
	if id in ["dist_10km", "dist_50km"]:
		return "%.0f km" % (value / 1000.0)
	return "%d m" % int(value)
