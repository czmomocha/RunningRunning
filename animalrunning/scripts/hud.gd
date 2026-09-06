class_name HUD
extends CanvasLayer
## 对局界面：分数 / 能量方块 / 速度 / 生命 / 关卡进度 / 小地图 / 暂停。
##
## 叠在 3D 画面之上，因此所有文字都放在半透明深色胶囊里 + 轻描边，
## 无论跑到雪原（亮）还是熔岩（暗）都能看清。

signal pause_requested
signal quit_requested
signal restart_requested
## 视角切换（D8）：按下后请求世界切换第一 / 第三人称
signal view_toggle_requested
## 复活（C4）：玩家选择续关 / 放弃继续
signal revive_requested
signal revive_declined

var _world: World
var _font: Font

var _score_label: Label
var _coin_label: Label
var _combo_label: Label
var _heal_bar: ProgressBar
var _heal_fill: StyleBoxFlat
var _heal_label: Label
var _trait_label: Label
var _level_label: Label
var _sub_label: Label
var _progress_label: Label
var _speed_label: Label
var _pause_layer: Control
var _pause_dim: ColorRect
var _sound_btn: Button
var _view_btn: Button
var _hp_row: HBoxContainer
var _hp_cells: Array[Panel] = []
var _minimap: MiniMap
var _damage_flash: ColorRect
var _hp_warning := false
## 道具状态标签（B2）：id -> Label
var _powerup_labels: Dictionary = {}
## 复活提示面板（C4）
var _revive_layer: Control
var _revive_info: Label
var _revive_time: Label
var _revive_left: float = 0.0


func setup(world: World) -> void:
	_world = world
	_font = UiTheme.body_font()
	_build_ui()
	# 无限模式：主题段切换时刷新关卡名与路况（B1）
	world.stage_changed.connect(_on_stage_changed)


## 无限模式切主题段时更新中央信息
func _on_stage_changed() -> void:
	if _world == null:
		return
	_level_label.text = _world.level_name
	_sub_label.text = _world.level_subtitle
	_trait_label.text = "　·　".join(GameConfig.theme_traits(_world.level_theme))


func _build_ui() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# ---------------------------------------------------------- 顶部信息条
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 24.0
	top.offset_top = 18.0
	top.offset_right = -24.0
	top.offset_bottom = 118.0
	top.add_theme_constant_override("separation", 14)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)

	# 左：得分 + 能量方块
	var left_panel := _pill()
	left_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(left_panel)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 0)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_panel.add_child(left)

	_score_label = _label("0", 40, GameConfig.COLOR_TEXT)
	left.add_child(_score_label)

	var coin_row := HBoxContainer.new()
	coin_row.add_theme_constant_override("separation", 7)
	coin_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(coin_row)
	var coin_icon := Panel.new()
	coin_icon.custom_minimum_size = Vector2(14.0, 14.0)
	coin_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cs := StyleBoxFlat.new()
	cs.bg_color = GameConfig.COLOR_ACCENT
	cs.set_corner_radius_all(4)
	coin_icon.add_theme_stylebox_override("panel", cs)
	coin_row.add_child(coin_icon)
	_coin_label = _label("0", 19, GameConfig.COLOR_ACCENT)
	coin_row.add_child(_coin_label)

	# 连击（B3）：连击 ≥2 时显示，随等级变色
	_combo_label = _label("", 19, GameConfig.COLOR_INFO)
	_combo_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin_row.add_child(_combo_label)

	# ---------------------------------------------------------- 回血进度
	# 「吃满 25 个方块回 1 血」原本是隐藏机制，这里显式呈现出来
	var heal_row := HBoxContainer.new()
	heal_row.add_theme_constant_override("separation", 6)
	heal_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(heal_row)

	_heal_bar = ProgressBar.new()
	_heal_bar.custom_minimum_size = Vector2(104.0, 7.0)
	_heal_bar.show_percentage = false
	_heal_bar.min_value = 0.0
	_heal_bar.max_value = 1.0
	_heal_bar.value = 0.0
	_heal_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_heal_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hbg := StyleBoxFlat.new()
	hbg.bg_color = Color8(0x0c, 0x12, 0x22, 210)
	hbg.set_corner_radius_all(4)
	_heal_fill = StyleBoxFlat.new()
	_heal_fill.bg_color = GameConfig.COLOR_GOOD
	_heal_fill.set_corner_radius_all(4)
	_heal_bar.add_theme_stylebox_override("background", hbg)
	_heal_bar.add_theme_stylebox_override("fill", _heal_fill)
	heal_row.add_child(_heal_bar)

	_heal_label = _label("", 13, GameConfig.COLOR_GOOD)
	_heal_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heal_row.add_child(_heal_label)

	# ---------------------------------------------------------- 道具状态（B2）
	# 激活中的道具：名称 + 剩余时间；护盾为常驻（无时限）
	var powerup_row := HBoxContainer.new()
	powerup_row.add_theme_constant_override("separation", 10)
	powerup_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(powerup_row)
	for id in GameConfig.POWERUPS.keys():
		var l := _label("", 13, GameConfig.powerup(String(id))["color"])
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		powerup_row.add_child(l)
		_powerup_labels[String(id)] = l

	# 中：关卡名
	var mid_holder := Control.new()
	mid_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(mid_holder)

	var center_panel := _pill()
	center_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	center_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mid_holder.add_child(center_panel)

	var center := VBoxContainer.new()
	center.add_theme_constant_override("separation", 0)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_panel.add_child(center)
	_level_label = _label("关卡", 22, GameConfig.COLOR_ACCENT)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_level_label)
	_sub_label = _label("", 14, GameConfig.COLOR_DIM)
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_sub_label)

	# 本关路况特性（地面湿滑 / 强逆风 / 裂谷…），阵风来袭时会高亮
	_trait_label = _label("", 13, GameConfig.COLOR_INFO)
	_trait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_trait_label)

	# 右：进度 + 速度
	var right_panel := _pill()
	right_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(right_panel)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 0)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_panel.add_child(right)
	_progress_label = _label("0 / 0 m", 22, GameConfig.COLOR_TEXT)
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_progress_label)
	_speed_label = _label("0 km/h", 18, GameConfig.COLOR_INFO)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_speed_label)

	# 视角切换（D8）：按钮文字提示「按下后会切到哪个视角」，键盘 V 同效
	_view_btn = UiTheme.button("第一人称", GameConfig.COLOR_INFO, Vector2(118.0, 52.0), 16)
	_view_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_view_btn.tooltip_text = "切换第一 / 第三人称 (V)"
	_view_btn.pressed.connect(func() -> void: view_toggle_requested.emit())
	top.add_child(_view_btn)

	# 暂停按钮
	var pause_btn := UiTheme.button("❚❚", GameConfig.COLOR_ACCENT, Vector2(52.0, 52.0), 18)
	pause_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pause_btn.tooltip_text = "暂停 (ESC)"
	pause_btn.pressed.connect(func() -> void: pause_requested.emit())
	top.add_child(pause_btn)

	# ---------------------------------------------------------- 生命值
	_hp_row = HBoxContainer.new()
	_hp_row.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hp_row.offset_left = 28.0
	# 左上信息面板已有 得分/方块/回血/道具 四行，血条要相应下移避免重叠
	_hp_row.offset_top = 180.0
	_hp_row.add_theme_constant_override("separation", 8)
	_hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hp_row)

	# ---------------------------------------------------------- 小地图
	var map_holder := Control.new()
	map_holder.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	map_holder.offset_top = -104.0
	map_holder.offset_bottom = -24.0
	map_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(map_holder)

	var map_panel := _pill(Color8(0x0a, 0x10, 0x1e, 170), 22)
	map_panel.set_anchors_preset(Control.PRESET_CENTER)
	map_panel.offset_left = -330.0
	map_panel.offset_right = 330.0
	map_panel.offset_top = -40.0
	map_panel.offset_bottom = 40.0
	map_holder.add_child(map_panel)

	_minimap = MiniMap.new()
	_minimap.custom_minimum_size = Vector2(600.0, 56.0)
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_panel.add_child(_minimap)

	# ---------------------------------------------------------- 暂停面板
	_pause_layer = Control.new()
	_pause_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_layer.visible = false
	root.add_child(_pause_layer)

	_pause_dim = ColorRect.new()
	_pause_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_dim.color = Color8(0x05, 0x09, 0x12, 190)
	# 拦截点击，避免误触到下面的东西
	_pause_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_layer.add_child(_pause_dim)

	var pause_panel := UiTheme.panel(GameConfig.COLOR_PANEL, 22, GameConfig.COLOR_ACCENT, 3, 18)
	pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_panel.offset_left = -190.0
	pause_panel.offset_right = 190.0
	pause_panel.offset_top = -185.0
	pause_panel.offset_bottom = 185.0
	_pause_layer.add_child(pause_panel)

	var pause_box := VBoxContainer.new()
	pause_box.alignment = BoxContainer.ALIGNMENT_CENTER
	pause_box.add_theme_constant_override("separation", 12)
	pause_panel.add_child(pause_box)

	pause_box.add_child(UiTheme.title("已暂停", 34))
	pause_box.add_child(UiTheme.label("深呼吸，追兵也在等你", 15, GameConfig.COLOR_MUTED,
		HORIZONTAL_ALIGNMENT_CENTER))

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 8.0)
	pause_box.add_child(gap)

	var resume_btn := UiTheme.button("继续游戏 (ESC)", GameConfig.COLOR_ACCENT,
		Vector2(300.0, 54.0), 22)
	resume_btn.pressed.connect(func() -> void: pause_requested.emit())
	pause_box.add_child(resume_btn)

	var restart_btn := UiTheme.button("重新开始", GameConfig.COLOR_INFO,
		Vector2(300.0, 48.0), 19, true)
	restart_btn.pressed.connect(func() -> void: restart_requested.emit())
	pause_box.add_child(restart_btn)

	_sound_btn = UiTheme.button("", GameConfig.COLOR_DIM, Vector2(300.0, 44.0), 17, true)
	_sound_btn.pressed.connect(func() -> void:
		Sfx.toggle_mute()
		_update_sound_btn())
	pause_box.add_child(_sound_btn)
	_update_sound_btn()

	var quit_btn := UiTheme.button("放弃本局", GameConfig.COLOR_BAD,
		Vector2(300.0, 48.0), 19, true)
	quit_btn.pressed.connect(func() -> void: quit_requested.emit())
	pause_box.add_child(quit_btn)

	# ---------------------------------------------------------- 复活提示（C4）
	# 被追上后先问一句要不要续命，再决定进结算，避免「手滑死了就白跑一局」
	_revive_layer = Control.new()
	_revive_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_revive_layer.visible = false
	root.add_child(_revive_layer)

	var rdim := ColorRect.new()
	rdim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rdim.color = Color8(0x05, 0x09, 0x12, 170)
	rdim.mouse_filter = Control.MOUSE_FILTER_STOP
	_revive_layer.add_child(rdim)

	var rpanel := UiTheme.panel(GameConfig.COLOR_PANEL, 22, GameConfig.COLOR_ACCENT, 3, 18)
	rpanel.set_anchors_preset(Control.PRESET_CENTER)
	rpanel.offset_left = -235.0
	rpanel.offset_right = 235.0
	rpanel.offset_top = -165.0
	rpanel.offset_bottom = 165.0
	_revive_layer.add_child(rpanel)

	var rbox := VBoxContainer.new()
	rbox.alignment = BoxContainer.ALIGNMENT_CENTER
	rbox.add_theme_constant_override("separation", 12)
	rpanel.add_child(rbox)

	rbox.add_child(UiTheme.title("被追上了！", 34))
	rbox.add_child(UiTheme.label("还想再跑一段吗？", 15, GameConfig.COLOR_MUTED,
		HORIZONTAL_ALIGNMENT_CENTER))

	var rgap := Control.new()
	rgap.custom_minimum_size = Vector2(0.0, 4.0)
	rbox.add_child(rgap)

	_revive_info = UiTheme.label("", 17, GameConfig.COLOR_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_revive_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rbox.add_child(_revive_info)

	_revive_time = UiTheme.label("", 26, GameConfig.COLOR_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	rbox.add_child(_revive_time)

	var rbtn_row := HBoxContainer.new()
	rbtn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	rbtn_row.add_theme_constant_override("separation", 12)
	rbox.add_child(rbtn_row)

	var revive_btn := UiTheme.button("原地复活 (R)", GameConfig.COLOR_GOOD,
		Vector2(186.0, 54.0), 20)
	revive_btn.pressed.connect(func() -> void: revive_requested.emit())
	rbtn_row.add_child(revive_btn)

	var giveup_btn := UiTheme.button("就此结束 (ESC)", GameConfig.COLOR_BAD,
		Vector2(158.0, 54.0), 17, true)
	giveup_btn.pressed.connect(func() -> void: revive_declined.emit())
	rbtn_row.add_child(giveup_btn)

	# ---------------------------------------------------------- 受击闪红
	_damage_flash = ColorRect.new()
	_damage_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_damage_flash.color = GameConfig.COLOR_BAD
	_damage_flash.modulate.a = 0.0
	_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_damage_flash)


## 半透明深色胶囊：保证 HUD 文字在任何 3D 背景上都清晰
func _pill(bg: Color = Color8(0x0a, 0x10, 0x1e, 160), radius: int = 16) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiTheme.stylebox(bg, radius, Color8(0x6e, 0x82, 0xa8, 70), 1)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


# ================================================================ 对局数据
func begin_run() -> void:
	hide_revive()
	_level_label.text = _world.level_name
	_sub_label.text = _world.level_subtitle
	_trait_label.text = "　·　".join(GameConfig.theme_traits(_world.level_theme))
	set_paused(false)
	set_hp(_world.player.hp, _world.player.max_hp)


func set_hp(hp: int, max_hp: int) -> void:
	_hp_warning = hp == 1
	if _hp_cells.size() != max_hp:
		for c in _hp_cells:
			c.queue_free()
		_hp_cells.clear()
		for i in max_hp:
			var cell := Panel.new()
			cell.custom_minimum_size = Vector2(26.0, 26.0)
			cell.pivot_offset = Vector2(13.0, 13.0)
			_hp_row.add_child(cell)
			_hp_cells.append(cell)

	for i in _hp_cells.size():
		var alive_cell := i < hp
		var cell := _hp_cells[i]
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(7)
		sb.bg_color = GameConfig.COLOR_BAD if alive_cell else Color8(0x1a, 0x22, 0x33, 190)
		sb.set_border_width_all(2)
		sb.border_color = (Color8(0xff, 0xa8, 0xa8) if alive_cell
			else Color8(0x4a, 0x55, 0x6a, 200))
		cell.add_theme_stylebox_override("panel", sb)
		cell.scale = Vector2.ONE if alive_cell else Vector2(0.74, 0.74)


func set_paused(paused: bool) -> void:
	_pause_layer.visible = paused
	if paused:
		_update_sound_btn()


## 同步视角按钮文案（D8）：显示「按下后将切换到」的目标视角
func set_view_mode(first_person: bool) -> void:
	if _view_btn != null:
		_view_btn.text = "第三人称" if first_person else "第一人称"


func _update_sound_btn() -> void:
	if _sound_btn == null:
		return
	_sound_btn.text = "音效：已关闭" if Sfx.is_muted() else "音效：开启"


## 受击时屏幕闪一下红光
func flash_damage() -> void:
	_flash_screen(GameConfig.COLOR_BAD, 0.40)


## 护盾挡下一次伤害（B2）：闪一下青光，与受伤的红色区分开
func flash_shield() -> void:
	_flash_screen(Color8(0x7f, 0xe3, 0xe0), 0.35)


func _flash_screen(color: Color, strength: float) -> void:
	if _damage_flash == null:
		return
	_damage_flash.color = color
	_damage_flash.modulate.a = strength
	var tween := create_tween()
	tween.tween_property(_damage_flash, "modulate:a", 0.0, 0.45)


## 复活倒计时（C4）：时间到视为放弃
func show_revive(cost: int) -> void:
	_revive_left = GameConfig.REVIVE_COUNTDOWN
	_revive_info.text = "消耗 %d 能量方块，原地满血继续（当前拥有 %d 个）" % [
		cost, GameState.coins_total]
	_revive_time.text = "%.0f s" % _revive_left
	_revive_layer.visible = true


func hide_revive() -> void:
	_revive_left = 0.0
	_revive_layer.visible = false


func is_revive_pending() -> bool:
	return _revive_layer.visible


func _update_revive(delta: float) -> void:
	if not _revive_layer.visible:
		return
	_revive_left -= delta
	if _revive_left <= 0.0:
		hide_revive()
		revive_declined.emit()
		return
	_revive_time.text = "%.1f s" % _revive_left


func _process(delta: float) -> void:
	_update_revive(delta)
	if _world == null:
		return

	# 生命只剩 1 点时血条持续脉动示警
	if _hp_warning:
		var a := 0.45 + 0.55 * absf(sin(Time.get_ticks_msec() * 0.006))
		_hp_row.modulate = Color(1.0, 1.0, 1.0, a)
	else:
		_hp_row.modulate = Color.WHITE

	_score_label.text = "%d" % _world.score
	_coin_label.text = "%d" % _world.coins
	_progress_label.text = "%d m" % int(_world.distance) if _world.infinite \
		else "%d / %d m" % [int(_world.distance), int(_world.target_distance)]
	_speed_label.text = "%.0f km/h" % (_world.speed * 3.6)

	# 连击（B3）：≥2 级才显示；等级越高越亮，倒计时结束自动消失
	if _world.combo >= 2:
		var t := clampf(_world.combo / 20.0, 0.0, 1.0)
		var color := Color8(0x7d, 0xc8, 0xff).lerp(GameConfig.COLOR_ACCENT, t)
		_combo_label.text = "×%d" % _world.combo
		_combo_label.add_theme_color_override("font_color", color)
	else:
		_combo_label.text = ""

	# 道具状态（B2）：限时道具显示剩余秒，护盾常驻显示
	for id in _powerup_labels.keys():
		var l: Label = _powerup_labels[id]
		var info := GameConfig.powerup(String(id))
		if id == "shield":
			l.text = "%s ●" % info["name"] if _world.player.shielded else ""
		elif _world.powerup_timers.has(id):
			l.text = "%s %.0fs" % [info["name"], float(_world.powerup_timers[id])]
		else:
			l.text = ""

	# 回血进度：满血时提示「已就绪」，避免玩家以为进度卡住了
	var full := _world.player.hp >= _world.player.max_hp
	var ready := _world.get_heal_remaining() <= 0
	_heal_bar.value = _world.get_heal_progress()
	if ready and full:
		_heal_label.text = "回血就绪"
		_heal_fill.bg_color = GameConfig.COLOR_ACCENT
	else:
		_heal_label.text = "再 %d 个回血" % _world.get_heal_remaining()
		_heal_fill.bg_color = GameConfig.COLOR_GOOD
	_heal_bar.modulate = Color(1.0, 1.0, 1.0, 0.55 if full and not ready else 1.0)

	# 逆风来袭时把路况提示染成警示色并轻微放大
	if _world.wind_factor < 0.94:
		_trait_label.add_theme_color_override("font_color", GameConfig.COLOR_ACCENT)
	else:
		_trait_label.add_theme_color_override("font_color", GameConfig.COLOR_INFO)

	_minimap.progress = _world.get_progress()
	_minimap.enemies = _world.get_enemy_progress()
	_minimap.infinite = _world.infinite
	_minimap.queue_redraw()


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", UiTheme.outline_for(size))
	l.add_theme_color_override("font_outline_color", GameConfig.COLOR_OUTLINE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ================================================================ 小地图
## 横向进度条：起点 -> 玩家 -> 追兵 -> 终点（无限模式终点换为 ∞）
class MiniMap extends Control:
	var progress: float = 0.0
	var enemies: Array[float] = []
	var infinite: bool = false

	const TRACK_H := 12.0
	const PAD := 30.0

	func _draw() -> void:
		var w := size.x - PAD * 2.0
		var y := size.y * 0.5 - 4.0
		var track := Rect2(PAD, y - TRACK_H * 0.5, w, TRACK_H)
		var radius := TRACK_H * 0.5

		# 轨道
		draw_rect(track, Color8(0x10, 0x17, 0x28, 210), true)
		draw_rect(Rect2(track.position.x, track.position.y, track.size.x * progress, TRACK_H),
			GameConfig.COLOR_GOOD, true)
		draw_rect(track, Color8(0x76, 0x88, 0xa8, 150), false, 1.5)

		# 起点 / 终点
		var end_x := PAD + w
		draw_circle(Vector2(PAD, y), 6.0, Color8(0xa8, 0xba, 0xd8))
		if infinite:
			# 无限模式没有终点旗，画一个 ∞
			draw_string(UiTheme.body_font(), Vector2(end_x - 34.0, y + 8.0), "∞",
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 26, GameConfig.COLOR_ACCENT)
		else:
			draw_rect(Rect2(end_x - 2.0, y - 17.0, 4.0, 28.0), GameConfig.COLOR_ACCENT, true)
			draw_rect(Rect2(end_x - 2.0, y - 17.0, 15.0, 10.0), GameConfig.COLOR_ACCENT, true)

		# 追兵
		for p in enemies:
			var ex := PAD + w * clampf(p, 0.0, 1.0)
			draw_circle(Vector2(ex, y), 7.0, Color8(0x2a, 0x10, 0x10, 200))
			draw_circle(Vector2(ex, y), 5.0, GameConfig.COLOR_BAD)

		# 玩家
		var px := PAD + w * clampf(progress, 0.0, 1.0)
		draw_circle(Vector2(px, y), 11.0, Color(GameConfig.COLOR_ACCENT.r,
			GameConfig.COLOR_ACCENT.g, GameConfig.COLOR_ACCENT.b, 0.35))
		draw_circle(Vector2(px, y), 6.5, Color.WHITE)

		# 文字
		var font := UiTheme.body_font()
		draw_string(font, Vector2(PAD - 6.0, y + 27.0), "起点" if not infinite else "",
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, GameConfig.COLOR_MUTED)
		if not infinite:
			draw_string(font, Vector2(end_x - 26.0, y + 27.0), "终点",
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, GameConfig.COLOR_MUTED)
		draw_string(font, Vector2(PAD + w * 0.5 - 22.0, y + 27.0), "%d%%" % int(progress * 100.0),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, GameConfig.COLOR_ACCENT)
