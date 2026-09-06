class_name AnimalModel
extends RefCounted
## Kenney「Cube Pets」方块动物模型的加载与自适应工具。
##
## 原始模型：宽约 1.25、高约 1.6，原点位于身体底部（腿会伸到 y = -0.3 附近），
## 且默认面朝 +Z。这里统一完成：缩放 -> 底部贴地 -> 水平居中 -> 朝向修正。

const MODEL_DIR := "res://models/animals/"


## 加载并实例化一个动物模型。
## [param file_name] 形如 "animal-panda.glb"
## [param height]    缩放后的目标高度（米）
## [param yaw_deg]   朝向修正角度；180 表示把默认的 +Z 朝向翻转成 -Z（前进方向）
static func create(file_name: String, height: float, yaw_deg := 180.0) -> Node3D:
	var path := MODEL_DIR + file_name
	if not ResourceLoader.exists(path):
		push_error("找不到模型: " + path)
		return Node3D.new()

	var packed: PackedScene = load(path)
	if packed == null:
		push_error("模型加载失败: " + path)
		return Node3D.new()

	var inst := packed.instantiate() as Node3D
	if inst == null:
		push_error("模型根节点不是 Node3D: " + path)
		return Node3D.new()

	inst.rotation_degrees.y = yaw_deg

	# 1) 按高度等比缩放
	var box := _aabb_of(inst)
	var s := height / maxf(box.size.y, 0.001)
	inst.scale = Vector3.ONE * s

	# 2) 重新测量后：底部贴地 + 水平居中
	box = _aabb_of(inst)
	inst.position.x -= box.position.x + box.size.x * 0.5
	inst.position.z -= box.position.z + box.size.z * 0.5
	inst.position.y -= box.position.y

	return inst


## 计算模型的合并包围盒（含自身 transform），供界面自动取景使用
static func bounds(root: Node3D) -> AABB:
	return _aabb_of(root)


## 收集模型里所有名字含关键字的子节点（用来做跑步摆腿动画）
static func collect_parts(root: Node, keyword: String, out: Array[Node3D]) -> void:
	for c in root.get_children():
		if c is Node3D:
			if c.name.to_lower().contains(keyword.to_lower()):
				out.append(c as Node3D)
			collect_parts(c, keyword, out)


## 计算以 root 为根的所有 MeshInstance3D 的合并 AABB（root 父节点坐标系）。
## 手工累乘 transform，因此不要求节点已加入场景树。
static func _aabb_of(root: Node3D) -> AABB:
	var acc: Array = [null, false]
	_accumulate(root, Transform3D(), acc)
	if not acc[1]:
		return AABB(Vector3.ZERO, Vector3.ONE)
	return acc[0] as AABB


static func _accumulate(node: Node, parent_xform: Transform3D, acc: Array) -> void:
	var xf := parent_xform
	if node is Node3D:
		xf = parent_xform * (node as Node3D).transform
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			if mi.mesh != null:
				var box: AABB = xf * mi.get_aabb()
				if not acc[1]:
					acc[0] = box
					acc[1] = true
				else:
					acc[0] = (acc[0] as AABB).merge(box)
	for c in node.get_children():
		_accumulate(c, xf, acc)
