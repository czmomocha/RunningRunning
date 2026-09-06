class_name MainMenu
extends Control
## 主菜单：标题、当前阵容展示（3D 预览）、入口按钮与操作说明。

signal start_pressed
signal characters_pressed
signal levels_pressed

var _summary: Label
var _preview_slot: Control
var _preview_name: Label
var _preview_tag: Label
var _model: Node3D
var _sound_btn: Button
var _shown_index: int = -1
var _time: float = 0.0


func _ready() -> void:
	_build()


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiTheme.add_background(self)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 90.0
	row.offset_right = -90.0
	row.offset_top = 70.0
	row.offset_bottom = -90.0
	row.add_theme_constant_override("separation", 40)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(row)

	# ---------------------------------------------------------- 左：标题与按钮
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.add_theme_constant_override("separation", 10)
	row.add_child(left)

	var title := UiTheme.title("方块动物 · 大逃亡", 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	left.add_child(title)

	var sub := UiTheme.label("选择你的动物，在无限赛道上甩开追兵", 20, GameConfig.COLOR_DIM)
	left.add_child(sub)

	var line := Panel.new()
	line.custom_minimum_size = Vector2(0.0, 3.0)
	var line_sb := StyleBoxFlat.new()
	line_sb.bg_color = Color(GameConfig.COLOR_ACCENT.r, GameConfig.COLOR_ACCENT.g,
		GameConfig.COLOR_ACCENT.b, 0.55)
	line_sb.set_corner_radius_all(2)
	line.add_theme_stylebox_override("panel", line_sb)
	line.custom_minimum_size = Vector2(220.0, 3.0)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(line)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 14.0)
	left.add_child(gap)

	_summary = UiTheme.label("", 18, GameConfig.COLOR_DIM)
	left.add_child(_summary)

	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0.0, 18.0)
	left.add_child(gap2)

	var start_btn := UiTheme.button("开始游戏", GameConfig.COLOR_ACCENT, Vector2(340.0, 64.0), 26)
	start_btn.pressed.connect(func() -> void: start_pressed.emit())
	left.add_child(_left(start_btn))

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 14)
	left.add_child(btn_row)

	var char_btn := UiTheme.button("选择角色", GameConfig.COLOR_INFO,
		Vector2(163.0, 52.0), 20, true)
	char_btn.pressed.connect(func() -> void: characters_pressed.emit())
	btn_row.add_child(char_btn)

	var level_btn := UiTheme.button("关卡地图", GameConfig.COLOR_GOOD,
		Vector2(163.0, 52.0), 20, true)
	level_btn.pressed.connect(func() -> void: levels_pressed.emit())
	btn_row.add_child(level_btn)

	# ---------------------------------------------------------- 右：当前角色
	var card := UiTheme.panel(GameConfig.COLOR_PANEL, 24, GameConfig.COLOR_LINE, 2, 10)
	card.custom_minimum_size = Vector2(330.0, 380.0)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(card)

	var card_box := VBoxContainer.new()
	card_box.alignment = BoxContainer.ALIGNMENT_CENTER
	card_box.add_theme_constant_override("separation", 8)
	card.add_child(card_box)

	card_box.add_child(UiTheme.label("当前出战", 15, GameConfig.COLOR_MUTED,
		HORIZONTAL_ALIGNMENT_CENTER))

	_preview_slot = Control.new()
	_preview_slot.custom_minimum_size = Vector2(220.0, 220.0)
	_preview_slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_preview_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_box.add_child(_preview_slot)

	_preview_name = UiTheme.label("", 30, GameConfig.COLOR_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	card_box.add_child(_preview_name)

	_preview_tag = UiTheme.label("", 15, GameConfig.COLOR_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_preview_tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_box.add_child(_preview_tag)

	# ---------------------------------------------------------- 音效开关
	_sound_btn = UiTheme.button("", GameConfig.COLOR_DIM, Vector2(140.0, 42.0), 16, true)
	_sound_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_sound_btn.offset_left = -176.0
	_sound_btn.offset_right = -36.0
	_sound_btn.offset_top = 24.0
	_sound_btn.offset_bottom = 66.0
	_sound_btn.pressed.connect(func() -> void:
		Sfx.toggle_mute()
		_update_sound_btn())
	add_child(_sound_btn)
	_update_sound_btn()

	# ---------------------------------------------------------- 底部操作提示
	var hint := UiTheme.label(
		"← → / A D 换道　　空格 跳跃　　↓ / S 快速下落　　ESC 暂停　　也支持鼠标 / 触屏滑动",
		15, GameConfig.COLOR_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -52.0
	hint.offset_bottom = -22.0
	add_child(hint)

	refresh()


func _update_sound_btn() -> void:
	_sound_btn.text = "音效：关" if Sfx.is_muted() else "音效：开"


func refresh() -> void:
	var ch := GameConfig.character(GameState.character_index)
	var diff := GameConfig.difficulty(GameState.difficulty_index)
	var lv := GameConfig.level(GameState.current_level)
	_summary.text = "难度：%s　·　生命 %d 点\n关卡：第 %d 关 %s　·　已解锁 %d / %d" % [
		diff["name"], GameState.final_hp(),
		GameState.current_level + 1, lv["name"],
		GameState.unlocked_levels, GameConfig.LEVELS.size()]

	if _shown_index != GameState.character_index:
		_shown_index = GameState.character_index
		_rebuild_preview(ch)

	_preview_name.text = String(ch["name"])
	_preview_name.add_theme_color_override("font_color", ch["color"])
	_preview_tag.text = String(ch["desc"])


## 角色变了就重建预览（SubViewport 里的模型无法直接换）
func _rebuild_preview(ch: Dictionary) -> void:
	for c in _preview_slot.get_children():
		c.queue_free()
	var preview := UiTheme.animal_preview(String(ch["file"]), 220.0, ch["color"])
	var root := preview["root"] as Control
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_slot.add_child(root)
	_model = preview["model"] as Node3D


func _left(control: Control) -> Control:
	var holder := HBoxContainer.new()
	holder.alignment = BoxContainer.ALIGNMENT_BEGIN
	holder.add_child(control)
	return holder


func _process(delta: float) -> void:
	if _model != null and is_instance_valid(_model):
		_time += delta
		_model.rotation.y += delta * 0.55
