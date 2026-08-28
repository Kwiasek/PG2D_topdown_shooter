extends Area2D
class_name Bullet

@export var speed: float = 450.0
@export var damage: float = 10.0
@export var lifetime: float = 3.0

var direction: Vector2 = Vector2.RIGHT
var shooter: Node2D = null

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	
	var timer = get_tree().create_timer(lifetime)
	timer.timeout.connect(queue_free)

func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	
func _on_body_entered(body: Node2D) -> void:
	if body == shooter or body is Enemy:
		return
		
	print("Pocisk uderzył w obiekt: ", body.name)
	
	if body.has_method("take_damage"):
		body.take_damage(damage)
	
	queue_free()
