class_name ResultScreen
extends Control
## 结算界面：展示本局数据、是否刷新纪录、关卡解锁情况，并提供下一步入口。

signal replay_pressed
signal next_pressed
signal map_pressed
signal difficulty_pressed

var _title: Label
var _subtitle: Label
var _rows: VBoxContainer
var _note: Label
var _next_btn: Button
var _banner: Panel


func _ready() -> void:
	_build()


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color8(0x06, 0x0a, 0x14, 214)
	add_child(bg)

	var card := UiTheme.panel(GameConfig.COLOR_PANEL, 24, GameConfig.COLOR_LINE, 2, 16)
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -290.0
	card.offset_right = 290.0
	card.offset_top = -252.0
	card.offset_bottom = 252.0
	add_child(card)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)

	# 顶部色条：胜负一眼可辨
	_banner = Panel.new()
	_banner.custom_minimum_size = Vector2(0.0, 5.0)
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = GameConfig.COLOR_ACCENT
	bsb.set_corner_radius_all(3)
	_banner.add_theme_stylebox_override("panel", bsb)
	box.add_child(_banner)

	_title = UiTheme.title("", 40)
	box.add_child(_title)
	_subtitle = UiTheme.label("", 17, GameConfig.COLOR_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_subtitle)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 6.0)
	box.add_child(gap)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	box.add_child(_rows)

	var gap1 := Control.new()
	gap1.custom_minimum_size = Vector2(0.0, 4.0)
	box.add_child(gap1)

	_note = UiTheme.label("", 16, GameConfig.COLOR_GOOD, HORIZONTAL_ALIGNMENT_CENTER)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(520.0, 44.0)
	box.add_child(_note)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)

	_next_btn = UiTheme.button("下一关", GameConfig.COLOR_GOOD, Vector2(168.0, 52.0), 20)
	_next_btn.pressed.connect(func() -> void: next_pressed.emit())
	row.add_child(_next_btn)

	var replay_btn := UiTheme.button("再来一次", GameConfig.COLOR_ACCENT, Vector2(168.0, 52.0), 20)
	replay_btn.pressed.connect(func() -> void: replay_pressed.emit())
	row.add_child(replay_btn)

	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 12)
	box.add_child(row2)

	var diff_btn := UiTheme.button("换个难度", GameConfig.COLOR_INFO, Vector2(168.0, 46.0), 18, true)
	diff_btn.pressed.connect(func() -> void: difficulty_pressed.emit())
	row2.add_child(diff_btn)

	var map_btn := UiTheme.button("关卡地图", GameConfig.COLOR_GOOD, Vector2(168.0, 46.0), 18, true)
	map_btn.pressed.connect(func() -> void: map_pressed.emit())
	row2.add_child(map_btn)


## 一行数据：左标题 右数值
func _stat_row(name_text: String, value_text: String, color: Color, big := false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := UiTheme.label(name_text, 20 if big else 17, GameConfig.COLOR_MUTED)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(n)
	var v := UiTheme.label(value_text, 24 if big else 18, color, HORIZONTAL_ALIGNMENT_RIGHT)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	return row


## 展示结算数据
func show_result(level_index: int, completed: bool, score: int, coins: int,
		distance: float, hits: int) -> void:
	var lv := GameConfig.level(level_index)
	var diff := GameConfig.difficulty(GameState.difficulty_index)
	var diff_id := String(diff["id"])
	var final_score := GameState.final_score(score)
	var main_color: Color = GameConfig.COLOR_GOOD if completed else GameConfig.COLOR_BAD

	_title.text = "关卡完成！" if completed else "被追上了"
	_title.add_theme_color_override("font_color", main_color)
	(_banner.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = main_color
	_subtitle.text = "第 %d 关 · %s　|　%s　|　%s" % [
		level_index + 1, lv["name"], diff["name"],
		GameConfig.character(GameState.character_index)["name"]]

	# 生涯结算：货币沉淀 + 统计累加 + 成就判定（必须在读取 coins_total 之前调用）
	var new_achievements := GameState.record_run(
		completed, coins, distance, hits, level_index, diff_id)

	for c in _rows.get_children():
		c.queue_free()
	_rows.add_child(_stat_row("跑出距离",
		"%d / %d m" % [int(distance), int(lv["distance"])], GameConfig.COLOR_TEXT))
	_rows.add_child(_stat_row("能量方块", "%d 个" % coins, GameConfig.COLOR_ACCENT))
	_rows.add_child(_stat_row("货币沉淀",
		"+%d（累计 %d）" % [coins, GameState.coins_total], GameConfig.COLOR_ACCENT))
	_rows.add_child(_stat_row("基础得分", str(score), GameConfig.COLOR_TEXT))
	_rows.add_child(_stat_row("难度加成", "×%.1f" % float(diff["score"]), GameConfig.COLOR_INFO))

	var sep := Panel.new()
	sep.custom_minimum_size = Vector2(0.0, 2.0)
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = GameConfig.COLOR_LINE
	sep.add_theme_stylebox_override("panel", ssb)
	_rows.add_child(sep)
	_rows.add_child(_stat_row("最终得分", str(final_score), GameConfig.COLOR_ACCENT, true))

	# 纪录与解锁
	var notes := ""
	var new_record := GameState.record_score(level_index, diff_id, final_score)
	var unlocked_new := false
	if new_record:
		notes += "新纪录！本关最佳成绩已更新"
	else:
		notes += "本关最佳：%d" % GameState.get_best(level_index, diff_id)

	if completed and level_index + 1 < GameConfig.LEVELS.size():
		if not GameState.is_level_unlocked(level_index + 1):
			GameState.unlock_level(level_index + 1)
			unlocked_new = true
			notes += "\n已解锁新关卡：%s！" % GameConfig.level(level_index + 1)["name"]
		else:
			notes += "\n下一关：%s" % GameConfig.level(level_index + 1)["name"]
	elif completed:
		notes += "\n全部关卡通关，恭喜！"

	# 新达成的成就（比关卡解锁更值得庆祝）
	notes += _achievement_notes(new_achievements)

	# 音效优先级：成就 > 关卡解锁 > 破纪录
	if not new_achievements.is_empty():
		_play_stinger("unlock")
	elif unlocked_new:
		_play_stinger("unlock")
	elif new_record:
		_play_stinger("record")

	_note.text = notes
	_note.add_theme_color_override("font_color",
		GameConfig.COLOR_GOOD if completed else GameConfig.COLOR_DIM)

	var has_next := completed and level_index + 1 < GameConfig.LEVELS.size()
	_next_btn.visible = has_next
	_next_btn.disabled = not has_next


## 把新达成的成就拼成提示文字
func _achievement_notes(ids: Array[String]) -> String:
	if ids.is_empty():
		return ""
	var names := []
	for id in ids:
		for a in GameConfig.ACHIEVEMENTS:
			if String(a["id"]) == id:
				names.append("%s（%s）" % [a["name"], a["desc"]])
				break
	return "\n达成成就：%s！" % "、".join(names)


## 稍稍延迟，避免和通关 / 淘汰音叠在一起变成一团
func _play_stinger(sound: String) -> void:
	await get_tree().create_timer(0.35).timeout
	Sfx.play(sound)
