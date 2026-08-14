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

func get_random_employee_name(num:int):

	var random_employee_name_list = []
	for i in range(num):
		var picked_employee = employee_list[randi() % employee_list.size()]
		random_employee_name_list.append(picked_employee)
	return random_employee_name_list


func generate_email(_employee_list):

	var picked_instruction = instruction_list[randi() % instruction_list.size()]
	var picked_employee = _employee_list[randi() % _employee_list.size()]
	var picked_sender_class = randi() % 5
	
	var e = email.new()
	e.init_email("someone",picked_instruction,picked_employee,picked_sender_class)
	
	SignalBus.send_email.emit(e)

	
