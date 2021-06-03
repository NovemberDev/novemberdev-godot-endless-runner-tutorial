tool
extends EditorPlugin

var menu

func _enter_tree():
	menu = Button.new()
	menu.text = "Compute Parts"
	menu.connect("pressed", self, "on_compute_parts")
	add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, menu)

func _exit_tree():
	remove_control_from_container(EditorPlugin.CONTAINER_TOOLBAR, menu)

func on_compute_parts():
	var root = get_tree().get_edited_scene_root()
	
	# if this node exists
	if root.has_node("OBJECT_LAYOUTS"):
		var layouts = {}
		# loop all children
		for node in root.get_node("OBJECT_LAYOUTS").get_children():
			# record all layouts and store which nodes were placed
			var s = node.name.split('_')
			var type = s[0]
			if !layouts.has(type):
				layouts[type] = []
			var new_layout = {
				name = node.name,
				children = []
			}
			for item in node.get_children():
				var v = item.transform.origin
				new_layout.children.push_back({
					name = item.name,
					x = v.x,
					y = v.y,
					z = v.z,
					rx = item.rotation.x,
					ry = item.rotation.y,
					rz = item.rotation.z
				})
			layouts[type].push_back(new_layout)
		var f = File.new()
		print("compiling parts: " + str(f.open("res://compiled_parts.tres", f.WRITE)))
		f.store_string(JSON.print(layouts))
		f.close()
		root.remove_child(root.get_node("OBJECT_LAYOUTS"))
	else:
		# read the layout parts
		var f = File.new()
		print("reading parts: " + str(f.open("res://compiled_parts.tres", f.READ)))
		var layouts = JSON.parse(f.get_as_text()).result
		var layouts_node
		if !root.has_node("OBJECT_LAYOUTS"):
			layouts_node = Spatial.new()
			layouts_node.name = "OBJECT_LAYOUTS"
			root.add_child(layouts_node)
			layouts_node.set_owner(root)
		else:
			layouts_node = root.get_node("OBJECT_LAYOUTS")
		# loop over layouts and instance the related scenes at those positions
		for part in layouts.values():
			for layout in part:
				var s = Spatial.new()
				s.name = layout.name
				s.visible = false
				layouts_node.add_child(s)
				s.set_owner(root)
				for item in layout.children:
					var n = item.name.split('_')
					var p = null
					if item.name.begins_with("COIN"):
						p = load("res://scenes/COIN.tscn").instance()
					elif item.name.begins_with("PICKUP"):
						p = load("res://scenes/MAGNET.tscn").instance()
					elif item.name.begins_with("SHIELD"):
						p = load("res://scenes/SHIELD.tscn").instance()
					elif item.name.begins_with("SPEED"):
						p = load("res://scenes/SPEED.tscn").instance()
					elif item.name.begins_with("TOKEN"):
						p = load("res://scenes/TOKEN.tscn").instance()
					else:
						p = load("res://scenes/obstacles/" + n[0].to_lower() + ".tscn").instance()
					p.name = item.name
					p.transform.origin = Vector3(item.x, item.y, item.z)
					p.rotation = Vector3(item.rx, item.ry, item.rz)
					s.add_child(p)
					p.set_owner(root)
