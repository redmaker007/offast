extends Node
class_name email_generator
var instruction_list = [
	"Fire",
	"Raise",
	"Reduction",
	"Promotion"
]
var employee_list = [
"Jack", "Tom", "Kate", "Sam", "Leo",
"Mia", "Dan", "Zoe", "Max", "Amy",
"Ben", "Eve", "Cal", "Ivy", "Rex",
"Sue", "Jay", "Kim", "Roy", "Ann",
"Ted", "Meg", "Sid", "Fay", "Gus",
"Jan", "Ned", "Kay", "Lou", "Ray",
"Yuki", "Hana", "Jiro", "Minji", "Sora",
"Kenji", "Yuna", "Daiki", "Soyeon", "Riku",
"Omar", "Layla", "Tariq", "Nadia", "Kareem",
"Yasmin", "Samir", "Fatima", "Ziad", "Rania",
"Kofi", "Amara", "Kwame", "Zara", "Chidi",
"Nia", "Seun", "Adaeze", "Malik", "Yemi",
"Klaus", "Greta", "Hans", "Lena", "Fritz",
"Heike", "Kurt", "Brigitte", "Dieter", "Inge",
"Ivan", "Masha", "Dmitri", "Olga", "Alexei",
"Natasha", "Pavel", "Vera", "Sergei", "Anya",
"Carlos", "Sofia", "Diego", "Valentina", "Raj",
"Priya", "Arjun", "Anika", "Pierre", "Claire",
"Luc", "Chloe"
]

## 不放回抽样：这份名单会直接变成人事 app 的行，
## 有放回的话同一个人会出现两行，玩家没法分辨该填哪一行。
func get_random_employee_name(num:int):
	var pool = employee_list.duplicate()
	pool.shuffle()
	return pool.slice(0, mini(num, pool.size()))


func generate_email(_employee_list):

	var picked_instruction = instruction_list[randi() % instruction_list.size()]
	var picked_employee = _employee_list[randi() % _employee_list.size()]
	var picked_sender_class = randi() % 5
	
	var e = email.new()
	e.init_email("someone",picked_instruction,picked_employee,picked_sender_class)
	
	SignalBus.send_email.emit(e)

	
