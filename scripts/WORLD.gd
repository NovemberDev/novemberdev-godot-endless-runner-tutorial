extends Spatial

var coins = 0
var parts = {}
var dead = false
var distance = 0
var speed_time = 0.0
var dead_timer = 0.0
var magnet_coins = []
var magnet_time = 0.0
var total_speed = 0.0
var current_speed = 40
var themes = ["TERRAN"]
var part_instances = []
var part_free_queue = []
var obstacle_scenes = {}
var obstacle_layouts = {}
var left_turn_counter = 0
var right_turn_counter = 0
var spawn_part_counter = 0
var current_theme_index = 0
var theme_switch_time = 45.0
var part_lane_coordinates = []
var current_direction = -Vector3.FORWARD

# This script controls the entire game state.
# It spawns and moves the parts around the player
# given the pre-recorded and current lane-points
# where the player is close to.

func _ready():
	prepare_parts()
	preparte_obstacles()
	preparte_obstacle_scenes()
	Globals.connect("on_collect", self, "on_collect")
	Globals.connect("on_obstacle", self, "on_obstacle")
	$Control/SPEEDBTN.connect("pressed", self, "on_speed")
	Globals.connect("on_unload_part", self, "on_unload_part")
	Globals.connect("on_coin_magnet_collision", self, "on_coin_magnet_collision")
	
	# spawn a few parts in the beginning
	# the index makes sure no obstacles are spawned
	for i in 5:
		spawn_next_part(i)
		yield(get_tree(), "idle_frame")

func _process(delta):
	current_speed += delta * 0.4
	distance += delta * current_speed * 0.1
	$Control/COINS.text = "%s Coins" % [int(coins)]
	$Control/DISTANCE.text = "%s Distance" % [int(distance)]
	$Control/SPEED.text = "%s Speed" % [int(current_speed)]
	
	# switch the theme based on time
	theme_switch_time -= delta
	if theme_switch_time <= 0.0:
		theme_switch_time = 45.0
		current_theme_index += 1
		if current_theme_index > themes.size()-1:
			current_theme_index = 0
			
	# activate super speed
	if speed_time > 0.0:
		speed_time -= delta 
		total_speed = min(current_speed + 50.0, 200.0)
	else:
		total_speed = current_speed
		
	# reload the game if the player is dead for a time
	if dead:
		dead_timer -= delta
		if dead_timer < 0.0:
			for part in $PARTS.get_children():
				ObjectPooling.queue_free_instance(part)
			get_tree().reload_current_scene()
		return
		
	# move collected coins towards the player
	# if the player carries a magnet
	for coin in magnet_coins:
		if !coin.is_inside_tree():
			magnet_coins.erase(coin)
		else:
			coin.global_transform.origin += delta * 80.0 * ($PLAYER.get_node("ANCHOR/MESH/MODEL").global_transform.origin - coin.global_transform.origin).normalized()
		
	# deactivate magnet after some time
	if magnet_time > 0:
		magnet_time -= delta
		if magnet_time < 0:
			Globals.emit_signal("on_toggle_magnet", false)
		
	# if parts are marked to be removed,
	# remove them if a certain distance is reached,
	# so the player doesn't notice
	while part_free_queue.size() > 0:
		var part_free_instance = part_free_queue[0]
		if part_free_instance.global_transform.origin.distance_to($PLAYER.global_transform.origin) > 150:
			part_free_instance.visited = true
			part_free_queue.pop_front()
		else:
			break

	# check if the current lane point is on a different part
	# than the next one, if it is, mark the current part for unloading
	if part_lane_coordinates[0].name != part_lane_coordinates[1].name:
		if part_free_queue.find($PARTS.get_node(part_lane_coordinates[0].name)) == -1:
			part_free_queue.push_back($PARTS.get_node(part_lane_coordinates[0].name))
	
	var current_lane_coordinate = part_lane_coordinates[0].point.global_transform.origin
	
	# if the player reached the point, go to the next by popping it off the lane point stack
	if current_lane_coordinate.distance_to($PLAYER.global_transform.origin) < 3.0:
		part_lane_coordinates.pop_front()
	
	current_direction = (current_lane_coordinate - $PLAYER.global_transform.origin).normalized()
	$PLAYER.set_look_at(current_direction)
	
	# move the world around the player
	$PARTS.global_transform.origin -= current_direction * delta * total_speed
	$PARTS.global_transform.origin.y = 0
	
	# automatically spawn more parts if parts have been unloaded
	if spawn_part_counter > 0:
		for i in range(spawn_part_counter):
			spawn_next_part(10)
		spawn_part_counter = 0

# unload the part and check how many turns are unloaded
func on_unload_part(part):
	match part.type:
		"RCURVE":
			right_turn_counter -= 1
		"LCURVE":
			left_turn_counter -= 1
	part_instances.erase(part)
	spawn_part_counter += 1

# spawn a new part
func spawn_next_part(index):
	randomize()
	
	# get any part by the current theme index
	var part = parts[themes[current_theme_index]][randi()%parts[themes[current_theme_index]].size()]
	
	# check if our amount of turns doesn't produce overlaps
	match part.type:
		"LCURVE":
			if left_turn_counter > 0 or index < 4:
				return spawn_next_part(index)
			left_turn_counter += 1
		"RCURVE":
			if right_turn_counter > 0 or index < 4:
				return spawn_next_part(index)
			right_turn_counter += 1
	
	var part_instance = ObjectPooling.load_from_pool(part.file)
	
	# spawn obstacles
	initialize_part(part, part_instance, index)
	$PARTS.add_child(part_instance)
	
	if part_instance.has_node("OBJECT_LAYOUTS"):
		print("Warning: " + str(part.file) + " has uncompiled OBJECT_LAYOUTS, this can lead to invisible collisions")
	
	# connect the parts by getting the last part's front position,
	# align the back position of the new part on that
	# and make it look towards it's front facing direction
	if part_instances.size() > 0:
		var latest_part = part_instances[part_instances.size()-1]
		part_instance.global_transform.origin = latest_part.get_node("FRONT").global_transform.origin
		part_instance.look_at(
			part_instance.global_transform.origin 
			- (latest_part.get_node("FRONT").global_transform.origin 
				- latest_part.get_node("FRONT_DIRECTION").global_transform.origin).normalized(), 
			Vector3.UP)
		part_instance.global_transform.origin -= (part_instance.get_node("BACK").global_transform.origin - part_instance.global_transform.origin)
		part_instance.global_transform.origin.y = 0
		
	# record all lane points of that part
	initialize_lane_points(part_instance, index)
	part_instances.push_back(part_instance)
	
# record all lane points for that part instance
func initialize_lane_points(part_instance, index):
	for lane_point in part_instance.get_node("LANE").get_children():
		# if point is behind player, skip it
		if index < 2:
			if($PLAYER.global_transform.origin - lane_point.global_transform.origin).normalized().dot($PLAYER.global_transform.basis.z) < 0:
				continue
		part_lane_coordinates.push_back({ 
			name = part_instance.name,
			point = lane_point
		})
	
	part_instances.push_back(part_instance)
	
# spawn obstacles on that part
func initialize_part(part, part_instance, index):
	
	# don't spawn obstacles for the first two parts
	# to not immediately collide with something on spawn
	if index < 2: 
		return
	if obstacle_layouts.has(part.type):
		var layouts = obstacle_layouts[part.type]
		var layout = layouts[randi()%layouts.size()]
		
		# extend this to override what has to happen
		# with that pickup below
		var pickups = ["MAGNET"]
		for obstacle in layout.children:
			randomize()
			var object_instance = null
			# override behaviour for some pickups and obstacles
			if obstacle.name.begins_with("COIN"):
				object_instance = ObjectPooling.load_from_pool("res://scenes/COIN.tscn")
			elif pickups.find(obstacle.name.split('_')[0]) != -1:
				object_instance = ObjectPooling.load_from_pool("res://scenes/" + pickups[randi()%pickups.size()] + ".tscn")
			else:
				var obstacle_type = obstacle.name.split('_')[0]
				var obstacle_file = obstacle_scenes[obstacle_type + "_" + themes[current_theme_index]][randi()%obstacle_scenes[obstacle_type + "_" + themes[current_theme_index]].size()]
				object_instance = ObjectPooling.load_from_pool(obstacle_file.file)
			part_instance.get_node("OBSTACLES").add_child(object_instance)
			object_instance.transform.origin = Vector3(obstacle.x, obstacle.y, obstacle.z)
			object_instance.rotation = Vector3(obstacle.rx, obstacle.ry, obstacle.rz)
			object_instance.visible = true
			
func prepare_parts():
	# this method gets all scenes inside res://scenes/parts
	# and stores them inside parts by their theme (Space...)
	# to store their scene paths
	var dir = Directory.new()
	var path = "res://scenes/parts"
	if dir.open(path) == OK:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if !dir.current_is_dir():
				var part = {
					file = path + "/" + file_name,
					type = file_name.split('_')[0],
					theme = file_name.split('_')[1],
					difficulty = file_name.split('_')[2].replace(".tscn", "")
				}
				if !parts.has(part.theme):
					parts[part.theme] = []
				parts[part.theme].push_back(part) 
			file_name = dir.get_next()
	else:
		print("WORLD.gd: error loading res://scenes/parts/*")

func preparte_obstacles():
	# this method gets all scenes inside res://scenes/obstacles
	# and stores them inside obstacle_types  by their type (middle, single, side)
	# to store their scene path inside the respective array
	var file = File.new()
	if file.open("res://compiled_parts.tres", File.READ) != 0:
		print("World.gd: error reading compiled_parts.tres")
	else:
		obstacle_layouts = JSON.parse(file.get_as_text()).result

# get all obstacles and store them inside a dictionary for quick retrieval
func preparte_obstacle_scenes():
	var dir = Directory.new()
	var path = "res://scenes/obstacle_scenes"
	if dir.open(path) == OK:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if !dir.current_is_dir():
				var obstacle_scene = {
					file = path + "/" + file_name,
					type = file_name.split('_')[0],
					theme = file_name.split('_')[1]
				}
				if !obstacle_scenes.has(obstacle_scene.type + "_" + obstacle_scene.theme):
					obstacle_scenes[obstacle_scene.type + "_" + obstacle_scene.theme] = []
				obstacle_scenes[obstacle_scene.type + "_" + obstacle_scene.theme].push_back(obstacle_scene) 
			file_name = dir.get_next()
	else:
		print("WORLD.gd: error loading res://scenes/obstace_scenes/*")

# deterime what happens when you collect a pickup
func on_collect(type):
	match type:
		"magnet":
			Globals.emit_signal("on_toggle_magnet", true)
			magnet_time = 8.0
		"coin":
			coins += 1
			$Control/COINLEVEL.value = min($Control/COINLEVEL.value + 4.0, 100.0)
			if $Control/COINLEVEL.value == 100.0:
				$Control/SPEEDBTN.disabled = false

func on_coin_magnet_collision(body):
	magnet_coins.push_back(body)

# control what happens when you collide with an obstacle
func on_obstacle():
	if dead:
		return
	if speed_time > 0.0:
		return
	if current_speed < 50:
		Globals.emit_signal("on_die")
		$Control/SPEEDBTN.disabled = true
		dead_timer = 2.0
		dead = true
	else:
		current_speed -= 10.0
		
func on_speed():
	speed_time = 10.0
	$Control/COINLEVEL.value = 0
	$Control/SPEEDBTN.disabled = true
