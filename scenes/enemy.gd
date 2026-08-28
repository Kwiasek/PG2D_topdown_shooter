extends CharacterBody2D
class_name Enemy

@export var speed: float = 160.0
@export var ray_count: int = 16
@export var look_ahead_distance: float = 80.0
@export var attack_range: float = 35.0
@export var damage: float = 15.0
@export var attack_cooldown: float = 1.0

@export var jump_speed: float = 240.0
@export var jump_duration: float = 0.45
@export var jump_trigger_distance: float = 65.0
var is_jumping: bool = false
var jump_cooldown_timer: float = 0.0

var player: Node2D = null
var ray_directions: Array[Vector2] = []
var chosen_dir: Vector2 = Vector2.ZERO

# Zmienne zapobiegające blokowaniu się (Anti-stuck / Wall Following)
var stuck_timer: float = 0.0
var avoid_side: float = 1.0 # 1.0 = prawo, -1.0 = lewo
var attack_timer: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	ray_directions.resize(ray_count)
	for i in range(ray_count):
		var angle = i * 2.0 * PI / ray_count
		ray_directions[i] = Vector2.RIGHT.rotated(angle)
	
	call_deferred("_find_player")

func _find_player() -> void:
	player = get_tree().get_first_node_in_group("player")
	if not player:
		player = get_parent().get_node_or_null("Player")

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	
	attack_timer -= delta
	jump_cooldown_timer -= delta
	
	if is_jumping:
		move_and_slide()
		return
	
	var dist_to_player = global_position.distance_to(player.global_position)
	var dir_to_player = (player.global_position - global_position).normalized()
	
	# Obrót w stronę wybranego kierunku ruchu lub gracza
	if velocity.length() > 10.0:
		rotation = lerp_angle(rotation, velocity.angle(), 10.0 * delta)
	else:
		rotation = lerp_angle(rotation, dir_to_player.angle(), 10.0 * delta)
	
	# Sprawdzenie możliwości przeskoczenia przeszkody
	if jump_cooldown_timer <= 0.0 and dist_to_player > attack_range:
		if should_jump_over_obstacle(dir_to_player):
			perform_jump(dir_to_player)
			return
	
	# Atak wręcz w zasięgu
	if dist_to_player <= attack_range:
		velocity = Vector2.ZERO
		if attack_timer <= 0.0:
			perform_melee_attack()
			attack_timer = attack_cooldown
		move_and_slide()
		return
	
	# Obliczenie optymalnego kierunku
	var target_direction = get_context_steering_direction(player.global_position)
	
	# 4. Ruch
	velocity = velocity.move_toward(target_direction * speed, speed * 8.0 * delta)
	move_and_slide()
	
	# Wykrywanie utknięcia i zmiana kierunku omijania
	if velocity.length() < speed * 0.2 and target_direction.length() > 0.1:
		stuck_timer += delta
		if stuck_timer > 0.3:
			avoid_side *= -1.0 # Zmiana strony omijania ściany
			stuck_timer = 0.0
	else:
		stuck_timer = max(0.0, stuck_timer - delta)

func should_jump_over_obstacle(dir_to_player: Vector2) -> bool:
	var space_state = get_world_2d().direct_space_state
	
	var jumpable_mask = 1 << 1 # Bit 2
	var query = PhysicsRayQueryParameters2D.create(
		global_position,
		global_position + dir_to_player * jump_trigger_distance,
		jumpable_mask
	)
	query.exclude = [self]
	var result = space_state.intersect_ray(query)
	
	if result:
		# Obliczenie punktu lądowania
		var land_pos = result.position + dir_to_player * 70.0
		
		var solid_mask = 1 << 0 # Bit 1
		var solid_query = PhysicsRayQueryParameters2D.create(
			result.position,
			land_pos,
			solid_mask
		)
		solid_query.exclude = [self]
		var solid_result = space_state.intersect_ray(solid_query)
		
		# Przeciwnik skacze jeżeli nie wbije się w solidną ścianę
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
		# Uniesienie w górę (offset w osi Y)
		var sprite_tween = create_tween()
		sprite_tween.tween_property(sprite, "offset:y", -jump_height, jump_duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		sprite_tween.tween_property(sprite, "offset:y", 0.0, jump_duration * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

		# Skalowanie dla efektu 3D
		var scale_tween = create_tween()
		scale_tween.tween_property(sprite, "scale", Vector2(1.25, 1.25), jump_duration * 0.5)
		scale_tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), jump_duration * 0.5)

	# Po zakończeniu ruchu lądujemy i przywracamy kolizję
	await tween.finished

	velocity = Vector2.ZERO
	set_collision_mask_value(2, true)
	is_jumping = false

func get_context_steering_direction(target_pos: Vector2) -> Vector2:
	var desired_dir = (target_pos - global_position).normalized()
	var interest: Array[float] = []
	var danger: Array[float] = []
	
	interest.resize(ray_count)
	danger.resize(ray_count)
	
	# Interest Map
	for i in range(ray_count):
		var d = ray_directions[i].dot(desired_dir)
		# Wzmacniamy kierunek w stronę celu; wartości ujemne zerujemy
		interest[i] = max(0.0, d)
	
	# Danger Map
	var space_state = get_world_2d().direct_space_state
	for i in range(ray_count):
		var ray_dir = ray_directions[i]
		var query = PhysicsRayQueryParameters2D.create(
			global_position,
			global_position + ray_dir * look_ahead_distance,
			collision_mask # Sprawdzamy warstwy Solid i Jumpable
		)
		query.exclude = [self]
		var result = space_state.intersect_ray(query)
		
		if result:
			var dist = global_position.distance_to(result.position)
			danger[i] = 1.0 - (dist / look_ahead_distance)
		else:
			danger[i] = 0.0
	
	# Eliminacja kierunków zablokowanych i wzmocnienie kierunków bocznych przy ścianie
	var final_direction = Vector2.ZERO
	for i in range(ray_count):
		# Odejmujemy zagrożenie od zainteresowania
		var weight = interest[i] - (danger[i] * 1.5)
		
		if danger[i] > 0.4:
			var tangent_dir = ray_directions[i].orthogonal() * avoid_side
			var tangent_dot = tangent_dir.dot(desired_dir)
			if tangent_dot > 0.0:
				weight += tangent_dot * 0.6
		
		if weight > 0.0:
			final_direction += ray_directions[i] * weight
	
	return final_direction.normalized()

func perform_melee_attack() -> void:
	if player and player.has_method("take_damage"):
		player.take_damage(damage)
