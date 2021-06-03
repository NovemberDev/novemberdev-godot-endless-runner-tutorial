extends Spatial

var cam_transform
var look_at_direction
var target_look_at_direction

var lane_index = 1
var rotation_speed = 5.0
var cam_position
var cam_rotation_speed = 5.0

var shake_intensity = 0
var vertical_force = 0.0
var magnet_active = false
var dead = false

func _ready():
	cam_position = $ANCHOR/MESH/Camera.transform.origin
	look_at_direction = global_transform.basis.z
	cam_transform = $ANCHOR/MESH/Camera.transform
	target_look_at_direction = global_transform.basis.z
	$ANCHOR/MESH/MODEL/AnimationTree.active = true
	$ANCHOR/MESH/MODEL/AnimationTree.set("parameters/state/current", 1)
	$ANCHOR/MESH/MODEL/SENSOR.connect("body_entered", self, "on_collision")
	$ANCHOR/MESH/MODEL/MAGNET_SENSOR.connect("body_entered", self, "on_magnet_collision")
	Globals.connect("on_die", self, "on_die")
	Globals.connect("on_toggle_magnet", self, "on_toggle_magnet")

func _process(delta):
	# camera shake
	if shake_intensity > 0.0:
		shake_intensity -= delta
		$ANCHOR/MESH/Camera.transform.origin = cam_position + 2.0 * shake_intensity * Vector3(cos(0.05 * OS.get_system_time_msecs()), sin(0.05 * OS.get_system_time_msecs()), 0.0)
	
	# do not process any further, if the player s dead
	if dead: return
	
	# look towards the walking direction
	look_at_direction = lerp(look_at_direction, target_look_at_direction, delta * 5.0)
	$ANCHOR.global_transform.basis = Globals.slerp_look_at($ANCHOR.global_transform, global_transform.origin + look_at_direction, cam_rotation_speed * delta)
	$ANCHOR/MESH/MODEL.global_transform.basis = Globals.slerp_look_at($ANCHOR/MESH/MODEL.global_transform, $ANCHOR/MESH/MODEL.global_transform.origin - look_at_direction + Vector3.UP, rotation_speed * delta)

	# lerp the player between lanes
	$ANCHOR/MESH.transform.origin.x = lerp($ANCHOR/MESH.transform.origin.x, (lane_index * 5) - 5, delta * 15.0)
	$ANCHOR/MESH.transform.origin.x = clamp($ANCHOR/MESH.transform.origin.x, -5, 5)

	# strafe left or right while animating and changing lane indices
	if Input.is_action_just_pressed("r_left"):
		$ANCHOR/MESH/MODEL/AnimationTree.set("parameters/strafe_state/current", 0)
		$ANCHOR/MESH/MODEL/AnimationTree.set("parameters/strafe/active", true)
		switch_lane(-1)
	if Input.is_action_just_pressed("r_right"):
		$ANCHOR/MESH/MODEL/AnimationTree.set("parameters/strafe_state/current", 1)
		$ANCHOR/MESH/MODEL/AnimationTree.set("parameters/strafe/active", true)
		switch_lane(1)
		
	# jump and slowly lerp the player back towards the ground
	if Input.is_action_just_pressed("r_jump") and $ANCHOR/MESH.transform.origin.y < 1:
		vertical_force = 5
	vertical_force = lerp(vertical_force, -3, 5.0 * delta)
	
	if vertical_force > 0:
		$ANCHOR/MESH/MODEL/AnimationTree.set("parameters/state/current", 2)
	elif $ANCHOR/MESH.transform.origin.y > 0:
		$ANCHOR/MESH/MODEL/AnimationTree.set("parameters/state/current", 3)
	else:
		$ANCHOR/MESH/MODEL/AnimationTree.set("parameters/state/current", 1)
		vertical_force = 0
	
	$ANCHOR/MESH.transform.origin.y += vertical_force
	$ANCHOR/MESH.transform.origin.y = clamp($ANCHOR/MESH.transform.origin.y, 0, 40)

	# simulate gravity
	if global_transform.origin.y > 0:
		global_transform.origin.y -= delta * 10.0
	
	# simulate run camera shake
	if shake_intensity <= 0.0:
		$ANCHOR/MESH/Camera.transform.origin.x = 0.35 * cos(0.0075 * OS.get_system_time_msecs())
		$ANCHOR/MESH/Camera.transform.origin.y = cam_position.y + 0.35 * sin(0.0075 * OS.get_system_time_msecs())
		
func set_look_at(dir):
	target_look_at_direction = dir * 10.0

func switch_lane(dir):
	lane_index += dir
	if lane_index > 2:
		lane_index = 2
	if lane_index < 0:
		lane_index = 0

# determine what happens on collision
func on_collision(body):
	if body.is_in_group("coin"):
		Globals.emit_signal("on_collect", "coin")
		ObjectPooling.queue_free_instance(body)
	if body.is_in_group("magnet"):
		Globals.emit_signal("on_collect", "magnet")
		ObjectPooling.queue_free_instance(body)
	if body.is_in_group("obstacle"):
		shake_intensity = 0.5
		Globals.emit_signal("on_obstacle")

func on_die():
	dead = true
	$ANCHOR/MESH/MODEL/AnimationTree.set("parameters/dead/blend_amount", 1.0)

func on_toggle_magnet(activate):
	$ANCHOR/MESH/MODEL/AnimationTree.set("parameters/magnet/blend_amount", int(activate))
	$ANCHOR/MESH/MODEL/bee/rig/Skeleton/MAGNET.visible = activate
	magnet_active = activate

func on_magnet_collision(body):
	if body.is_in_group("coin") and magnet_active:
		Globals.emit_signal("on_coin_magnet_collision", body)
