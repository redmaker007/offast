extends RefCounted
class_name asset_library

## 素材查找：关卡里引用素材用「相对 res:// 的路径」当 id（"theme/items/2t.png"、"sound/click2.mp3"）。
##
## 不做导入界面——玩家把图片、音乐按同样的相对路径丢进外部素材文件夹，就会盖掉游戏自带的那份：
##     <游戏目录>/assets/theme/items/2t.png     导出后的游戏（编辑器里运行时跳过这一个）
##     user://assets/theme/items/2t.png          用户数据目录，开发时也能用
## 都没有才用 res:// 里自带的。外部文件按扩展名直接读（png / jpg / webp / svg，mp3 / ogg / wav）。
## 设计见 docs/level_engine.md 第 6 节。

const USER_DIR := "user://assets"
const EXE_SUBDIR := "assets"

const IMAGE_EXTS := ["png", "jpg", "jpeg", "webp", "svg"]
const AUDIO_EXTS := ["mp3", "ogg", "wav"]

## id -> 读好的素材。外部文件可能被替换，clear_cache() 之后重新读。
static var _cache := {}


## 外部素材文件夹，按优先级。
static func external_dirs() -> Array[String]:
	var dirs: Array[String] = []
	if not OS.has_feature("editor"):
		dirs.append(OS.get_executable_path().get_base_dir().path_join(EXE_SUBDIR))
	dirs.append(USER_DIR)
	return dirs


## 外部文件夹里有没有这个素材，有就返回完整路径。
static func external_path(id: String) -> String:
	for dir in external_dirs():
		var path := dir.path_join(id)
		if FileAccess.file_exists(path):
			return path
	return ""


static func exists(id: String) -> bool:
	if id.is_empty():
		return false
	return not external_path(id).is_empty() or ResourceLoader.exists("res://" + id)


static func texture(id: String) -> Texture2D:
	return _load(id, "texture") as Texture2D


static func audio(id: String) -> AudioStream:
	return _load(id, "audio") as AudioStream


static func clear_cache() -> void:
	_cache.clear()


static func _load(id: String, kind: String) -> Resource:
	if id.is_empty():
		return null
	if _cache.has(id):
		return _cache[id]
	var res: Resource = null
	var ext_path := external_path(id)
	if not ext_path.is_empty():
		res = _load_external(ext_path, kind)
		if res == null:
			push_warning("外部素材读不进来，改用游戏自带的：%s" % ext_path)
	if res == null and ResourceLoader.exists("res://" + id):
		res = load("res://" + id)
	if res == null:
		push_error("找不到素材：%s" % id)
	_cache[id] = res
	return res


static func _load_external(path: String, kind: String) -> Resource:
	var ext := path.get_extension().to_lower()
	if kind == "texture" and ext in IMAGE_EXTS:
		var img := Image.load_from_file(path)
		return ImageTexture.create_from_image(img) if img != null else null
	if kind == "audio" and ext in AUDIO_EXTS:
		match ext:
			"mp3":
				var s := AudioStreamMP3.new()
				s.data = FileAccess.get_file_as_bytes(path)
				return s
			"ogg":
				return AudioStreamOggVorbis.load_from_file(path)
			"wav":
				return AudioStreamWAV.load_from_file(path)
	return null
