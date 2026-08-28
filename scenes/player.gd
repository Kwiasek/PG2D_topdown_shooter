extends CharacterBody2D
class_name Player

@export var speed: float = 250.0
@export var max_health: float = 100.0
var health: float
var spawn_position: Vector2

signal health_changed(current_health: float, max_health: float)
signal player_died
signal player_respawned

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	health = max_health
	spawn_position = global_position

func _physics_process(delta: float) -> void:
	# Ruch w 8 kierunkach
	var input_vector := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = input_vector * speed
	move_and_slide()
	
	# Obrót sprite'a w stronę kierunku biegu
	if velocity.length() > 5.0 and sprite:
		sprite.rotation = lerp_angle(sprite.rotation, velocity.angle(), 14.0 * delta)

func take_damage(amount: float) -> void:
	health -= amount
	health_changed.emit(health, max_health)
	print("Gracz otrzymał obrażenia! Aktualne HP: ", health)
	
	modulate = Color.RED
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.15)
	
	if health <= 0:
		die()

func die() -> void:
	print("Gracz zginął! Respawn...")
	player_died.emit()
	respawn()

func respawn() -> void:
	health = max_health
	global_position = spawn_position
	velocity = Vector2.ZERO
	health_changed.emit(health, max_health)
	
	# Krótki efekt wizualny respawnu (zielonkawe mignięcie)
	modulate = Color(0.5, 1.0, 0.5, 0.7)
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.3)
	player_respawned.emit()
	print("Gracz zrespawnowany w punkcie startowym!")
