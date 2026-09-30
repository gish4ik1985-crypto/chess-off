extends RefCounted
class_name MapData

# The "chess country" roster: each character sits at one stop on the map,
# tied to an AI difficulty level, with its own colour palette (for the
# region backdrop) and its own calm musical theme. Ordered by progression —
# beating one unlocks the next.

# Node kinds: regular character battle (default), "task" — a visible gate
# that opens the puzzle screen for its theme and counts as passed once
# `required` puzzles of that theme are solved, or drills/restriction battles
# (is_drill + start_fen). Ordered as one snake-shaped chain.
#
# The full map is three "acts" of 20 nodes each (60 total): act 1 is the
# hand-written roster below; acts 2 («Турнир мастеров») and 3 («Путь
# легенды») are built from it with harder AI levels, higher task quotas
# (cumulative: 5 → 15 → 30 solved) and tougher drills/restrictions.
const ACT_NAMES := {1: "Шахматная страна", 2: "Турнир мастеров", 3: "Путь легенды"}

const ACT1 := [
	{
		"id": "task_mate",
		"node": "task",
		"piece": "P",
		"name": "Задачи: мат в 1 ход",
		"region": "Пешечная деревня",
		"blurb": "Начало пути! Решите задачи на мат в один ход, чтобы открыть первый бой.",
		"ai_level": 1,
		"theme": "mate",
		"theme_label": "мат в 1 ход",
		"required": 5,
		"pos": Vector2(150, 140),
		"palette": {"bg_a": Color(0.10, 0.14, 0.08), "bg_b": Color(0.03, 0.05, 0.03), "accent": Color(0.55, 0.9, 0.35)},
		"music": {"root": 261.63, "scale": [0, 2, 4, 7, 9], "note_dur": 1.8, "tri_mix": 0.15, "drone_vol": 0.05},
	},
	{
		"id": "pawn_timofey",
		"piece": "P",
		"name": "Тимофей-пешка",
		"region": "Пешечная деревня",
		"blurb": "Только начал играть, но очень старается. Хороший первый соперник.",
		"ai_level": 1,
		"theme": "mate",
		"theme_label": "мат в 1 ход",
		"theme_required": 5,
		"assist_fen": "rnbqkbnr/ppp1pppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
		"lines": {
			"greet": "Ой, привет! Я только учусь... но сегодня точно тебя удивлю!",
			"win": "Ух ты, здорово играешь! Я запомню этот приём.",
			"lose": "Ура, получилось! Не расстраивайся — попробуй ещё разок!",
		},
		"pos": Vector2(350, 140),
		"palette": {"bg_a": Color(0.10, 0.14, 0.08), "bg_b": Color(0.03, 0.05, 0.03), "accent": Color(0.55, 0.9, 0.35)},
		"music": {"root": 261.63, "scale": [0, 2, 4, 7, 9], "note_dur": 1.8, "tri_mix": 0.15, "drone_vol": 0.05},
	},
	{
		# endgame drill node: fixed starting position, win = checkmate the AI
		"id": "drill_two_rooks",
		"piece": "R",
		"name": "Урок: мат двумя ладьями",
		"region": "Учебная поляна",
		"blurb": "У вас две ладьи против одинокого короля. Оттесняйте его «лесенкой» к краю и поставьте мат. Осторожно: не заприте короля так, чтобы получился пат!",
		"ai_level": 6,
		"theme": "",
		"theme_label": "",
		"theme_required": 0,
		"is_drill": true,
		"start_fen": "4k3/8/8/8/8/8/R7/R3K3 w - - 0 1",
		"lines": {
			"greet": "Урок первый: две ладьи работают «лесенкой». Оттесняй короля к краю!",
			"win": "Отлично! Мат двумя ладьями — теперь твой инструмент навсегда.",
			"lose": "Ничего страшного! Помни: ладьи по очереди, и следи за патом.",
		},
		"pos": Vector2(550, 140),
		"palette": {"bg_a": Color(0.12, 0.12, 0.08), "bg_b": Color(0.04, 0.04, 0.03), "accent": Color(0.85, 0.8, 0.4)},
		"music": {"root": 261.63, "scale": [0, 2, 4, 7, 9], "note_dur": 1.8, "tri_mix": 0.15, "drone_vol": 0.05},
	},
	{
		"id": "task_fork",
		"node": "task",
		"piece": "N",
		"name": "Задачи: вилка",
		"region": "Степные конюшни",
		"blurb": "Конь Ветер уважает только тех, кто владеет вилкой. Решите задачи — и он примет вызов.",
		"ai_level": 3,
		"theme": "fork",
		"theme_label": "вилка",
		"required": 5,
		"pos": Vector2(750, 140),
		"palette": {"bg_a": Color(0.16, 0.10, 0.05), "bg_b": Color(0.05, 0.03, 0.02), "accent": Color(0.95, 0.6, 0.2)},
		"music": {"root": 293.66, "scale": [0, 2, 4, 7, 9], "note_dur": 1.3, "tri_mix": 0.3, "drone_vol": 0.05},
	},
	{
		"id": "restr_no_queen",
		"piece": "Q",
		"name": "Испытание: без ферзя",
		"region": "Степные конюшни",
		"blurb": "Обычная партия, но ваш ферзь остался дома! Победите без самой сильной фигуры — научитесь ценить остальных.",
		"ai_level": 2,
		"theme": "",
		"theme_label": "",
		"theme_required": 0,
		"is_drill": true,
		"start_fen": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNB1KBNR w KQkq - 0 1",
		"lines": {
			"greet": "Правило испытания: никакого ферзя! Посмотрим, как ты без него.",
			"win": "Победа без ферзя — вот это мастерство! Испытание пройдено.",
			"lose": "Без ферзя непросто, да? Ладьи и кони ждут твоих приказов — ещё раз!",
		},
		"pos": Vector2(950, 140),
		"palette": {"bg_a": Color(0.16, 0.10, 0.05), "bg_b": Color(0.05, 0.03, 0.02), "accent": Color(0.95, 0.75, 0.4)},
		"music": {"root": 293.66, "scale": [0, 2, 4, 7, 9], "note_dur": 1.3, "tri_mix": 0.3, "drone_vol": 0.05},
	},
	{
		"id": "knight_veter",
		"piece": "N",
		"name": "Конь Ветер",
		"region": "Степные конюшни",
		"blurb": "Скачет по доске непредсказуемыми зигзагами. Любит внезапные атаки.",
		"ai_level": 3,
		"theme": "fork",
		"theme_label": "вилка",
		"theme_required": 5,
		"assist_fen": "r1bqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
		"lines": {
			"greet": "И-го-го! Держись крепче — мои прыжки не угадаешь!",
			"win": "Фух, загнал ты меня! Быстрые у тебя ходы, признаю.",
			"lose": "Оп-ля! Вилка! Говорил же — не угадаешь, куда я прыгну!",
		},
		"pos": Vector2(950, 310),
		"palette": {"bg_a": Color(0.16, 0.10, 0.05), "bg_b": Color(0.05, 0.03, 0.02), "accent": Color(0.95, 0.6, 0.2)},
		"music": {"root": 293.66, "scale": [0, 2, 4, 7, 9], "note_dur": 1.3, "tri_mix": 0.3, "drone_vol": 0.05},
	},
	{
		# co-op: a weak ally AI plays on its own; the player steps in when
		# the ally is about to blunder and must find the strong move instead
		"id": "coop_intervene",
		"piece": "B",
		"name": "Помощь другу",
		"region": "Дружеская поляна",
		"blurb": "Ваш друг играет партию сам — но иногда теряется. Следите за игрой и в трудный момент подскажите ему сильный ход!",
		"ai_level": 6,
		"theme": "",
		"theme_label": "",
		"theme_required": 0,
		"is_drill": true,
		"coop": "intervene",
		"coop_ally": 3,
		"coop_opp": 6,
		"lines": {
			"greet": "Друг волнуется перед партией. Будь рядом и помоги в трудную минуту!",
			"win": "Вы победили вместе! Настоящая дружба — вовремя подставить плечо.",
			"lose": "Не вышло... Друг верит в тебя — попробуйте ещё раз вместе!",
		},
		"pos": Vector2(750, 310),
		"palette": {"bg_a": Color(0.06, 0.12, 0.10), "bg_b": Color(0.02, 0.05, 0.04), "accent": Color(0.45, 0.9, 0.6)},
		"music": {"root": 246.94, "scale": [0, 2, 4, 7, 9], "note_dur": 1.6, "tri_mix": 0.2, "drone_vol": 0.05},
	},
	{
		# co-op: player + partner AI alternate White moves vs two Black AIs
		"id": "coop_team",
		"piece": "K",
		"name": "Папа и сын",
		"region": "Дружеская поляна",
		"blurb": "Командная партия: вы и ваш напарник ходите по очереди против команды из двух соперников. Доверяйте друг другу и стройте общий план!",
		"ai_level": 8,
		"theme": "",
		"theme_label": "",
		"theme_required": 0,
		"is_drill": true,
		"coop": "team",
		"coop_partner": 7,
		"coop_opp_a": 5,
		"coop_opp_b": 8,
		"lines": {
			"greet": "Команда на команду! Ходим по очереди — думаем как один.",
			"win": "Командная победа! Вместе вы непобедимы!",
			"lose": "Команда соперников оказалась слаженнее. Сыграемся — и реванш!",
		},
		"pos": Vector2(550, 310),
		"palette": {"bg_a": Color(0.06, 0.12, 0.10), "bg_b": Color(0.02, 0.05, 0.04), "accent": Color(0.55, 0.85, 0.95)},
		"music": {"root": 246.94, "scale": [0, 2, 4, 7, 9], "note_dur": 1.6, "tri_mix": 0.2, "drone_vol": 0.05},
	},
	{
		"id": "task_pin",
		"node": "task",
		"piece": "B",
		"name": "Задачи: связка",
		"region": "Тихая роща",
		"blurb": "В тихой роще учат связке — когда фигура не может отойти, не подставив короля.",
		"ai_level": 5,
		"theme": "pin",
		"theme_label": "связка",
		"required": 5,
		"pos": Vector2(350, 310),
		"palette": {"bg_a": Color(0.05, 0.13, 0.12), "bg_b": Color(0.02, 0.05, 0.045), "accent": Color(0.25, 0.85, 0.75)},
		"music": {"root": 220.0, "scale": [0, 3, 5, 7, 10], "note_dur": 2.2, "tri_mix": 0.1, "drone_vol": 0.06},
	},
	{
		# Pathway Этап 3 — "Микс": mate/fork/pin puzzles served at random,
		# without labelling which trick applies, once all three are learned.
		"id": "task_mix3",
		"node": "mix",
		"piece": "Q",
		"name": "Микс: три приёма",
		"region": "Тихая роща",
		"blurb": "Мат, вилка, связка — теперь вперемешку, без подсказки, какой приём сработает. Проверьте, чему вы правда научились!",
		"ai_level": 5,
		"theme": "",
		"theme_label": "",
		"required": 5,
		"pos": Vector2(150, 310),
		"palette": {"bg_a": Color(0.05, 0.13, 0.12), "bg_b": Color(0.02, 0.05, 0.045), "accent": Color(0.6, 0.9, 0.8)},
		"music": {"root": 220.0, "scale": [0, 3, 5, 7, 10], "note_dur": 2.2, "tri_mix": 0.1, "drone_vol": 0.06},
	},
	{
		"id": "drill_king_rook",
		"piece": "R",
		"name": "Урок: мат королём и ладьёй",
		"region": "Учебная поляна",
		"blurb": "Одна ладья сама мат не поставит — ей нужен ваш король. Работайте парой: король отнимает поля, ладья запирает и матует у края доски.",
		"ai_level": 7,
		"theme": "",
		"theme_label": "",
		"theme_required": 0,
		"is_drill": true,
		"start_fen": "4k3/8/8/8/8/8/8/R3K3 w - - 0 1",
		"lines": {
			"greet": "Здесь ладья одна — веди короля ей на помощь. Они сильны вместе!",
			"win": "Превосходно! Король и ладья — команда, которая не подведёт.",
			"lose": "Почти! Сначала подведи короля, потом запирай ладьёй. Ещё раз?",
		},
		"pos": Vector2(150, 480),
		"palette": {"bg_a": Color(0.12, 0.12, 0.08), "bg_b": Color(0.04, 0.04, 0.03), "accent": Color(0.85, 0.8, 0.4)},
		"music": {"root": 220.0, "scale": [0, 3, 5, 7, 10], "note_dur": 2.2, "tri_mix": 0.1, "drone_vol": 0.06},
	},
	{
		"id": "bishop_mudrost",
		"piece": "B",
		"name": "Слон Мудрость",
		"region": "Тихая роща",
		"blurb": "Действует издалека и по диагонали. Спокоен, но очень точен.",
		"ai_level": 5,
		"theme": "pin",
		"theme_label": "связка",
		"theme_required": 5,
		"assist_fen": "rn1qkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
		"lines": {
			"greet": "Тише... В роще слышно каждый ход. Подумай, прежде чем ходить.",
			"win": "Мудро сыграно. Ты видишь диагонали не хуже меня.",
			"lose": "Терпение — вот чего тебе не хватило. Возвращайся, я подожду.",
		},
		"pos": Vector2(350, 480),
		"palette": {"bg_a": Color(0.05, 0.13, 0.12), "bg_b": Color(0.02, 0.05, 0.045), "accent": Color(0.25, 0.85, 0.75)},
		"music": {"root": 220.0, "scale": [0, 3, 5, 7, 10], "note_dur": 2.2, "tri_mix": 0.1, "drone_vol": 0.06},
	},
	{
		"id": "task_backrank",
		"node": "task",
		"piece": "R",
		"name": "Задачи: мат на 1-й горизонтали",
		"region": "Каменная крепость",
		"blurb": "Крепость Грома пала бы давно, если бы не хитрость: мат по последней горизонтали. Изучите его!",
		"ai_level": 7,
		"theme": "backrank",
		"theme_label": "мат на 1-й горизонтали",
		"required": 5,
		"pos": Vector2(550, 480),
		"palette": {"bg_a": Color(0.10, 0.11, 0.14), "bg_b": Color(0.04, 0.04, 0.06), "accent": Color(0.6, 0.7, 0.95)},
		"music": {"root": 164.81, "scale": [0, 2, 3, 5, 7, 9, 10], "note_dur": 1.6, "tri_mix": 0.5, "drone_vol": 0.07},
	},
	{
		"id": "restr_no_rooks",
		"piece": "R",
		"name": "Испытание: без ладей",
		"region": "Каменная крепость",
		"blurb": "Стража забрала обе ваши ладьи на ремонт стен. Выиграйте партию лёгкими фигурами и ферзём!",
		"ai_level": 4,
		"theme": "",
		"theme_label": "",
		"theme_required": 0,
		"is_drill": true,
		"start_fen": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/1NBQKBN1 w kq - 0 1",
		"lines": {
			"greet": "В крепости уважают тех, кто умеет обходиться без ладей. Докажи!",
			"win": "Без ладей — и такая победа! Стража крепости салютует тебе.",
			"lose": "Без ладей сложнее держать линии, верно? Попробуй ещё раз!",
		},
		"pos": Vector2(750, 480),
		"palette": {"bg_a": Color(0.10, 0.11, 0.14), "bg_b": Color(0.04, 0.04, 0.06), "accent": Color(0.75, 0.8, 0.95)},
		"music": {"root": 164.81, "scale": [0, 2, 3, 5, 7, 9, 10], "note_dur": 1.6, "tri_mix": 0.5, "drone_vol": 0.07},
	},
	{
		"id": "rook_grom",
		"piece": "R",
		"name": "Ладья Гром",
		"region": "Каменная крепость",
		"blurb": "Прямая сила по линиям и вертикалям. Держит оборону крепко.",
		"ai_level": 7,
		"theme": "backrank",
		"theme_label": "мат на 1-й горизонтали",
		"theme_required": 5,
		"assist_fen": "1nbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQk - 0 1",
		"lines": {
			"greet": "Стой! Кто идёт?! Моя крепость не сдаётся без боя!",
			"win": "ГРОМ И МОЛНИЯ! Стены пали... Ты достоин идти дальше.",
			"lose": "Ха-ха! Моя оборона крепка! Потренируйся и приходи снова!",
		},
		"pos": Vector2(950, 480),
		"palette": {"bg_a": Color(0.10, 0.11, 0.14), "bg_b": Color(0.04, 0.04, 0.06), "accent": Color(0.6, 0.7, 0.95)},
		"music": {"root": 164.81, "scale": [0, 2, 3, 5, 7, 9, 10], "note_dur": 1.6, "tri_mix": 0.5, "drone_vol": 0.07},
	},
	{
		"id": "task_defense",
		"node": "task",
		"piece": "Q",
		"name": "Задачи: уничтожение защиты",
		"region": "Хрустальный дворец",
		"blurb": "Виктория элегантно убирает защитников с дороги. Освойте этот приём, чтобы войти во дворец.",
		"ai_level": 9,
		"theme": "defense",
		"theme_label": "уничтожение защиты",
		"required": 5,
		"pos": Vector2(950, 650),
		"palette": {"bg_a": Color(0.16, 0.07, 0.15), "bg_b": Color(0.06, 0.02, 0.06), "accent": Color(0.95, 0.55, 0.9)},
		"music": {"root": 349.23, "scale": [0, 2, 4, 7, 9], "note_dur": 1.1, "tri_mix": 0.4, "drone_vol": 0.05},
	},
	{
		"id": "drill_pawn_promote",
		"piece": "P",
		"name": "Урок: проведи пешку в ферзи",
		"region": "Учебная поляна",
		"blurb": "Всего одна пешка — но если довести её до последней горизонтали, она станет ферзём! Ведите её вперёд под охраной короля, а потом поставьте мат.",
		"ai_level": 7,
		"theme": "",
		"theme_label": "",
		"theme_required": 0,
		"is_drill": true,
		"start_fen": "8/8/4K3/8/4P3/8/8/4k3 w - - 0 1",
		"lines": {
			"greet": "Одна пешка — но какая! Король впереди, пешка следом. Вперёд!",
			"win": "Ферзь! А дальше ты знаешь, что делать. Урок усвоен!",
			"lose": "Пешку нужно охранять королём — без него она не пройдёт. Попробуй снова!",
		},
		"pos": Vector2(750, 650),
		"palette": {"bg_a": Color(0.12, 0.12, 0.08), "bg_b": Color(0.04, 0.04, 0.03), "accent": Color(0.85, 0.8, 0.4)},
		"music": {"root": 293.66, "scale": [0, 2, 4, 7, 9], "note_dur": 1.3, "tri_mix": 0.3, "drone_vol": 0.05},
	},
	{
		"id": "queen_viktoria",
		"piece": "Q",
		"name": "Ферзь Виктория",
		"region": "Хрустальный дворец",
		"blurb": "Играет элегантно и очень сильно во всех направлениях сразу.",
		"ai_level": 9,
		"theme": "defense",
		"theme_label": "уничтожение защиты",
		"theme_required": 5,
		"assist_fen": "rnbqkb1r/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
		"lines": {
			"greet": "Добро пожаловать во дворец. Играем красиво — или не играем вовсе.",
			"win": "Блестяще! Такую партию не стыдно повесить в хрустальной галерее.",
			"lose": "Элегантно, не правда ли? Отточи свою игру — и возвращайся.",
		},
		"pos": Vector2(550, 650),
		"palette": {"bg_a": Color(0.16, 0.07, 0.15), "bg_b": Color(0.06, 0.02, 0.06), "accent": Color(0.95, 0.55, 0.9)},
		"music": {"root": 349.23, "scale": [0, 2, 4, 7, 9], "note_dur": 1.1, "tri_mix": 0.4, "drone_vol": 0.05},
	},
	{
		"id": "task_deflection",
		"node": "task",
		"piece": "K",
		"name": "Задачи: отвлечение",
		"region": "Вершина Короны",
		"blurb": "Последний приём перед вершиной: отвлеките защитника — и путь к победе открыт.",
		"ai_level": 10,
		"theme": "deflection",
		"theme_label": "отвлечение",
		"required": 5,
		"pos": Vector2(350, 650),
		"palette": {"bg_a": Color(0.09, 0.11, 0.17), "bg_b": Color(0.03, 0.04, 0.07), "accent": Color(0.85, 0.75, 0.35)},
		"music": {"root": 130.81, "scale": [0, 3, 5, 7, 10], "note_dur": 2.0, "tri_mix": 0.5, "drone_vol": 0.08},
	},
	{
		"id": "king_magnus",
		"piece": "K",
		"name": "Король Магнус",
		"region": "Вершина Короны",
		"blurb": "Финальный соперник. Спокойный, невозмутимый и почти не ошибается.",
		"ai_level": 10,
		"theme": "deflection",
		"theme_label": "отвлечение",
		"theme_required": 5,
		"assist_fen": "r1bqkb1r/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
		"lines": {
			"greet": "Ты дошёл до вершины. Покажи мне всё, чему научился.",
			"win": "...Мат. Мне. Невероятно. Корона твоя — ты настоящий чемпион!",
			"lose": "Хорошая партия. Но вершина покоряется лишь упорным. Ещё раз?",
		},
		"pos": Vector2(150, 650),
		"palette": {"bg_a": Color(0.09, 0.11, 0.17), "bg_b": Color(0.03, 0.04, 0.07), "accent": Color(0.85, 0.75, 0.35)},
		"music": {"root": 130.81, "scale": [0, 3, 5, 7, 10], "note_dur": 2.0, "tri_mix": 0.5, "drone_vol": 0.08},
		"is_boss": true,
	},
]

static var CHARACTERS: Array = _build_all()

static func _build_all() -> Array:
	var all := []
	for c in ACT1:
		var d = c.duplicate(true)
		d["act"] = 1
		all.append(d)
	all.append_array(_patched_act(2, _act2_overrides()))
	all.append_array(_patched_act(3, _act3_overrides()))
	return all

# Clones every act-1 node with a per-act id suffix and applies overrides.
static func _patched_act(act: int, over: Dictionary) -> Array:
	var out := []
	for c in ACT1:
		var d = c.duplicate(true)
		d["act"] = act
		d["id"] = "%s_%d" % [c.id, act]
		if over.has(c.id):
			for k in over[c.id]:
				d[k] = over[c.id][k]
		out.append(d)
	return out

static func _act2_overrides() -> Dictionary:
	return {
		"task_mate": {"name": "Задачи: мат — серия II", "required": 15,
			"blurb": "Турнир мастеров открыт! Доведите счёт решённых задач на мат до 15."},
		"pawn_timofey": {"name": "Тимофей-пешка — реванш", "ai_level": 4, "theme_required": 15,
			"blurb": "Тимофей тренировался день и ночь и требует реванша!",
			"lines": {
				"greet": "Я тренировался всё лето! Теперь держись по-настоящему!",
				"win": "Опять ты сильнее... Но в третьем акте я стану легендой!",
				"lose": "Видал?! Тренировки работают! Догоняй!",
			}},
		"drill_two_rooks": {"name": "Урок: мат ферзём", "ai_level": 9,
			"start_fen": "4k3/8/8/8/8/8/3Q4/4K3 w - - 0 1",
			"blurb": "Ферзь — сильнейшая фигура, но именно с ним чаще всего случается пат! Подведите короля и поставьте мат аккуратно.",
			"lines": {
				"greet": "Урок мастеров: мат ферзём. Главный враг здесь — пат, будь начеку!",
				"win": "Чисто сработано! Ферзь и король — грозная пара.",
				"lose": "Пат или потеря времени? Ферзь ставит мат только вместе с королём!",
			}},
		"task_fork": {"name": "Задачи: вилка — серия II", "required": 15,
			"blurb": "Мастера видят вилку мгновенно. Доведите счёт до 15 решённых."},
		"restr_no_queen": {"name": "Испытание: без ферзя II", "ai_level": 5,
			"blurb": "Снова без ферзя — но соперник теперь куда сильнее!"},
		"knight_veter": {"name": "Конь Ветер — реванш", "ai_level": 6, "theme_required": 15,
			"lines": {
				"greet": "И-го-го! На турнире мастеров мои зигзаги ещё коварнее!",
				"win": "Уф-ф... Ты обуздал ветер. До встречи в финальном акте!",
				"lose": "Штормовой ветер не остановить! Тренируйся и возвращайся!",
			}},
		"coop_intervene": {"name": "Помощь другу II", "ai_level": 9, "coop_ally": 5, "coop_opp": 9,
			"blurb": "Друг подрос и играет сильнее — но и соперник серьёзнее. Не пропустите момент, когда нужна ваша помощь!"},
		"coop_team": {"name": "Папа и сын — турнир", "ai_level": 11, "coop_partner": 9, "coop_opp_a": 8, "coop_opp_b": 11},
		"task_pin": {"name": "Задачи: связка — серия II", "required": 15},
		"task_mix3": {"name": "Микс мастеров: три приёма", "required": 15,
			"blurb": "Мат, вилка, связка вперемешку — мастер обязан узнавать приём с одного взгляда. До 15 решённых!"},
		"drill_king_rook": {"name": "Урок: ладья против упрямца", "ai_level": 10,
			"blurb": "Тот же мат королём и ладьёй — но теперь король соперника защищается идеально. Ни одного лишнего хода!",
			"lines": {
				"greet": "Теперь я защищаюсь всерьёз. Каждый твой ход должен быть точным!",
				"win": "Безупречная техника! Мастер эндшпиля.",
				"lose": "Видишь? Против точной защиты нужна точная атака. Ещё раз!",
			}},
		"bishop_mudrost": {"name": "Слон Мудрость — реванш", "ai_level": 7, "theme_required": 15},
		"task_backrank": {"name": "Задачи: 1-я горизонталь — серия II", "required": 15},
		"restr_no_rooks": {"name": "Испытание: без ладей II", "ai_level": 7},
		"rook_grom": {"name": "Ладья Гром — реванш", "ai_level": 8, "theme_required": 15},
		"task_defense": {"name": "Задачи: уничтожение защиты — серия II", "required": 15},
		"drill_pawn_promote": {"name": "Урок: две пешки в бой", "ai_level": 9,
			"start_fen": "8/8/3k4/8/2PP4/8/3K4/8 w - - 0 1",
			"blurb": "Две пешки поддерживают друг друга. Проведите хотя бы одну в ферзи — король соперника не сможет остановить обеих!",
			"lines": {
				"greet": "Две пешки — как два брата: одну держат, вторая проходит!",
				"win": "Прорыв удался! Пешечная пара — страшная сила.",
				"lose": "Пешки должны идти вместе, под защитой короля. Попробуй ещё!",
			}},
		"queen_viktoria": {"name": "Ферзь Виктория — реванш", "ai_level": 11, "theme_required": 15},
		"task_deflection": {"name": "Задачи: отвлечение — серия II", "required": 15},
		"king_magnus": {"name": "Король Магнус — корона на кону", "ai_level": 12, "theme_required": 15,
			"lines": {
				"greet": "Ты вернулся. На этот раз я не буду сдерживаться.",
				"win": "Дважды... Ты победил меня дважды. Турнир мастеров твой!",
				"lose": "Корона остаётся у меня. Закали характер — и приходи.",
			}},
	}

static func _act3_overrides() -> Dictionary:
	return {
		"task_mate": {"name": "Задачи: мат — путь легенды", "required": 30,
			"blurb": "Финальный акт. Легенды решают задачи на мат с закрытыми глазами — доведите счёт до 30."},
		"pawn_timofey": {"name": "Тимофей-пешка — легенда", "ai_level": 10, "theme_required": 30,
			"blurb": "Тимофей прошёл весь путь вместе с вами — и стал по-настоящему сильным.",
			"lines": {
				"greet": "Помнишь меня новичком? Теперь я играю как мастер!",
				"win": "Ты... ты всё ещё сильнее. Ты настоящая легенда!",
				"lose": "Пешка, дошедшая до конца, становится ферзём! Это про меня!",
			}},
		"drill_two_rooks": {"name": "Легенда: мат двумя слонами", "ai_level": 12,
			"start_fen": "4k3/8/8/8/8/8/8/2B1KB2 w - - 0 1",
			"blurb": "Два слона плетут сеть по диагоналям, а король загоняет соперника в угол. Один из самых красивых матов в шахматах!",
			"lines": {
				"greet": "Диагональная сеть — искусство. Покажи, что ты художник!",
				"win": "Великолепно! Мат двумя слонами — украшение любой коллекции.",
				"lose": "Слоны работают только парой, а король — их дирижёр. Ещё раз!",
			}},
		"task_fork": {"name": "Задачи: вилка — путь легенды", "required": 30},
		"restr_no_queen": {"name": "Испытание: без ферзя и ладей", "ai_level": 8,
			"start_fen": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/1NB1KBN1 w kq - 0 1",
			"blurb": "Ни ферзя, ни ладей — только лёгкие фигуры, пешки и голова на плечах!",
			"lines": {
				"greet": "Ферзь и ладьи отдыхают. Победи умом, а не силой!",
				"win": "Победа лёгкими фигурами — тяжёлый вес мастерства!",
				"lose": "Кони и слоны сильны в руках терпеливого. Ещё попытка!",
			}},
		"knight_veter": {"name": "Конь Ветер — легенда", "ai_level": 12, "theme_required": 30,
			"lines": {
				"greet": "Финальная скачка! Ветер стал ураганом!",
				"win": "Ураган стих... перед бурей по имени ты. Скачи к вершине!",
				"lose": "Ур-р-раган! Никто не обгонит Ветра в его лучшей форме!",
			}},
		"coop_intervene": {"name": "Помощь другу — легенда", "ai_level": 13, "coop_ally": 8, "coop_opp": 13,
			"blurb": "Финальный экзамен наставника: друг играет против настоящего мастера. Каждое ваше вмешательство должно быть безупречным!"},
		"coop_team": {"name": "Папа и сын — легенда", "ai_level": 15, "coop_partner": 12, "coop_opp_a": 12, "coop_opp_b": 15},
		"task_pin": {"name": "Задачи: связка — путь легенды", "required": 30},
		"task_mix3": {"name": "Микс легенд: три приёма", "required": 30},
		"drill_king_rook": {"name": "Легенда: мат конём и слоном", "ai_level": 12,
			"start_fen": "4k3/8/8/8/8/8/8/2B1KN2 w - - 0 1",
			"blurb": "Самый трудный мат в шахматах: конь, слон и король должны работать как единый механизм, загоняя соперника в «правильный» угол.",
			"lines": {
				"greet": "Мат конём и слоном ставят единицы. Войди в их число!",
				"win": "Невероятно! Этот мат — вершина техники. Ты легенда эндшпиля!",
				"lose": "Не расстраивайся — этот мат сложен даже для гроссмейстеров. Ещё раз?",
			}},
		"bishop_mudrost": {"name": "Слон Мудрость — легенда", "ai_level": 13, "theme_required": 30},
		"task_backrank": {"name": "Задачи: 1-я горизонталь — путь легенды", "required": 30},
		"restr_no_rooks": {"name": "Испытание: без лёгких фигур", "ai_level": 10,
			"start_fen": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/R2QK2R w KQkq - 0 1",
			"blurb": "Ни коней, ни слонов — только тяжёлые фигуры. Прямолинейно? Зато соперник очень силён!",
			"lines": {
				"greet": "Только ферзь и ладьи. Грубая сила требует тонкого расчёта!",
				"win": "Тяжёлая артиллерия в умелых руках! Испытание пройдено.",
				"lose": "Без лёгких фигур каждая ошибка тяжелее вдвойне. Ещё раз!",
			}},
		"rook_grom": {"name": "Ладья Гром — легенда", "ai_level": 15, "theme_required": 30},
		"task_defense": {"name": "Задачи: уничтожение защиты — путь легенды", "required": 30},
		"drill_pawn_promote": {"name": "Легенда: ферзь против ладьи", "ai_level": 12,
			"start_fen": "3rk3/8/8/8/8/8/3Q4/3K4 w - - 0 1",
			"blurb": "Ферзь сильнее ладьи — но доказать это против упорной защиты неимоверно трудно. Выиграйте ладью или поставьте мат!",
			"lines": {
				"greet": "Ферзь против ладьи — дуэль чемпионов. Докажи превосходство!",
				"win": "Дуэль выиграна! Такой технике позавидуют чемпионы мира.",
				"lose": "Ладья вертится как юла, да? Терпение, зигзаги ферзём — и она попадётся!",
			}},
		"queen_viktoria": {"name": "Ферзь Виктория — легенда", "ai_level": 16, "theme_required": 30},
		"task_deflection": {"name": "Задачи: отвлечение — путь легенды", "required": 30},
		"king_magnus": {"name": "Король Магнус — последняя партия", "ai_level": 18, "theme_required": 30,
			"blurb": "Финал финалов. Магнус в абсолютной форме. Победитель становится легендой шахматной страны.",
			"lines": {
				"greet": "Третья встреча — последняя. Сыграем партию, достойную легенд.",
				"win": "...Идеально. Шахматная страна склоняется перед новой легендой. Корона твоя навсегда.",
				"lose": "Легендами не рождаются — ими становятся через поражения. Возвращайся.",
			}},
	}

static func by_id(id: String) -> Dictionary:
	for c in CHARACTERS:
		if c.id == id:
			return c
	return {}

static func index_of(id: String) -> int:
	for i in range(CHARACTERS.size()):
		if CHARACTERS[i].id == id:
			return i
	return -1

static func first_id() -> String:
	return CHARACTERS[0].id
