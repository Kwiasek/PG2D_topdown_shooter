extends CharacterBody2D
class_name Player

@export var speed: float = 250.0
@export var max_health: float = 100.0
var health: float

signal health_changed(current_health: float, max_health: float)
signal player_died

func _ready() -> void:
	health = max_health
	
func _physics_process(delta: float) -> void:
	var input_vector := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = input_vector * speed
	move_and_slide()
	
	look_at(get_global_mouse_position())

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
	print("Gracz zginął!")
	player_died.emit()
