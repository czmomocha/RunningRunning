class_name DifficultySelect
extends Control
## 难度选择：展示四个难度档位的生命 / 速度 / 障碍密度 / 得分倍率，确认后出发。

signal back_pressed
signal start_pressed

var _cards: Array[Button] = []
var _level_title: Label
var _level_info: Label
var _footer: Label


func _ready() -> void:
	_build()
	_update_selection()


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiTheme.add_background(self)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 46.0
	root.offset_right = -46.0
	root.offset_top = 24.0
	root.offset_bottom = -22.0
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	_level_title = UiTheme.title("", 36)
	root.add_child(_level_title)
	_level_info = UiTheme.label("", 16, GameConfig.COLOR_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(_level_info)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 6.0)
	root.add_child(gap)

	root.add_child(UiTheme.label("选择难度", 22, GameConfig.COLOR_TEXT,
		HORIZONTAL_ALIGNMENT_CENTER))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(row)

	for i in GameConfig.DIFFICULTIES.size():
		row.add_child(_make_card(i))

	_footer = UiTheme.label("", 16, GameConfig.COLOR_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(_footer)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	root.add_child(btn_row)

	var back_btn := UiTheme.button("返回", Color8(0x9a, 0xaa, 0xc4), Vector2(180.0, 54.0), 21, true)
	back_btn.pressed.connect(func() -> void: back_pressed.emit())
	btn_row.add_child(back_btn)

	var start_btn := UiTheme.button("出发！", GameConfig.COLOR_ACCENT, Vector2(260.0, 54.0), 24)
	start_btn.pressed.connect(func() -> void: start_pressed.emit())
	btn_row.add_child(start_btn)


func _make_card(index: int) -> Button:
	var d := GameConfig.difficulty(index)
	var accent: Color = d["color"]

	var card := Button.new()
	card.custom_minimum_size = Vector2(264.0, 296.0)
	card.clip_contents = true
	card.focus_mode = Control.FOCUS_NONE
	card.add_theme_stylebox_override("normal", UiTheme.card_style(accent, false))
	card.add_theme_stylebox_override("hover", UiTheme.card_style(accent, false, true))
	card.add_theme_stylebox_override("pressed", UiTheme.card_style(accent, true))
	UiTheme.add_sfx(card, "ui_select")
	card.pressed.connect(func() -> void: _select(index))

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_top = 14.0
	box.offset_bottom = -14.0
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)

	box.add_child(UiTheme.label(String(d["name"]), 26, accent, HORIZONTAL_ALIGNMENT_CENTER))

	# 生命值用心形方块直观呈现
	var hearts := HBoxContainer.new()
	hearts.alignment = BoxContainer.ALIGNMENT_CENTER
	hearts.add_theme_constant_override("separation", 5)
	hearts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in int(d["hp"]):
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(16.0, 16.0)
		var sb := StyleBoxFlat.new()
		sb.bg_color = GameConfig.COLOR_BAD
		sb.set_corner_radius_all(4)
		pip.add_theme_stylebox_override("panel", sb)
		hearts.add_child(pip)
	hearts.add_child(UiTheme.label("  基础生命 %d" % int(d["hp"]), 14, GameConfig.COLOR_MUTED))
	box.add_child(hearts)

	var desc := UiTheme.label(String(d["desc"]), 14, GameConfig.COLOR_DIM,
		HORIZONTAL_ALIGNMENT_CENTER)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(224.0, 44.0)
	box.add_child(desc)

	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 5)
	stats.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stats)

	stats.add_child(UiTheme.stat_bar("速度", (float(d["speed"]) - 0.7) / 0.75,
		"%.2f×" % float(d["speed"]), GameConfig.COLOR_INFO, 84.0))
	stats.add_child(UiTheme.stat_bar("障碍", (float(d["obstacle"]) - 0.6) / 0.9,
		"%.2f×" % float(d["obstacle"]), GameConfig.COLOR_ACCENT, 84.0))
	stats.add_child(UiTheme.stat_bar("追兵", (float(d["enemy"]) - 0.4) / 1.4,
		"%.2f×" % float(d["enemy"]), GameConfig.COLOR_BAD, 84.0))
	stats.add_child(UiTheme.stat_bar("得分", (float(d["score"]) - 0.5) / 1.8,
		"%.1f×" % float(d["score"]), GameConfig.COLOR_GOOD, 84.0))

	_cards.append(card)
	return card


func _select(index: int) -> void:
	GameState.difficulty_index = index
	GameState.save()
	_update_selection()


## 进入界面时刷新关卡信息与难度卡片
func refresh() -> void:
	if GameConfig.is_infinite(GameState.current_level):
		_level_title.text = "每日挑战" if GameState.current_level == GameConfig.DAILY_LEVEL \
			else "无限模式"
		if GameState.current_level == GameConfig.DAILY_LEVEL:
			_level_info.text = "今日种子 · 全世界同图竞速　·　当前今日最佳：%d" % GameState.get_daily_best()
		else:
			_level_info.text = "没有终点 · 主题每 500 m 轮换　·　看你能跑多远"
	else:
		var lv := GameConfig.level(GameState.current_level)
		_level_title.text = "第 %d 关 · %s" % [GameState.current_level + 1, lv["name"]]
		var traits := GameConfig.theme_traits(String(lv["theme"]))
		_level_info.text = "%s　·　通关距离 %d m　·　路况：%s" % [
			lv["subtitle"], int(lv["distance"]), "、".join(traits)]
	_update_selection()


## 只负责难度卡片的选中态与底部说明（不要在内部调用 refresh，否则会递归）
func _update_selection() -> void:
	for i in _cards.size():
		var selected := i == GameState.difficulty_index
		var accent: Color = GameConfig.difficulty(i)["color"]
		_cards[i].add_theme_stylebox_override("normal", UiTheme.card_style(accent, selected))
		_cards[i].add_theme_stylebox_override("hover",
			UiTheme.card_style(accent, selected, true))

	var d := GameConfig.difficulty(GameState.difficulty_index)
	var ch := GameConfig.character(GameState.character_index)
	_footer.text = "出战：%s　·　本局生命 %d 点（%s 基础 %d，角色 %+d）　·　通关得分 ×%.1f" % [
		ch["name"], GameState.final_hp(), d["name"], int(d["hp"]), int(ch["hp"]),
		float(d["score"])]
