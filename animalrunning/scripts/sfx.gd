extends Node
## 程序化音效（Autoload 名：Sfx）。
##
## 项目里没有任何音频素材，所以全部音色都在启动时用 PCM 合成成 AudioStreamWAV：
## 零素材依赖、不产生 .import 文件，音高与音量还能跟着游戏状态实时变化。
##
## 用法：Sfx.play("coin")、Sfx.play("jump", 1.08)、Sfx.play("step", 1.0, -6.0)

const MIX_RATE := 22050.0
const VOICE_COUNT := 16          # 可同时播放的音效数量
const DEFAULT_VOLUME := 0.8

## 基础波形
enum Wave { SINE, SQUARE, SAW, TRI }

# 常用音高（十二平均律，C5 = 523.25 Hz）
const C5 := 523.25
const D5 := 587.33
const E5 := 659.25
const G5 := 783.99
const A5 := 880.00
const B5 := 987.77
const C6 := 1046.50
const E6 := 1318.51
const G6 := 1567.98
const C7 := 2093.00

var _bank: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _rng := RandomNumberGenerator.new()
var _volume: float = DEFAULT_VOLUME
var _muted: bool = false


func _ready() -> void:
	# 暂停时界面按钮依然需要点击反馈，因此音效系统不能被 SceneTree 冻结
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 20260906

	_volume = GameState.sfx_volume
	_muted = GameState.sfx_muted

	_build_voices()
	_build_bank()


# ================================================================ 对外接口
## 播放一个音效。[param pitch] 音高倍率，[param volume_db] 相对音量增减
func play(sound: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if _muted or _volume <= 0.001:
		return
	var stream: AudioStreamWAV = _bank.get(sound)
	if stream == null:
		return

	var voice := _pick_voice()
	voice.stream = stream
	voice.pitch_scale = clampf(pitch, 0.4, 2.4)
	voice.volume_db = linear_to_db(_volume) + volume_db
	voice.play()


func set_volume(value: float) -> void:
	_volume = clampf(value, 0.0, 1.0)
	GameState.sfx_volume = _volume
	GameState.save()


func get_volume() -> float:
	return _volume


func set_muted(value: bool) -> void:
	_muted = value
	if _muted:
		for v in _voices:
			v.stop()
	GameState.sfx_muted = _muted
	GameState.save()


func is_muted() -> bool:
	return _muted


## 返回切换后的状态
func toggle_mute() -> bool:
	set_muted(not _muted)
	if not _muted:
		play("ui_confirm")
	return _muted


# ================================================================ 播放通道
func _build_voices() -> void:
	for i in VOICE_COUNT:
		var p := AudioStreamPlayer.new()
		p.name = "Voice%d" % i
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_voices.append(p)


## 优先找空闲通道，全忙则覆盖最早的那个
func _pick_voice() -> AudioStreamPlayer:
	for i in _voices.size():
		var idx := (_next_voice + i) % _voices.size()
		if not _voices[idx].playing:
			_next_voice = (idx + 1) % _voices.size()
			return _voices[idx]
	var fallback := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	return fallback


# ================================================================ 音色合成
func _build_bank() -> void:
	_bank["jump"] = _make_jump()
	_bank["land"] = _make_land()
	_bank["step"] = _make_step()
	_bank["lane"] = _make_lane()
	_bank["coin"] = _make_coin()
	_bank["heal"] = _make_heal()
	_bank["hit"] = _make_hit()
	_bank["death"] = _make_death()
	_bank["gust"] = _make_gust()
	_bank["fall"] = _make_fall()
	_bank["enemy_jump"] = _make_enemy_jump()
	_bank["win"] = _make_win()
	_bank["record"] = _make_record()
	_bank["start"] = _make_start()
	_bank["warn"] = _make_warn()
	_bank["unlock"] = _make_unlock()
	_bank["pause"] = _make_pause()
	_bank["resume"] = _make_resume()
	_bank["ui_click"] = _make_ui_click()
	_bank["ui_hover"] = _make_ui_hover()
	_bank["ui_select"] = _make_ui_select()
	_bank["ui_confirm"] = _make_ui_confirm()
	_bank["ui_back"] = _make_ui_back()
	_bank["powerup"] = _make_powerup()
	_bank["shield_up"] = _make_shield_up()
	_bank["shield_break"] = _make_shield_break()
	_bank["trick"] = _make_trick()
	_bank["slide"] = _make_slide()
	_bank["revive"] = _make_revive()


# ---------------------------------------------------------------- 跑动
## 跳跃：向上滑音，方块动物的轻快感
func _make_jump() -> AudioStreamWAV:
	var b := _blank(0.20)
	_osc(b, 0.0, 0.17, 420.0, 900.0, 0.30, Wave.SQUARE, 3.4)
	_osc(b, 0.0, 0.17, 210.0, 450.0, 0.16, Wave.TRI, 3.0)
	return _to_stream(b)


## 落地：低频闷响 + 一点尘土噪声
func _make_land() -> AudioStreamWAV:
	var b := _blank(0.16)
	_osc(b, 0.0, 0.13, 190.0, 70.0, 0.40, Wave.SINE, 5.5)
	_noise(b, 0.0, 0.06, 0.13, 9.0, 0.55)
	return _to_stream(b)


## 脚步：极短的软噪声，音量很低，只作为奔跑节奏底噪
func _make_step() -> AudioStreamWAV:
	var b := _blank(0.06)
	_noise(b, 0.0, 0.045, 0.16, 14.0, 0.7)
	_osc(b, 0.0, 0.04, 150.0, 95.0, 0.10, Wave.SINE, 12.0)
	return _to_stream(b)


## 换道：一声轻微的横向掠风
func _make_lane() -> AudioStreamWAV:
	var b := _blank(0.10)
	_noise(b, 0.0, 0.08, 0.13, 8.0, 0.35)
	_osc(b, 0.0, 0.07, 760.0, 420.0, 0.07, Wave.TRI, 7.0)
	return _to_stream(b)


# ---------------------------------------------------------------- 收集 / 受击
## 能量方块：明亮的两音上行，经典拾取音
func _make_coin() -> AudioStreamWAV:
	var b := _blank(0.22)
	_osc(b, 0.0, 0.06, B5, B5, 0.20, Wave.SQUARE, 2.4)
	_osc(b, 0.045, 0.16, E6, E6, 0.22, Wave.SQUARE, 3.2)
	_osc(b, 0.045, 0.16, C7, C7, 0.05, Wave.SINE, 4.0)
	return _to_stream(b)


## 回血：柔和的三音上行
func _make_heal() -> AudioStreamWAV:
	var b := _blank(0.42)
	_osc(b, 0.00, 0.14, E5, E5, 0.17, Wave.TRI, 3.0)
	_osc(b, 0.09, 0.14, G5, G5, 0.17, Wave.TRI, 3.0)
	_osc(b, 0.18, 0.22, C6, C6, 0.19, Wave.TRI, 2.6)
	_osc(b, 0.18, 0.22, E6, E6, 0.06, Wave.SINE, 3.0)
	return _to_stream(b)


## 受击：锯齿下坠 + 撞击噪声
func _make_hit() -> AudioStreamWAV:
	var b := _blank(0.34)
	_osc(b, 0.0, 0.30, 330.0, 90.0, 0.30, Wave.SAW, 3.6)
	_noise(b, 0.0, 0.13, 0.24, 7.0, 0.25)
	_osc(b, 0.0, 0.10, 120.0, 60.0, 0.20, Wave.SINE, 6.0)
	return _to_stream(b)


## 阵风：一整段柔和的宽频风噪，缓入缓出
func _make_gust() -> AudioStreamWAV:
	var b := _blank(1.30)
	_noise(b, 0.0, 1.28, 0.30, 0.9, 0.93)
	_osc(b, 0.05, 1.10, 210.0, 150.0, 0.035, Wave.SINE, 1.1)
	return _to_stream(b)


## 坠落：长距离下行滑音，掉进坑洞时播放
func _make_fall() -> AudioStreamWAV:
	var b := _blank(0.75)
	_osc(b, 0.0, 0.70, 700.0, 90.0, 0.26, Wave.TRI, 1.5)
	_osc(b, 0.0, 0.70, 350.0, 45.0, 0.12, Wave.SINE, 1.5)
	_noise(b, 0.0, 0.60, 0.07, 2.0, 0.9)
	return _to_stream(b)


## 追兵起跳：比玩家跳跃更短更闷，避免混淆
func _make_enemy_jump() -> AudioStreamWAV:
	var b := _blank(0.14)
	_osc(b, 0.0, 0.12, 300.0, 560.0, 0.16, Wave.TRI, 4.5)
	return _to_stream(b)


## 淘汰：四个下行音，交代「本局结束」
func _make_death() -> AudioStreamWAV:
	var b := _blank(0.90)
	var notes := [C6, A5, E5, C5 * 0.5]
	for i in notes.size():
		var f: float = notes[i]
		_osc(b, float(i) * 0.14, 0.30, f, f * 0.98, 0.24, Wave.SQUARE, 3.2)
	_osc(b, 0.56, 0.34, 130.0, 62.0, 0.22, Wave.SAW, 2.4)
	return _to_stream(b)


# ---------------------------------------------------------------- 结果 / 流程
## 通关：大三和弦琶音上行
func _make_win() -> AudioStreamWAV:
	var b := _blank(1.00)
	var notes := [C5, E5, G5, C6]
	for i in notes.size():
		var f: float = notes[i]
		var dur := 0.44 if i == notes.size() - 1 else 0.22
		_osc(b, float(i) * 0.11, dur, f, f, 0.19, Wave.SQUARE, 2.6)
		_osc(b, float(i) * 0.11, dur, f * 2.0, f * 2.0, 0.05, Wave.SINE, 3.2)
	_osc(b, 0.44, 0.50, G5, G5, 0.10, Wave.TRI, 2.0)
	return _to_stream(b)


## 新纪录：三颗高音「叮」
func _make_record() -> AudioStreamWAV:
	var b := _blank(0.50)
	var notes := [E6, G6, C7]
	for i in notes.size():
		var f: float = notes[i]
		_osc(b, float(i) * 0.08, 0.20, f, f, 0.15, Wave.SINE, 4.0)
		_osc(b, float(i) * 0.08, 0.20, f * 1.5, f * 1.5, 0.05, Wave.SINE, 5.0)
	return _to_stream(b)


## 解锁新关卡
func _make_unlock() -> AudioStreamWAV:
	var b := _blank(0.55)
	_osc(b, 0.00, 0.16, G5, G5, 0.17, Wave.SQUARE, 3.0)
	_osc(b, 0.10, 0.16, C6, C6, 0.17, Wave.SQUARE, 3.0)
	_osc(b, 0.20, 0.30, E6, E6, 0.18, Wave.SQUARE, 2.4)
	_osc(b, 0.20, 0.30, G6, G6, 0.07, Wave.SINE, 3.0)
	return _to_stream(b)


## 出发：短促的三连上行 + 一声起跑气流
func _make_start() -> AudioStreamWAV:
	var b := _blank(0.55)
	_osc(b, 0.00, 0.11, C5, C5, 0.18, Wave.SQUARE, 3.6)
	_osc(b, 0.09, 0.11, G5, G5, 0.18, Wave.SQUARE, 3.6)
	_osc(b, 0.18, 0.26, C6, C6, 0.20, Wave.SQUARE, 2.6)
	_noise(b, 0.18, 0.22, 0.10, 5.0, 0.3)
	return _to_stream(b)


## 追兵逼近：低沉的两声警示
func _make_warn() -> AudioStreamWAV:
	var b := _blank(0.34)
	_osc(b, 0.00, 0.12, 233.0, 220.0, 0.20, Wave.SAW, 4.0)
	_osc(b, 0.15, 0.14, 196.0, 185.0, 0.20, Wave.SAW, 4.0)
	return _to_stream(b)


func _make_pause() -> AudioStreamWAV:
	var b := _blank(0.24)
	_osc(b, 0.00, 0.10, A5, A5, 0.16, Wave.TRI, 4.0)
	_osc(b, 0.08, 0.14, E5, E5, 0.16, Wave.TRI, 3.6)
	return _to_stream(b)


func _make_resume() -> AudioStreamWAV:
	var b := _blank(0.24)
	_osc(b, 0.00, 0.10, E5, E5, 0.16, Wave.TRI, 4.0)
	_osc(b, 0.08, 0.14, A5, A5, 0.16, Wave.TRI, 3.6)
	return _to_stream(b)


# ---------------------------------------------------------------- 界面
func _make_ui_click() -> AudioStreamWAV:
	var b := _blank(0.09)
	_osc(b, 0.0, 0.06, 900.0, 700.0, 0.15, Wave.SQUARE, 7.0)
	_osc(b, 0.0, 0.05, 450.0, 380.0, 0.07, Wave.TRI, 8.0)
	return _to_stream(b)


func _make_ui_hover() -> AudioStreamWAV:
	var b := _blank(0.06)
	_osc(b, 0.0, 0.04, 1200.0, 1250.0, 0.13, Wave.SINE, 9.0)
	return _to_stream(b)


## 选中卡片：比普通点击更「实」一点
func _make_ui_select() -> AudioStreamWAV:
	var b := _blank(0.20)
	_osc(b, 0.00, 0.07, G5, G5, 0.15, Wave.SQUARE, 4.5)
	_osc(b, 0.05, 0.13, C6, C6, 0.16, Wave.SQUARE, 4.0)
	return _to_stream(b)


func _make_ui_confirm() -> AudioStreamWAV:
	var b := _blank(0.26)
	_osc(b, 0.00, 0.09, E5, E5, 0.16, Wave.SQUARE, 4.0)
	_osc(b, 0.07, 0.09, G5, G5, 0.16, Wave.SQUARE, 4.0)
	_osc(b, 0.14, 0.14, C6, C6, 0.17, Wave.SQUARE, 3.4)
	return _to_stream(b)


func _make_ui_back() -> AudioStreamWAV:
	var b := _blank(0.20)
	_osc(b, 0.00, 0.08, G5, G5, 0.14, Wave.TRI, 5.0)
	_osc(b, 0.06, 0.12, D5, D5, 0.14, Wave.TRI, 4.5)
	return _to_stream(b)


# ---------------------------------------------------------------- 道具 / 技巧（B2 / B3）
## 拾取道具：明亮的快速琶音上行，结尾带一点闪光感
func _make_powerup() -> AudioStreamWAV:
	var b := _blank(0.55)
	var notes := [C5, E5, G5, C6]
	for i in notes.size():
		var f: float = notes[i]
		var start := float(i) * 0.07
		_osc(b, start, 0.16, f, f, 0.18, Wave.SQUARE, 3.4)
		_osc(b, start, 0.16, f * 2.0, f * 2.0, 0.05, Wave.SINE, 4.2)
	_osc(b, 0.28, 0.24, E6, E6, 0.09, Wave.SINE, 3.0)
	return _to_stream(b)


## 获得护盾：低频沉稳 + 高频闪烁，有「能量展开」的感觉
func _make_shield_up() -> AudioStreamWAV:
	var b := _blank(0.45)
	_osc(b, 0.00, 0.30, 196.0, 196.0, 0.16, Wave.TRI, 2.6)
	_osc(b, 0.04, 0.26, G5, G5, 0.13, Wave.SINE, 3.2)
	_osc(b, 0.16, 0.24, E6, E6, 0.07, Wave.SINE, 3.8)
	return _to_stream(b)


## 护盾破碎：噪声爆破 + 短下行，干脆利落
func _make_shield_break() -> AudioStreamWAV:
	var b := _blank(0.32)
	_noise(b, 0.0, 0.16, 0.30, 11.0, 0.35)
	_osc(b, 0.0, 0.26, 880.0, 320.0, 0.16, Wave.SAW, 4.6)
	_osc(b, 0.0, 0.12, 220.0, 110.0, 0.18, Wave.SINE, 6.0)
	return _to_stream(b)


## 技巧得分（跳栏 / 擦身 / 飞坑）：短促的高音双叮
func _make_trick() -> AudioStreamWAV:
	var b := _blank(0.20)
	_osc(b, 0.00, 0.07, G6, G6, 0.14, Wave.SINE, 5.0)
	_osc(b, 0.06, 0.12, C7, C7, 0.12, Wave.SINE, 5.5)
	return _to_stream(b)


# ---------------------------------------------------------------- 滑铲 / 复活（B4 / C4）
## 滑铲：一段贴地掠过的摩擦噪声 + 下滑的低音，短促但有「擦地」的实感
func _make_slide() -> AudioStreamWAV:
	var b := _blank(0.42)
	_noise(b, 0.0, 0.34, 0.26, 3.2, 0.62)
	_osc(b, 0.0, 0.30, 520.0, 190.0, 0.16, Wave.TRI, 4.2)
	_osc(b, 0.02, 0.24, 130.0, 78.0, 0.14, Wave.SINE, 5.0)
	return _to_stream(b)


## 复活：由低到高的四音上行 + 一层明亮的泛音，明确传达「回来了」
func _make_revive() -> AudioStreamWAV:
	var b := _blank(0.85)
	var notes := [C5, E5, G5, C6]
	for i in notes.size():
		var f: float = notes[i]
		var start := float(i) * 0.09
		_osc(b, start, 0.26, f, f, 0.17, Wave.TRI, 2.8)
		_osc(b, start, 0.26, f * 2.0, f * 2.0, 0.05, Wave.SINE, 3.6)
	_osc(b, 0.36, 0.44, E6, E6, 0.10, Wave.SINE, 2.4)
	_noise(b, 0.0, 0.18, 0.10, 6.0, 0.5)
	return _to_stream(b)


# ================================================================ 合成底层
## 一段静音缓冲（单位：秒）
func _blank(duration: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(int(duration * MIX_RATE))
	return buf


## 叠加一个振荡器。频率从 [param f0] 线性扫到 [param f1]，
## 音量按 exp(-decay * 进度) 衰减；首尾各带极短的淡入淡出，避免爆音。
func _osc(buf: PackedFloat32Array, start: float, duration: float, f0: float, f1: float,
		gain: float, wave: Wave = Wave.SINE, decay: float = 3.0) -> void:
	var total := buf.size()
	var offset := int(start * MIX_RATE)
	var count := int(duration * MIX_RATE)
	if count <= 1:
		return

	var fade := maxf(0.004 * MIX_RATE, 1.0)
	var phase := 0.0

	for k in count:
		var i := offset + k
		if i < 0 or i >= total:
			continue
		var u := float(k) / float(count - 1)
		phase += TAU * lerpf(f0, f1, u) / MIX_RATE

		var s := 0.0
		match wave:
			Wave.SINE:
				s = sin(phase)
			Wave.SQUARE:
				s = 1.0 if sin(phase) >= 0.0 else -1.0
			Wave.SAW:
				s = fposmod(phase, TAU) / PI - 1.0
			Wave.TRI:
				s = asin(sin(phase)) * (2.0 / PI)

		var env := exp(-decay * u)
		var shape := minf(float(k) / fade, minf(float(count - k) / fade, 1.0))
		buf[i] += s * env * shape * gain


## 叠加一段噪声。[param smooth] 为 0~1 的低通系数，越大越「闷」，用于风声 / 撞击
func _noise(buf: PackedFloat32Array, start: float, duration: float, gain: float,
		decay: float = 8.0, smooth: float = 0.0) -> void:
	var total := buf.size()
	var offset := int(start * MIX_RATE)
	var count := int(duration * MIX_RATE)
	if count <= 1:
		return

	var fade := maxf(0.003 * MIX_RATE, 1.0)
	var last := 0.0
	var a := clampf(smooth, 0.0, 0.98)

	for k in count:
		var i := offset + k
		if i < 0 or i >= total:
			continue
		var u := float(k) / float(count - 1)
		# 一阶低通，把白噪声压成更柔和的「风」
		last = lerpf(_rng.randf_range(-1.0, 1.0), last, a)
		var env := exp(-decay * u)
		var shape := minf(float(k) / fade, minf(float(count - k) / fade, 1.0))
		buf[i] += last * env * shape * gain


## 浮点缓冲 -> 16 位单声道 AudioStreamWAV
func _to_stream(buf: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		# tanh 软限幅：叠加多层后也不会出现数字削波的刺耳感
		var v: float = tanh(buf[i] * 1.35)
		bytes.encode_s16(i * 2, int(round(clampf(v, -1.0, 1.0) * 32767.0)))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(MIX_RATE)
	wav.stereo = false
	wav.data = bytes
	return wav
