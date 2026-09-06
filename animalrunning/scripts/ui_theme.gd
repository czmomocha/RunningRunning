class_name UiTheme
extends RefCounted
## 界面通用样式：字体、背景、面板、按钮、标签、3D 动物预览。
## 所有界面共用，保证视觉统一。

static var _font: Font
static var _grad: GradientTexture2D


static func body_font() -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray([
			"PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "Noto Sans CJK SC", "Arial"])
		_font = f
	return _font


# ================================================================ 文字
## 界面文字默认不描边：深色底 + 亮色字已经足够清晰，
## 描边只会让 15~18 px 的小字糊成一团（这是之前「看不清」的主因）。
static func label(text: String, size: int, color: Color = GameConfig.COLOR_TEXT,
		align := HORIZONTAL_ALIGNMENT_LEFT, outline: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", body_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", GameConfig.COLOR_OUTLINE)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 大标题：带轻微投影，视觉更有分量
static func title(text: String, size: int = 44,
		color: Color = GameConfig.COLOR_ACCENT) -> Label:
	var l := label(text, size, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.add_theme_constant_override("shadow_outline_size", 2)
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
	return l


## 叠在 3D 画面上的文字（HUD）才需要描边
static func outline_for(size: int) -> int:
	return clampi(int(round(float(size) / 16.0)), 2, 5)


# ================================================================ 面板 / 卡片
static func stylebox(bg: Color, radius: int = 14, border_color: Color = Color.TRANSPARENT,
		border_width: int = 0, shadow: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border_width > 0:
		sb.set_border_width_all(border_width)
		sb.border_color = border_color
		sb.border_blend = false
	if shadow > 0:
		sb.shadow_size = shadow
		sb.shadow_color = GameConfig.COLOR_SHADOW
		sb.shadow_offset = Vector2(0.0, 3.0)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	return sb


static func panel(bg: Color = GameConfig.COLOR_PANEL, radius: int = 18,
		border_color: Color = Color.TRANSPARENT, border_width: int = 0,
		shadow: int = 0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", stylebox(bg, radius, border_color, border_width, shadow))
	return p


## 选择类卡片的三态样式（未选中 / 悬停 / 选中）
static func card_style(accent: Color, selected: bool, hover: bool = false) -> StyleBoxFlat:
	var bg := GameConfig.COLOR_CARD
	if selected:
		bg = GameConfig.COLOR_CARD_SELECTED
	elif hover:
		bg = GameConfig.COLOR_CARD_HOVER
	var border: Color = accent if selected else GameConfig.COLOR_LINE
	var sb := stylebox(bg, 20, border, 4 if selected else 2, 8 if selected else 4)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	return sb


## 小圆角标签（例如「均衡」「推荐」）
static func chip(text: String, color: Color, font_size: int = 13) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := stylebox(Color(color.r, color.g, color.b, 0.16), 10, color, 1)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 2.0
	sb.content_margin_bottom = 3.0
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.add_child(label(text, font_size, color, HORIZONTAL_ALIGNMENT_CENTER))
	return p


## 属性条：名称 + 进度条 + 数值，比一串百分比数字直观得多
static func stat_bar(name_text: String, ratio: float, value_text: String,
		color: Color, width: float = 92.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var n := label(name_text, 14, GameConfig.COLOR_MUTED)
	n.custom_minimum_size = Vector2(34.0, 0.0)
	row.add_child(n)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, 8.0)
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = clampf(ratio, 0.0, 1.0)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color8(0x12, 0x1a, 0x2c)
	bg.set_corner_radius_all(4)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	row.add_child(bar)

	var v := label(value_text, 14, color, HORIZONTAL_ALIGNMENT_RIGHT)
	v.custom_minimum_size = Vector2(46.0, 0.0)
	row.add_child(v)
	return row


# ================================================================ 背景
## 统一的界面背景：竖向渐变 + 低多边形装饰块，避免整块死黑
static func add_background(target: Control, decorate: bool = true) -> void:
	var bg := TextureRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.texture = _background_gradient()
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.add_child(bg)

	if not decorate:
		return

	var deco := Control.new()
	deco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.modulate = Color(1.0, 1.0, 1.0, 0.55)
	target.add_child(deco)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260906
	for i in 16:
		var block := ColorRect.new()
		var s := rng.randf_range(60.0, 190.0)
		block.size = Vector2(s, s)
		block.position = Vector2(rng.randf_range(-140.0, 1280.0), rng.randf_range(-120.0, 720.0))
		block.color = Color8(0x35, 0x4a, 0x78, 46)
		block.rotation = rng.randf_range(-0.45, 0.45)
		block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		deco.add_child(block)


static func _background_gradient() -> GradientTexture2D:
	if _grad == null:
		var g := Gradient.new()
		g.set_color(0, GameConfig.COLOR_BG_TOP)
		g.set_color(1, GameConfig.COLOR_BG_BOTTOM)
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_LINEAR
		t.fill_from = Vector2(0.0, 0.0)
		t.fill_to = Vector2(0.35, 1.0)
		t.width = 256
		t.height = 256
		_grad = t
	return _grad


# ================================================================ 按钮
## 给任意按钮挂上点击 / 悬停音效。[param click] 可指定音色（卡片用 ui_select）
static func add_sfx(b: BaseButton, click: String = "ui_click") -> void:
	b.pressed.connect(func() -> void:
		if b.disabled:
			return
		Sfx.play(click))
	b.mouse_entered.connect(func() -> void:
		if b.disabled:
			return
		Sfx.play("ui_hover", 1.0, -9.0))


## 根据底色自动选择黑字 / 白字，保证任何强调色下都清晰
static func ink_for(bg: Color) -> Color:
	return Color8(0x0d, 0x13, 0x22) if bg.get_luminance() > 0.42 else GameConfig.COLOR_TEXT


static func button(text: String, accent: Color = GameConfig.COLOR_ACCENT,
		min_size: Vector2 = Vector2(220.0, 58.0), font_size: int = 24,
		ghost: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_override("font", body_font())
	b.add_theme_font_size_override("font_size", font_size)
	b.focus_mode = Control.FOCUS_NONE
	# 所有走 UiTheme 的按钮统一带点击 / 悬停音，各界面无需重复接线
	add_sfx(b)

	if ghost:
		# 次要按钮：透明底 + 描边，不与主按钮抢视线
		b.add_theme_stylebox_override("normal",
			stylebox(Color(accent.r, accent.g, accent.b, 0.10), 16, accent.darkened(0.1), 2))
		b.add_theme_stylebox_override("hover",
			stylebox(Color(accent.r, accent.g, accent.b, 0.22), 16, accent, 2))
		b.add_theme_stylebox_override("pressed",
			stylebox(Color(accent.r, accent.g, accent.b, 0.30), 16, accent, 2))
		b.add_theme_stylebox_override("disabled",
			stylebox(Color8(0x1c, 0x24, 0x36, 160), 16, GameConfig.COLOR_LINE, 2))
		b.add_theme_color_override("font_color", accent.lightened(0.25))
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_disabled_color", Color8(0x6b, 0x76, 0x8c))
		return b

	var base := accent.darkened(0.06)
	b.add_theme_stylebox_override("normal",
		stylebox(base, 16, accent.lightened(0.28), 2, 6))
	b.add_theme_stylebox_override("hover",
		stylebox(accent.lightened(0.12), 16, Color.WHITE, 2, 10))
	b.add_theme_stylebox_override("pressed",
		stylebox(accent.darkened(0.3), 16, accent, 2, 2))
	b.add_theme_stylebox_override("disabled",
		stylebox(Color8(0x30, 0x39, 0x4c), 16, Color8(0x3f, 0x4a, 0x60), 2))
	var ink := ink_for(base)
	b.add_theme_color_override("font_color", ink)
	b.add_theme_color_override("font_hover_color", ink_for(accent.lightened(0.12)))
	b.add_theme_color_override("font_pressed_color", ink_for(accent.darkened(0.3)))
	b.add_theme_color_override("font_disabled_color", Color8(0x78, 0x82, 0x96))
	return b


## 圆形的关卡节点按钮
static func node_button(text: String, accent: Color, size: float = 128.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(size, size)
	b.add_theme_font_override("font", body_font())
	b.add_theme_font_size_override("font_size", 18)
	b.focus_mode = Control.FOCUS_NONE
	add_sfx(b, "ui_select")
	var r := int(size / 2)
	b.add_theme_stylebox_override("normal", stylebox(accent.darkened(0.08), r,
		accent.lightened(0.3), 3, 8))
	b.add_theme_stylebox_override("hover", stylebox(accent.lightened(0.12), r, Color.WHITE, 3, 12))
	b.add_theme_stylebox_override("pressed", stylebox(accent.darkened(0.32), r, accent, 3))
	b.add_theme_stylebox_override("disabled", stylebox(Color8(0x28, 0x30, 0x42), r,
		Color8(0x38, 0x42, 0x58), 2))
	b.add_theme_color_override("font_color", ink_for(accent))
	b.add_theme_color_override("font_disabled_color", Color8(0x74, 0x7e, 0x90))
	return b


# ================================================================ 3D 动物预览
## 带 3D 动物预览的卡片（SubViewport 实时渲染）。
## 返回 {"root": Control, "container": SubViewportContainer, "model": Node3D}
static func animal_preview(file_name: String, size: float = 150.0,
		accent: Color = GameConfig.COLOR_ACCENT) -> Dictionary:
	var root := Control.new()
	root.custom_minimum_size = Vector2(size, size)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 背后的圆形光晕，让白色模型不再「浮」在深色卡片上
	var halo := Panel.new()
	halo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var halo_sb := StyleBoxFlat.new()
	halo_sb.bg_color = Color(accent.r, accent.g, accent.b, 0.13)
	halo_sb.set_corner_radius_all(int(size * 0.5))
	halo_sb.border_color = Color(accent.r, accent.g, accent.b, 0.35)
	halo_sb.set_border_width_all(2)
	halo.add_theme_stylebox_override("panel", halo_sb)
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(halo)

	var container := SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(container)

	var vp := SubViewport.new()
	vp.size = Vector2i(int(size), int(size))
	vp.transparent_bg = true
	# 关键：不开独立世界的话，所有预览会共用主场景的 World3D，
	# 六张卡片就会互相「串台」渲染成同一坨模型。
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	container.add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color8(0xb8, 0xc8, 0xe8)
	env.ambient_light_energy = 1.15
	var env_node := WorldEnvironment.new()
	env_node.environment = env
	vp.add_child(env_node)

	# 主光 + 补光：方块动物有明确的明暗面，轮廓更立体
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30.0, 35.0, 0.0)
	key.light_energy = 1.5
	vp.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10.0, -130.0, 0.0)
	fill.light_energy = 0.55
	fill.light_color = Color8(0x9f, 0xc4, 0xff)
	vp.add_child(fill)

	# 略微侧转，呈现 3/4 视角（模型默认面朝 +Z，即面向相机）
	var pivot := Node3D.new()
	pivot.rotation_degrees.y = 28.0
	vp.add_child(pivot)

	var model := AnimalModel.create(file_name, 1.70, 0.0)
	pivot.add_child(model)

	# 依据模型实际包围盒自动取景，保证每只动物都完整、居中、大小一致
	var box := AnimalModel.bounds(model)
	var center := box.position + box.size * 0.5
	var radius := maxf(box.size.length() * 0.5, 0.5)
	var fov := 32.0
	var dist := radius / sin(deg_to_rad(fov * 0.5)) * 0.86

	var camera := Camera3D.new()
	camera.fov = fov
	camera.position = Vector3(0.0, center.y + radius * 0.16, dist)
	# 预览此时还未挂到界面上，用 look_at_from_position 避免「节点不在树中」的报错
	camera.look_at_from_position(camera.position, Vector3(0.0, center.y, 0.0), Vector3.UP)
	vp.add_child(camera)

	return {"root": root, "container": container, "model": pivot}
