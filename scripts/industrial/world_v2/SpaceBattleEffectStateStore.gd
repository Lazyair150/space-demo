extends RefCounted
class_name SpaceBattleEffectStateStore
## Persists effect runtime state and dispatcher EventIds as ONE replaceable snapshot.
## Uses a pending file and a recoverable previous snapshot; platform durability must be verified.

var _path: String

func _init(path: String = "user://battle_effect_state.json") -> void:
	_path = path

func save(effect_state: Dictionary, dispatcher_state: Dictionary, loadout_identity: Dictionary) -> bool:
	var payload := {
		"schemaVersion": 1,
		"loadoutIdentity": loadout_identity.duplicate(true),
		"effectState": effect_state.duplicate(true),
		"dispatcherState": dispatcher_state.duplicate(true)
	}
	var absolute_path := ProjectSettings.globalize_path(_path)
	var temporary_path := absolute_path + ".pending"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		push_error("Unable to open battle effect snapshot temporary file: " + temporary_path)
		return false
	file.store_string(JSON.stringify(payload))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary_path)
		push_error("Unable to flush battle effect snapshot")
		return false

	if FileAccess.file_exists(absolute_path):
		var backup_path := absolute_path + ".previous"
		if FileAccess.file_exists(backup_path):
			DirAccess.remove_absolute(backup_path)
		var backup_error := DirAccess.rename_absolute(absolute_path, backup_path)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary_path)
			push_error("Unable to stage previous battle effect snapshot")
			return false
		var replace_error := DirAccess.rename_absolute(temporary_path, absolute_path)
		if replace_error != OK:
			DirAccess.rename_absolute(backup_path, absolute_path)
			push_error("Unable to replace battle effect snapshot")
			return false
		DirAccess.remove_absolute(backup_path)
		return true

	var rename_error := DirAccess.rename_absolute(temporary_path, absolute_path)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary_path)
		push_error("Unable to commit battle effect snapshot")
		return false
	return true

func load() -> Dictionary:
	var absolute_path := ProjectSettings.globalize_path(_path)
	var candidates := [absolute_path, absolute_path + ".previous"]
	for candidate in candidates:
		if not FileAccess.file_exists(candidate):
			continue
		var file := FileAccess.open(candidate, FileAccess.READ)
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary and int(parsed.get("schemaVersion", 0)) == 1:
			return parsed.duplicate(true)
	push_error("No valid battle effect snapshot or recoverable previous snapshot exists")
	return {}
