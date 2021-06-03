extends Node

# use signals to decouple events within the game
# to allow many nodes (deep down in the hierarchy)
# easily react to events
signal on_coin_magnet_collision
signal on_toggle_magnet
signal on_unload_part
signal on_obstacle
signal on_collect
signal on_die

# smootly lerp between two rotations
func slerp_look_at(t : Transform, dir, delta):
	 return t.basis.slerp(t.looking_at(dir, Vector3.UP).basis, delta)
