extends CharacterBody2D
class_name Enemy

enum WeaponMode { MELEE, RANGED }
enum CombatStance { RANGED_HARASS, MELEE_CHARGE }

@export var speed: float = 160.0
@export var charge_speed_multiplier: float = 1.25

# Statystyki broni
@export var bullet_scene: PackedScene = preload("res://scenes/bullet.tscn")
@export var melee_range: float = 35.0
@export var melee_switch_threshold: float = 90.0
@export var ranged_min_distance: float = 140.0
@export var ranged_max_range: float = 420.0

@export var melee_damage: float = 20.0
@export var melee_cooldown: float = 0.8
@export var ranged_cooldown: float = 1.0

# Skok
@export var jump_duration: float = 0.45
@export var jump_trigger_distance: float = 75.0
var is_jumping: bool = false
var jump_cooldown_timer: float = 0.0

# Stan przeciwnika
var current_weapon: WeaponMode = WeaponMode.RANGED
var combat_stance: CombatStance = CombatStance.RANGED_HARASS
var stance_timer: float = 4.0

var player: Node2D = null
var tilemap: TileMapLayer = null
var attack_timer: float = 0.0

# Zmienne Flow Field i Taktyki
var dist_grid: Dictionary = {}
var flow_recalc_timer: float = 0.0
var last_player_cell: Vector2i = Vector2i(-9999, -9999)
var smoothed_dir: Vector2 = Vector2.ZERO

var flank_side: float = 1.0
var flank_switch_timer: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	call_deferred("_initialize")

func _initialize() -> void:
	player = get_tree().get_first_node_in_group("player")
	if not player:
		player = get_parent().get_node_or_null("Player")
	
	tilemap = get_parent().get_node_or_null("TileMapLayer")
	if not tilemap:
		for child in get_parent().get_children():
			if child is TileMapLayer:
				tilemap = child
				break

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	
	attack_timer -= delta
	jump_cooldown_timer -= delta
	flow_recalc_timer -= delta
	flank_switch_timer -= delta
	stance_timer -= delta
	
	# Cykliczna zmiana postawy taktycznej
	if stance_timer <= 0.0:
		if combat_stance == CombatStance.RANGED_HARASS:
			combat_stance = CombatStance.MELEE_CHARGE
			stance_timer = randf_range(3.5, 5.0) # Szarżuj przez 3.5-5 sekund
		else:
			combat_stance = CombatStance.RANGED_HARASS
			stance_timer = randf_range(4.0, 6.0) # Ostrzeliwuj przez 4-6 sekund
	
	# Zmiana kierunku flankowania
	if flank_switch_timer <= 0.0:
		if randf() > 0.4:
			flank_side *= -1.0
		flank_switch_timer = randf_range(2.0, 3.5)
	
	if is_jumping:
		move_and_slide()
		return
	
	var dist_to_player = global_position.distance_to(player.global_position)
	var dir_to_player = (player.global_position - global_position).normalized()
	var has_los = check_line_of_sight()
	var jumpable_in_front = check_jumpable_barrier_to_player(dir_to_player)
	
	# Wybór broni
	update_weapon_choice(dist_to_player, has_los)
	
	# Obrót
	if current_weapon == WeaponMode.RANGED and has_los:
		rotation = lerp_angle(rotation, dir_to_player.angle(), 12.0 * delta)
	elif velocity.length() > 10.0:
		rotation = lerp_angle(rotation, velocity.angle(), 10.0 * delta)
	else:
		rotation = lerp_angle(rotation, dir_to_player.angle(), 10.0 * delta)
	
	# Sprawdzenie skoku
	if jump_cooldown_timer <= 0.0 and dist_to_player > melee_range:
		if should_jump_over_obstacle(dir_to_player):
			perform_jump(dir_to_player)
			return
	
	# Logika ataku
	if current_weapon == WeaponMode.MELEE:
		if dist_to_player <= melee_range:
			velocity = Vector2.ZERO
			if attack_timer <= 0.0:
				perform_melee_attack()
				attack_timer = melee_cooldown
			move_and_slide()
			return
	elif current_weapon == WeaponMode.RANGED:
		if has_los and dist_to_player <= ranged_max_range:
			if attack_timer <= 0.0:
				shoot_projectile(dir_to_player)
				attack_timer = ranged_cooldown
	
	# Wyznaczenie wektora ruchu
	var target_dir = Vector2.ZERO
	var current_speed = speed
	
	# Jeśli przed nami jest niska przeszkoda, biegniemy prosto na nią, aby ją przeskoczyć
	if jumpable_in_front:
		target_dir = dir_to_player
	elif combat_stance == CombatStance.MELEE_CHARGE or current_weapon == WeaponMode.MELEE:
		# FAZA SZARŻY: Zwiększona prędkość, bieg prosto do gracza
		current_speed = speed * charge_speed_multiplier
		if has_los:
			target_dir = dir_to_player
		else:
			target_dir = get_flow_field_direction()
	elif has_los and current_weapon == WeaponMode.RANGED:
		# FAZA OSTRZAŁU I FLANKOWANIA: Krążenie wokół gracza na dystans
		var strafe_vector = dir_to_player.orthogonal() * flank_side
		if dist_to_player < ranged_min_distance:
			target_dir = (-dir_to_player * 0.5 + strafe_vector * 0.7).normalized()
		else:
			target_dir = (dir_to_player * 0.2 + strafe_vector * 0.9).normalized()
	else:
		# Gracz za budynkiem/ścianą – Flow Field
		target_dir = get_flow_field_direction()
	
	# Bufor odpychania od krawędzi ścian
	var clearance_push = calculate_wall_clearance_push()
	var final_move_dir = (target_dir + clearance_push).normalized()
	
	smoothed_dir = smoothed_dir.lerp(final_move_dir, 10.0 * delta)
	if smoothed_dir.length() > 0.05:
		velocity = velocity.move_toward(smoothed_dir.normalized() * current_speed, current_speed * 8.0 * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, current_speed * 8.0 * delta)
	
	move_and_slide()

func check_jumpable_barrier_to_player(dir_to_player: Vector2) -> bool:
	var space_state = get_world_2d().direct_space_state
	var jumpable_mask = 1 << 1 # Layer 2 (World_Jumpable)
	var query = PhysicsRayQueryParameters2D.create(
		global_position,
		global_position + dir_to_player * 130.0,
		jumpable_mask
	)
	query.exclude = [self]
	var result = space_state.intersect_ray(query)
	return not result.is_empty()

func update_weapon_choice(dist: float, has_los: bool) -> void:
	# Przełączamy na Melee gdy jesteśmy blisko LUB w trakcie aktywnej szarży
	if dist <= melee_switch_threshold or combat_stance == CombatStance.MELEE_CHARGE or not has_los:
		if current_weapon != WeaponMode.MELEE:
			current_weapon = WeaponMode.MELEE
			modulate = Color(1.0, 0.7, 0.7) # Czerwony odcień w zwarciu/szarży
	else:
		if current_weapon != WeaponMode.RANGED:
			current_weapon = WeaponMode.RANGED
			modulate = Color.WHITE

func get_flow_field_direction() -> Vector2:
	if not tilemap:
		return (player.global_position - global_position).normalized()
	
	var player_cell = tilemap.local_to_map(tilemap.to_local(player.global_position))
	var my_cell = tilemap.local_to_map(tilemap.to_local(global_position))
	
	if player_cell != last_player_cell or flow_recalc_timer <= 0.0:
		recalculate_flow_field(player_cell)
		last_player_cell = player_cell
		flow_recalc_timer = 0.2
	
	var best_cell = my_cell
	var min_dist = dist_grid.get(my_cell, 99999.0)
	
	var neighbors = [
		Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)
	]
	
	for offset in neighbors:
		var n_cell = my_cell + offset
		if n_cell in dist_grid:
			var d = dist_grid[n_cell]
			if d < min_dist:
				if offset.x != 0 and offset.y != 0:
					if is_cell_solid(my_cell + Vector2i(offset.x, 0)) or is_cell_solid(my_cell + Vector2i(0, offset.y)):
						continue
				min_dist = d
				best_cell = n_cell
	
	if best_cell != my_cell:
		var target_world_pos = tilemap.to_global(tilemap.map_to_local(best_cell))
		return (target_world_pos - global_position).normalized()
	
	return (player.global_position - global_position).normalized()

func recalculate_flow_field(target_cell: Vector2i) -> void:
	dist_grid.clear()
	
	var queue: Array[Vector2i] = []
	dist_grid[target_cell] = 0.0
	queue.append(target_cell)
	
	var neighbors = [
		Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)
	]
	
	var max_steps = 1500
	var step_count = 0
	
	while queue.size() > 0 and step_count < max_steps:
		step_count += 1
		var current = queue.pop_front()
		var current_dist = dist_grid[current]
		
		for offset in neighbors:
			var n_cell = current + offset
			if n_cell in dist_grid:
				continue
			
			if is_cell_solid(n_cell):
				continue
			
			if offset.x != 0 and offset.y != 0:
				if is_cell_solid(current + Vector2i(offset.x, 0)) and is_cell_solid(current + Vector2i(0, offset.y)):
					continue
			
			var move_cost = 1.0 if (offset.x == 0 or offset.y == 0) else 1.414
			if is_near_wall(n_cell):
				move_cost += 0.35
			
			dist_grid[n_cell] = current_dist + move_cost
			queue.append(n_cell)

func is_cell_solid(cell: Vector2i) -> bool:
	if not tilemap:
		return false
	var tile_data = tilemap.get_cell_tile_data(cell)
	if not tile_data:
		return false
	return tile_data.get_collision_polygons_count(0) > 0

func is_near_wall(cell: Vector2i) -> bool:
	var cardinal_offsets = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for off in cardinal_offsets:
		if is_cell_solid(cell + off):
			return true
	return false

func calculate_wall_clearance_push() -> Vector2:
	var space_state = get_world_2d().direct_space_state
	var push = Vector2.ZERO
	var whisker_dirs = [
		Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT,
		Vector2(-1, -1).normalized(), Vector2(1, -1).normalized(),
		Vector2(-1, 1).normalized(), Vector2(1, 1).normalized()
	]
	
	var clearance_dist = 40.0
	
	for dir in whisker_dirs:
		var query = PhysicsRayQueryParameters2D.create(
			global_position,
			global_position + dir * clearance_dist,
			collision_mask
		)
		query.exclude = [self]
		var result = space_state.intersect_ray(query)
		
		if result:
			var dist = global_position.distance_to(result.position)
			var strength = 1.0 - (dist / clearance_dist)
			push += result.normal * (strength * 0.7)
	
	return push

func check_line_of_sight() -> bool:
	if not is_instance_valid(player):
		return false
	
	var space_state = get_world_2d().direct_space_state
	var mask = (1 << 0) | (1 << 1)
	var query = PhysicsRayQueryParameters2D.create(
		global_position,
		player.global_position,
		mask
	)
	query.exclude = [self]
	var result = space_state.intersect_ray(query)
	return result.is_empty()

func shoot_projectile(direction: Vector2) -> void:
	if not bullet_scene:
		return
	
	var bullet = bullet_scene.instantiate() as Bullet
	bullet.global_position = global_position + direction * 30.0
	bullet.direction = direction
	bullet.rotation = direction.angle()
	bullet.shooter = self
	
	get_parent().add_child(bullet)

func perform_melee_attack() -> void:
	if player and player.has_method("take_damage"):
		player.take_damage(melee_damage)

func should_jump_over_obstacle(dir_to_player: Vector2) -> bool:
	var space_state = get_world_2d().direct_space_state
	var jumpable_mask = 1 << 1
	var query = PhysicsRayQueryParameters2D.create(
		global_position,
		global_position + dir_to_player * jump_trigger_distance,
		jumpable_mask
	)
	query.exclude = [self]
	var result = space_state.intersect_ray(query)
	
	if result:
		var land_pos = result.position + dir_to_player * 70.0
		var solid_mask = 1 << 0
		var solid_query = PhysicsRayQueryParameters2D.create(
			result.position,
			land_pos,
			solid_mask
		)
		solid_query.exclude = [self]
		var solid_result = space_state.intersect_ray(solid_query)
		return solid_result.is_empty()
	
	return false

func perform_jump(jump_direction: Vector2) -> void:
	is_jumping = true
	jump_cooldown_timer = 1.2
	set_collision_mask_value(2, false)
	
	var start_pos = global_position
	var target_land_pos = start_pos + jump_direction * 140.0
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(self, "global_position", target_land_pos, jump_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	if sprite:
		var jump_height: float = 20.0
		var sprite_tween = create_tween()
		sprite_tween.tween_property(sprite, "offset:y", -jump_height, jump_duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		sprite_tween.tween_property(sprite, "offset:y", 0.0, jump_duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		
		var scale_tween = create_tween()
		scale_tween.tween_property(sprite, "scale", Vector2(1.25, 1.25), jump_duration * 0.5)
		scale_tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), jump_duration * 0.5)
	
	await tween.finished
	velocity = Vector2.ZERO
	set_collision_mask_value(2, true)
	is_jumping = false
