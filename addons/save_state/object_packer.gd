extends RefCounted
class_name object_packer

## 把纯数据对象和内置容器递归转成"可以直接 var_to_str 的普通 Variant"，以及反向还原。
##
## 字段靠 get_property_list() + PROPERTY_USAGE_SCRIPT_VARIABLE 枚举，
## 所以被打包的数据类一行存档代码都不用写——加字段自动跟着存。
##
## 只支持纯数据对象：字段里出现 Node、Callable、Signal、没有脚本文件的对象会打包失败。
##
## 注意：还原时会按存档里记的脚本路径 load().new()。本地单机存档可以接受，
## 但存档文件是用户可编辑的，如果以后有云存档或联机，这里要改成白名单。

## 打包后的字典里用这个 key 记脚本路径。普通字典里出现同名 key 会被误判成对象。
const SCRIPT_KEY := "_script"


## 递归打包。数组/字典逐项处理，带脚本的对象转成字典，其余原样返回。
static func pack(v: Variant) -> Variant:
	if v is Array:
		var packed_array := []
		for item in v:
			packed_array.append(pack(item))
		return packed_array

	if v is Dictionary:
		var packed_dict := {}
		for key in v:
			packed_dict[pack(key)] = pack(v[key])
		return packed_dict

	if v is Object:
		return _pack_object(v)

	return v


## 递归还原，pack() 的逆操作。
static func unpack(v: Variant) -> Variant:
	if v is Array:
		var restored_array := []
		for item in v:
			restored_array.append(unpack(item))
		return restored_array

	if v is Dictionary:
		if v.has(SCRIPT_KEY):
			return _unpack_object(v)
		var restored_dict := {}
		for key in v:
			restored_dict[unpack(key)] = unpack(v[key])
		return restored_dict

	return v


static func _pack_object(obj: Object) -> Dictionary:
	var script: Script = obj.get_script()
	if script == null or script.resource_path.is_empty():
		push_error("object_packer 只能打包带脚本文件的对象，跳过：%s" % obj)
		return {}

	var out := {SCRIPT_KEY: script.resource_path}
	for prop in obj.get_property_list():
		if not (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		out[prop["name"]] = pack(obj.get(prop["name"]))
	return out


static func _unpack_object(d: Dictionary) -> Object:
	var script_path: String = str(d[SCRIPT_KEY])
	if not ResourceLoader.exists(script_path):
		push_error("存档里记的脚本路径不存在，跳过：%s" % script_path)
		return null

	var script: Script = load(script_path)
	var obj: Object = script.new()
	for key in d:
		if key == SCRIPT_KEY:
			continue
		obj.set(key, unpack(d[key]))
	return obj
