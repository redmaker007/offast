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
##
## exclude 里的名字不会被抽中——剧情角色已经自己占了名额，
## 再被随机抽一次就成了重复行。
## 名字池优先用内容文件里那份（world.story 的 [names]）——中文局要的是
## 另一套名字，不是把 Jack 翻译成杰克。内容里没写才退回下面这份内置英文名单。
func name_pool() -> Array:
	var world = %story_book.world if has_node("%story_book") else null
	if world != null and not world.random_names.is_empty():
		var out: Array = []
		for n in world.random_names:
			out.append(String(n))
		return out
	return employee_list.duplicate()


func get_random_employee_name(num:int, exclude:Array = []):
	var pool = name_pool()
	for name in exclude:
		pool.erase(String(name))
	pool.shuffle()
	return pool.slice(0, mini(num, pool.size()))


## exclude 里的动作不会被随机到——比如第三天要求「随机信不出 promotion」，
## 因为那天的 promotion 名额留给剧情角色。
func generate_email(_employee_list, exclude: Array = []):

	var pool = instruction_list.duplicate()
	for action in exclude:
		pool.erase(String(action))
	if pool.is_empty():
		pool = instruction_list.duplicate()

	var picked_instruction = pool[randi() % pool.size()]
	var picked_employee = _employee_list[randi() % _employee_list.size()]
	var picked_sender_class = randi() % 5
	
	var e = email.new()
	e.init_email("someone",picked_instruction,picked_employee,picked_sender_class)
	
	SignalBus.send_email.emit(e)

	
