tool
extends EditorPlugin

var menu

func _enter_tree():
	menu = Button.new()
	menu.text = "ObjectPooling"
	menu.connect("pressed", self, "on_object_pool_ui")
	add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, menu)

func _exit_tree():
	remove_control_from_container(EditorPlugin.CONTAINER_TOOLBAR, menu)

func on_object_pool_ui():
	var popup = load("res://addons/object_pooling/ObjectPoolingUi.tscn").instance()
	add_child(popup)
	popup.get_node("scenes/list/TEMPLATE").visible = false
	popup.connect("popup_hide", self, "on_ui_closed", [popup])
	
	var scenes_state = load_all_text("res://addons/object_pooling/state.tres")
	if scenes_state != null:
		scenes_state = JSON.parse(scenes_state).result
		popup.get_node("DEBUG").pressed = scenes_state["DEBUG"]
	var scenes_dict = { }
	var scenes = get_scenes_recursively("res://")
	if scenes.size() < 1:
		var p = ConfirmationDialog.new()
		p.window_title = "ObjectPooling"
		p.dialog_text = "No scenes found in project"
		p.theme = load("res://addons/object_pooling/theme.tres")
		add_child(p)
		p.popup_centered()
		return
	for node in popup.get_node("scenes/list").get_children():
		if node.name == "TEMPLATE": continue
		node.name = "x"
		node.visible = false
		node.queue_free()
	for scene_path in scenes:
		var node = popup.get_node("scenes/list/TEMPLATE").duplicate(true)
		node.get_node("PATH").text = str(scene_path)
		node.visible = true
		if scenes_state != null:
			if scenes_state.scenes.has(scene_path):
				node.get_node("COUNT").value = scenes_state.scenes[scene_path]
		popup.get_node("scenes/list").add_child(node)
		scenes_dict[scene_path] = 1
	popup.popup()
	
func get_scenes_recursively(path):
	var scenes = []
	var dir = Directory.new()
	if path.find("addons") != -1:
		return scenes
	if path.find(".import") != -1:
		return scenes
	if dir.open(path) == OK:
		dir.list_dir_begin(true)
		var element_name = dir.get_next()
		while element_name != "":
			if dir.current_is_dir():
				if path + element_name != path:
					if dir.get_current_dir() != "res://":
						scenes += get_scenes_recursively(dir.get_current_dir() + "/" + element_name + "/")
					else:
						scenes += get_scenes_recursively(dir.get_current_dir() + element_name + "/")
			else:
				if element_name.ends_with(".tscn"):
					scenes.push_back(path + element_name)
			element_name = dir.get_next()
	else:
		print("ObjectPooling: Error opening path " + str(path))
	return scenes
	
func on_ui_closed(popup):
	var script_source_path = "res://addons/object_pooling/ObjectPoolingTemplate.gd"
	var script_target_path = "res://addons/object_pooling/ObjectPooling.gd"
	var script : String = load_all_text(script_source_path)
	var starting_index = script.find("#%**-")
	var scenes = {}
	for node in popup.get_node("scenes/list").get_children():
		if node.name == "TEMPLATE": continue
		scenes[node.get_node("PATH").text] = int(node.get_node("COUNT").value)
		
	var scenes_state = { scenes = scenes }
	scenes_state["DEBUG"] = popup.get_node("DEBUG").is_pressed()
	write_all_text("res://addons/object_pooling/state.tres", JSON.print(scenes_state, "\t"))
	script = script.replace("#%**--", "= " + JSON.print(scenes, "\t"))
	script = script.replace("#%**-", "= " + str(popup.get_node("DEBUG").is_pressed()).to_lower())
	write_all_text(script_target_path, script)
	remove_autoload_singleton("ObjectPooling")
	add_autoload_singleton("ObjectPooling", script_target_path)
	
func load_all_text(path):
	var file = File.new()
	if file.open(path, File.READ) != OK:
		print("ObjectPooling: Could not open file: " + str(path))
	else:
		var content = file.get_as_text()
		file.close()
		return content

func write_all_text(path, content):
	var file = File.new()
	if file.open(path, File.WRITE) != OK:
		print("ObjectPooling: Could not open file: " + str(path))
	else:
		file.store_string(content)
		file.close()
