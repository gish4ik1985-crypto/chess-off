class_name Roles
extends RefCounted

# Роли пользователей и их права. Роль выдаётся в облаке (документ roles/{uid}); здесь — только названия
# и «что можно». Права проверяются и в игре (что показывать), и в правилах базы (что разрешено записать).
#
#   player    — ученик: играет и учится, правит только свою анкету
#   coach     — тренер: видит всех игроков, присваивает им именные титулы
#   moderator — помощник: как тренер (резерв на будущее — турниры, жалобы)
#   admin     — администратор: всё, включая выдачу ролей и настройки игры

const ORDER := ["player", "coach", "moderator", "admin"]

const INFO := {
	"player": {"name": "Ученик", "icon": "🎓", "about": "Играет, учится, ведёт свою анкету."},
	"coach": {"name": "Тренер", "icon": "🧑‍🏫", "about": "Видит всех игроков школы и присваивает им именные титулы."},
	"moderator": {"name": "Модератор", "icon": "🛡", "about": "Помощник тренера: видит игроков и присваивает титулы (права будут расширяться)."},
	"admin": {"name": "Администратор", "icon": "👑", "about": "Полный доступ: роли пользователей, настройки игры, титулы."},
}

# Что кому можно.
const PERMS := {
	"open_admin": ["coach", "moderator", "admin"], # заходить в панель управления
	"award_titles": ["coach", "moderator", "admin"], # присваивать именные титулы
	"manage_roles": ["admin"], # назначать роли
	"game_settings": ["admin"], # игра с форой, живая сложность, правило 50 ходов, настоящий рейтинг
}

# Кто становится администратором сразу (до выдачи ролей в базе). Тот же список — в firebase/firestore.rules.
const BOOTSTRAP_ADMINS := ["gish4ik1985@gmail.com"]

static func valid(role: String) -> bool:
	return INFO.has(role)

static func can(role: String, perm: String) -> bool:
	return role in PERMS.get(perm, [])

static func role_name(role: String) -> String:
	return String(INFO.get(role, INFO.player).name)

static func badge(role: String) -> String:
	var i: Dictionary = INFO.get(role, INFO.player)
	return "%s %s" % [i.icon, i.name]

# Короткий значок для строк и подписей: у ученика его нет, чтобы не шуметь.
static func icon_for(role: String) -> String:
	return "" if role == "player" or not INFO.has(role) else String(INFO[role].icon)

# Автоматическая «характеристика игрока» по турнирному рейтингу: титул и примерный разряд.
# Разряд — ориентир для школы, не официальное звание.
static func class_text(rating: float, title: String) -> String:
	return "%s · %s" % [title, approx_rank(rating)]

static func approx_rank(rating: float) -> String:
	if rating < 900: return "без разряда"
	if rating < 1100: return "≈ 3 разряд"
	if rating < 1300: return "≈ 2 разряд"
	if rating < 1500: return "≈ 1 разряд"
	if rating < 1800: return "≈ КМС"
	return "≈ мастер"
