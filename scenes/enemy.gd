extends CharacterBody2D
class_name Enemy

@export var speed: float = 160.0
@export var ray_count: int = 16
@export var look_ahead_distance: float = 80.0
@export var attack_range: float = 35.0
@export var damage: float = 15.0
@export var attack_cooldown: float = 1.0

var player: Node2D = null
var ray_directions: Array[Vector2] = []
var chosen_dir: Vector2 = Vector2.ZERO

# Zmienne zapobiegające blokowaniu się (Anti-stuck / Wall Following)
var stuck_timer: float = 0.0
var avoid_side: float = 1.0 # 1.0 = prawo, -1.0 = lewo
var attack_timer: float = 0.0

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
	
	var dist_to_player = global_position.distance_to(player.global_position)
	var dir_to_player = (player.global_position - global_position).normalized()
	
	# Obrót w stronę wybranego kierunku ruchu lub gracza
	if velocity.length() > 10.0:
		rotation = lerp_angle(rotation, velocity.angle(), 10.0 * delta)
	else:
		rotation = lerp_angle(rotation, dir_to_player.angle(), 10.0 * delta)
	
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
