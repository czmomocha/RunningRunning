class_name CharacterSelect
extends Control
## 角色选择：以 3D 预览卡片展示所有方块动物，点击即可切换当前角色。

signal back_pressed
signal next_pressed

const CARD_SIZE := Vector2(300.0, 248.0)
const PREVIEW_SIZE := 104.0

var _cards: Array[Button] = []
var _models: Array[Node3D] = []
var _halo: Array[Panel] = []
var _info: Label
var _time: float = 0.0


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
	root.offset_top = 16.0
	root.offset_bottom = -16.0
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	root.add_child(UiTheme.title("选择你的动物", 38))

	_info = UiTheme.label("", 16, GameConfig.COLOR_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(_info)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 16)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(grid)

	for i in GameConfig.CHARACTERS.size():
		grid.add_child(_make_card(i))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	root.add_child(row)

	var back_btn := UiTheme.button("返回", Color8(0x9a, 0xaa, 0xc4), Vector2(180.0, 54.0), 21, true)
	back_btn.pressed.connect(func() -> void: back_pressed.emit())
	row.add_child(back_btn)

	var next_btn := UiTheme.button("下一步：选择关卡", GameConfig.COLOR_ACCENT,
		Vector2(300.0, 54.0), 22)
	next_btn.pressed.connect(func() -> void: next_pressed.emit())
	row.add_child(next_btn)


func _make_card(index: int) -> Button:
	var ch := GameConfig.character(index)
	var accent: Color = ch["color"]

	var card := Button.new()
	card.custom_minimum_size = CARD_SIZE
	card.clip_contents = true
	card.focus_mode = Control.FOCUS_NONE
	card.add_theme_stylebox_override("normal", UiTheme.card_style(accent, false))
	card.add_theme_stylebox_override("hover", UiTheme.card_style(accent, false, true))
	card.add_theme_stylebox_override("pressed", UiTheme.card_style(accent, true))
	UiTheme.add_sfx(card, "ui_select")
	card.pressed.connect(func() -> void: _select(index))

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_top = 10.0
	box.offset_bottom = -10.0
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)

	# ---------------------------------------------------------- 3D 预览
	var preview := UiTheme.animal_preview(String(ch["file"]), PREVIEW_SIZE, accent)
	var holder := HBoxContainer.new()
	holder.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(preview["root"] as Control)
	box.add_child(holder)
	_models.append(preview["model"] as Node3D)
	_halo.append((preview["root"] as Control).get_child(0) as Panel)

	# ---------------------------------------------------------- 名称 + 标签 + 生命
	var hp := int(ch["hp"])
	var hp_color := GameConfig.COLOR_GOOD if hp > 0 else (
		GameConfig.COLOR_BAD if hp < 0 else GameConfig.COLOR_MUTED)

	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 8)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(UiTheme.label(String(ch["name"]), 23, GameConfig.COLOR_TEXT))
	var tag := UiTheme.chip(String(ch["tag"]), accent)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(tag)
	var hp_chip := UiTheme.chip("生命 %+d" % hp, hp_color)
	hp_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(hp_chip)
	box.add_child(name_row)

	box.add_child(UiTheme.label(String(ch["desc"]), 14, GameConfig.COLOR_MUTED,
		HORIZONTAL_ALIGNMENT_CENTER))

	# ---------------------------------------------------------- 属性条
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 4)
	stats.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stats)

	stats.add_child(UiTheme.stat_bar("速度", _ratio(float(ch["speed"])),
		"%d%%" % int(float(ch["speed"]) * 100.0), GameConfig.COLOR_ACCENT))
	stats.add_child(UiTheme.stat_bar("跳跃", _ratio(float(ch["jump"])),
		"%d%%" % int(float(ch["jump"]) * 100.0), GameConfig.COLOR_INFO))
	stats.add_child(UiTheme.stat_bar("换道", _ratio(float(ch["lane"])),
		"%d%%" % int(float(ch["lane"]) * 100.0), GameConfig.COLOR_GOOD))

	_cards.append(card)
	return card


## 把 0.85 ~ 1.30 的倍率映射到进度条的 0 ~ 1
func _ratio(value: float) -> float:
	return clampf((value - 0.80) / 0.55, 0.06, 1.0)


func _select(index: int) -> void:
	GameState.character_index = index
	GameState.save()
	_update_selection()


func _update_selection() -> void:
	for i in _cards.size():
		var selected := i == GameState.character_index
		var accent: Color = GameConfig.character(i)["color"]
		# 选中一律用金色描边，语义最清晰
		var border: Color = GameConfig.COLOR_ACCENT if selected else accent
		_cards[i].add_theme_stylebox_override("normal", UiTheme.card_style(border, selected))
		_cards[i].add_theme_stylebox_override("hover",
			UiTheme.card_style(border, selected, true))
		if i < _halo.size():
			_halo[i].modulate = Color(1.0, 1.0, 1.0, 1.0 if selected else 0.55)

	var ch := GameConfig.character(GameState.character_index)
	var diff := GameConfig.difficulty(GameState.difficulty_index)
	_info.text = "已选择 %s　·　本局生命 %d 点（%s 基础 %d，角色 %+d）" % [
		ch["name"], GameState.final_hp(), diff["name"],
		int(diff["hp"]), int(ch["hp"])]


func _process(delta: float) -> void:
	# 选中的动物缓慢转身展示，其余保持 3/4 视角轻微摆动
	_time += delta
	for i in _models.size():
		if i == GameState.character_index:
			_models[i].rotation.y += delta * 0.9
		else:
			_models[i].rotation.y = deg_to_rad(28.0) + sin(_time * 0.8 + float(i)) * 0.18
