extends Node
## 全局存档与选择状态（Autoload 名：GameState）。
## 负责：记住玩家选择的角色 / 难度、关卡解锁进度、每个「关卡 + 难度」的最佳成绩。

const SAVE_PATH := "user://save.cfg"

## 当前选择的角色索引
var character_index: int = 0
## 当前选择的难度索引
var difficulty_index: int = 1
## 当前进入的关卡索引
var current_level: int = 0
## 已解锁的关卡数量（至少 1）
var unlocked_levels: int = 1
## 键："关卡索引_难度id"，值：最佳分数
var best_scores: Dictionary = {}
## 音效音量（0~1）与静音开关
var sfx_volume: float = 0.8
var sfx_muted: bool = false


func _ready() -> void:
	load_save()


# ---------------------------------------------------------------- 存档
func load_save() -> void:
	var file := ConfigFile.new()
	if file.load(SAVE_PATH) != OK:
		return

	unlocked_levels = maxi(1, int(file.get_value("progress", "unlocked", 1)))
	var loaded_best = file.get_value("progress", "best", {})
	if loaded_best is Dictionary:
		best_scores = loaded_best
	character_index = clampi(int(file.get_value("settings", "character", 0)),
		0, GameConfig.CHARACTERS.size() - 1)
	difficulty_index = clampi(int(file.get_value("settings", "difficulty", 1)),
		0, GameConfig.DIFFICULTIES.size() - 1)
	sfx_volume = clampf(float(file.get_value("settings", "sfx_volume", 0.8)), 0.0, 1.0)
	sfx_muted = bool(file.get_value("settings", "sfx_muted", false))


func save() -> void:
	var file := ConfigFile.new()
	file.set_value("progress", "unlocked", unlocked_levels)
	file.set_value("progress", "best", best_scores)
	file.set_value("settings", "character", character_index)
	file.set_value("settings", "difficulty", difficulty_index)
	file.set_value("settings", "sfx_volume", sfx_volume)
	file.set_value("settings", "sfx_muted", sfx_muted)
	file.save(SAVE_PATH)


# ---------------------------------------------------------------- 关卡进度
func is_level_unlocked(index: int) -> bool:
	return index < unlocked_levels


func unlock_level(index: int) -> void:
	if index + 1 > unlocked_levels and index + 1 <= GameConfig.LEVELS.size():
		unlocked_levels = index + 1
		save()


# ---------------------------------------------------------------- 成绩
static func score_key(level_index: int, difficulty_id: String) -> String:
	return "%d_%s" % [level_index, difficulty_id]


func get_best(level_index: int, difficulty_id: String) -> int:
	return int(best_scores.get(score_key(level_index, difficulty_id), 0))


## 返回是否刷新了纪录
func record_score(level_index: int, difficulty_id: String, score: int) -> bool:
	var key := score_key(level_index, difficulty_id)
	if score > int(best_scores.get(key, 0)):
		best_scores[key] = score
		save()
		return true
	return false


# ---------------------------------------------------------------- 对局参数
## 最终生命值 = 难度基础生命 + 角色加成（至少 1）
func final_hp() -> int:
	var base := int(GameConfig.difficulty(difficulty_index)["hp"])
	var bonus := int(GameConfig.character(character_index)["hp"])
	return maxi(1, base + bonus)


func final_score(score: int) -> int:
	return int(score * float(GameConfig.difficulty(difficulty_index)["score"]))
