## word_set_loader.gd
## Manages word sets for different languages, organized by word length
## Autoload singleton: WordSetLoader
extends Node

enum Language { EN, DE }

var current_language: Language = Language.EN
var used_words: Dictionary = {}  # Track used words per length group

# Words organized by length groups per language
# Group 1: 2-3 letters (Waves 1-2)
# Group 2: 4-5 letters (Waves 3-5)
# Group 3: 6-7 letters (Waves 6-8)
# Group 4: 8-9 letters (Waves 9-12)
# Group 5: 10+ letters (Waves 13+)

const WORDS_BY_LENGTH := {
	Language.EN: {
		# 2-3 letter words (60 words)
		2: [
			"GO", "UP", "IT", "ON", "IN", "TO", "DO", "BE", "WE", "ME",
			"NO", "SO", "OR", "IF", "AT", "BY", "AN", "AS", "IS", "HE"
		],
		3: [
			"RUN", "CAT", "DOG", "RED", "BIG", "SUN", "SKY", "BOX", "FOX", "HOT",
			"CUT", "HIT", "WIN", "FLY", "TRY", "CRY", "DRY", "WHY", "OLD", "NEW",
			"TOP", "MAP", "BAT", "RAT", "HAT", "JAR", "WAR", "CAR", "BAR", "FAR",
			"GUN", "FUN", "BUS", "CUP", "MUD", "BUD", "RUG", "BUG", "HUG", "JUG"
		],
		# 4-5 letter words (100 words)
		4: [
			"FIRE", "JUMP", "FAST", "SLOW", "HARD", "EASY", "DARK", "GOLD", "IRON", "WOOD",
			"STAR", "MOON", "WIND", "RAIN", "SNOW", "ROCK", "TREE", "BIRD", "FISH", "WOLF",
			"BLUE", "COLD", "WARM", "GOOD", "EVIL", "KING", "HERO", "MAGE", "TANK", "SHIP",
			"BOLT", "HEAL", "MANA", "AURA", "GLOW", "BYTE", "CODE", "DATA", "HACK", "SYNC",
			"CHIP", "CORE", "NODE", "WAVE", "BEAM", "DISK", "GRID", "LINK", "LOOP", "MESH"
		],
		5: [
			"BLADE", "ARROW", "SPEAR", "LANCE", "SWORD", "SHIELD", "ARMOR", "STORM", "FLAME",
			"FROST", "SPARK", "LIGHT", "MAGIC", "SPELL", "CURSE", "BLESS", "POWER", "FORCE",
			"SPEED", "SKILL", "LEVEL", "QUEST", "WORLD", "REALM", "TOWER", "CROWN", "GLORY",
			"HONOR", "VALOR", "BRAVE", "SWIFT", "QUICK", "SHARP", "TOUGH", "SOLID", "STEEL",
			"STONE", "EARTH", "WATER", "GHOST", "DEMON", "ANGEL", "BEAST", "GIANT", "DWARF",
			"CHAOS", "ORDER", "PEACE", "WRATH", "GRACE"
		],
		# 6-7 letter words (100 words)
		6: [
			"STRIKE", "ATTACK", "DEFEND", "BATTLE", "COMBAT", "WEAPON", "HUNTER", "KILLER",
			"SLAYER", "WIZARD", "ARCHER", "KNIGHT", "DRAGON", "UNDEAD", "ZOMBIE", "SPIRIT",
			"SHADOW", "MYSTIC", "ARCANE", "COSMIC", "DIVINE", "SACRED", "FALLEN", "CURSED",
			"FROZEN", "BLAZING", "THUNDER", "ENERGY", "PLASMA", "PHOTON", "SYSTEM", "MATRIX",
			"CIPHER", "VECTOR", "BINARY", "UPLOAD", "DECODE", "REBOOT", "SIGNAL", "SWITCH",
			"PORTAL", "VORTEX", "BREACH", "RIFT", "SECTOR", "COLONY", "EMPIRE", "LEGION", "HORDE"
		],
		7: [
			"WARRIOR", "FIGHTER", "SOLDIER", "CAPTAIN", "GENERAL", "MARSHAL", "WARLORD",
			"EMPEROR", "PHOENIX", "CHIMERA", "GRIFFIN", "SERPENT", "VAMPIRE", "WARLOCK",
			"SORCERY", "ALCHEMY", "ENCHANT", "CONJURE", "SUMMONS", "BANISH", "DESTROY",
			"SHATTER", "DEMOLISH", "UNLEASH", "EXECUTE", "QUANTUM", "NETWORK", "DIGITAL",
			"VIRTUAL", "COMPLEX", "PROGRAM", "CLUSTER", "REACTOR", "TURBINE", "CRYSTAL",
			"ANCIENT", "ETERNAL", "SUPREME", "ULTIMATE", "PRIMAL", "MYTHIC", "HEROIC",
			"PHANTOM", "SPECTER", "WRAITH", "CYCLONE", "TEMPEST", "INFERNO", "GLACIER"
		],
		# 8-9 letter words (80 words)
		8: [
			"FIREBALL", "ICESTORM", "THUNDERBOLT", "FIRESTORM", "BLIZZARD", "EARTHQUAKE",
			"ASSASSIN", "GUARDIAN", "DEFENDER", "CHAMPION", "CONQUEROR", "PREDATOR",
			"OVERLORD", "DREADLORD", "NIGHTMARE", "DARKNESS", "OBLIVION", "INFINITY",
			"PROTOCOL", "OVERRIDE", "FIREWALL", "MAINFRAME", "SOFTWARE", "HARDWARE",
			"DATABASE", "SECURITY", "TERMINAL", "DOWNLOAD", "SEQUENCE", "ALGORITHM",
			"BERSERKER", "PALADIN", "SENTINEL", "COLOSSUS", "BEHEMOTH", "LEVIATHAN",
			"MASSACRE", "CARNAGE", "RAMPAGE", "ONSLAUGHT"
		],
		9: [
			"LEGENDARY", "DANGEROUS", "NIGHTMARE", "LIGHTNING", "EXPLOSIVE", "ANNIHILATE",
			"DEVASTATE", "ERADICATE", "ELIMINATE", "TERMINATE", "OBLITERATE", "DECIMATE",
			"FIREPOWER", "CYBERNETIC", "AUTOMATIC", "SYNTHETIC", "ENERGETIC", "CHROMATIC",
			"DESTROYER", "COMMANDER", "GLADIATOR", "IMMORTALS", "VENGEANCE", "RECKONING",
			"ARCHANGEL", "ARCHDEVIL", "DOOMSAYER", "HARBINGER", "EXECUTIONER", "CONQUEROR",
			"REBELLION", "EVOLUTION", "EXPLOSION", "IMPLOSION", "COLLISION", "DIMENSION"
		],
		# 10+ letter words (60 words)
		10: [
			"APOCALYPSE", "ARMAGEDDON", "CATACLYSM", "ANNIHILATOR", "TERMINATOR", "DECIMATOR",
			"OBLITERATOR", "ELIMINATOR", "DOMINATOR", "DEVASTATOR", "EXTERMINATOR", "INQUISITOR",
			"JUGGERNAUT", "BEHEMOTH", "COLOSSUS", "MONSTROSITY", "ABOMINATION", "CATASTROPHE",
			"DESTRUCTION", "REVOLUTION", "EVOLUTION", "CORRUPTION", "DOMINATION", "ELIMINATION",
			"DEVASTATION", "ANNIHILATION", "OBLITERATION", "EXTERMINATION", "ACCELERATION",
			"DECELERATION"
		],
		11: [
			"UNSTOPPABLE", "UNBREAKABLE", "INVINCIBLE", "INDESTRUCTIBLE", "OVERWHELMING",
			"THUNDERSTORM", "OBLITERATION", "ANNIHILATION", "EXTERMINATION", "DISINTEGRATE",
			"ANNIHILATOR", "BATTLECRUISER", "DREADNOUGHT", "INTERCEPTOR", "MOTHERSHIP"
		],
		12: [
			"EXTERMINATOR", "ANNIHILATING", "OBLITERATING", "OVERWHELMING", "DISINTEGRATION",
			"TRANSCENDENCE", "METAMORPHOSIS", "MAGNIFICENCE", "EXTRAORDINARY", "CATASTROPHIC"
		]
	},
	Language.DE: {
		# 2-3 letter words (60 words)
		2: [
			"AB", "AN", "DA", "ES", "IM", "JA", "SO", "UM", "WO", "ZU",
			"AM", "BEI", "EIN", "ICH", "IST", "MAN", "NUR", "SIE", "UND", "VOR"
		],
		3: [
			"LOS", "AUF", "ROT", "TAG", "WEG", "GUT", "NEU", "ALT", "ORT", "RAD",
			"ARM", "BAU", "EIS", "FEE", "GAS", "HUT", "KUH", "LAB", "MAL", "NAH",
			"OHR", "RAT", "SEE", "TAL", "UHR", "VIA", "WUT", "ZUG", "BOT", "DUO",
			"ERZ", "FON", "GAB", "HOF", "JOB", "KIT", "LOS", "MUT", "NUN", "OPA"
		],
		# 4-5 letter words (100 words)
		4: [
			"HAUS", "BAUM", "BERG", "MOND", "TIER", "BROT", "LAUF", "HALT", "RUND", "FEST",
			"GOLD", "WALD", "HELD", "KERN", "LOCH", "MEER", "NETZ", "POST", "QUAL", "REIS",
			"SAFT", "TURM", "UFER", "VOLK", "WAHL", "XRAY", "YOGA", "ZAHL", "BLUT", "DORF",
			"ERBE", "FILM", "GRAS", "HERR", "IDEE", "JAGD", "KALT", "LAND", "MAUL", "NORM"
		],
		5: [
			"FEUER", "WASSER", "STEIN", "WOLKE", "BLUME", "VOGEL", "FISCH", "PFERD", "KATZE",
			"HUNDE", "BLITZ", "STURM", "KRAFT", "MACHT", "KRIEG", "KAMPF", "SIEG", "EHRE",
			"RUHM", "GLORY", "MAGIE", "ZAUBER", "FLUCH", "SEGEN", "GEIST", "SEELE", "TRAUM",
			"ANGST", "FREUDE", "LIEBE", "HASS", "STOLZ", "TREUE", "GLAUBE", "TAPFER", "STARK",
			"MUTIG", "WEISE", "KLUG", "SCHLAU", "GROSS", "KLEIN", "DUNKEL", "LICHT", "WELLE",
			"PHASE", "IMPULS", "STROM", "LASER", "CYBER"
		],
		# 6-7 letter words (100 words)
		6: [
			"ANGRIFF", "ABWEHR", "PARADE", "AUSFALL", "ATTACKE", "WAFFEN", "KRIEGER",
			"SOLDAT", "RITTER", "DRACHE", "DAEMON", "ZOMBIE", "VAMPIR", "HEXER", "MAGIER",
			"SCHATTEN", "MYSTIK", "ARKAN", "KOSMISCH", "HEILIG", "VERFLUCHT", "GEFROREN",
			"DONNER", "ENERGIE", "PLASMA", "SYSTEM", "MATRIX", "VEKTOR", "SIGNAL", "PORTAL",
			"VORTEX", "SEKTOR", "KOLONIE", "LEGION", "HORDE", "ARMEE", "TRUPPEN", "FLOTTE",
			"MARINE", "PANZER", "RAKETE", "BOMBE", "GEWEHR", "KANONE", "SCHILD", "SCHWERT",
			"KLINGE", "AMULETT"
		],
		7: [
			"KRIEGER", "KAEMPFER", "SOLDAT", "KAPITAEN", "GENERAL", "ADMIRAL", "IMPERATOR",
			"PHOENIX", "CHIMERA", "GREIF", "SCHLANGE", "VAMPIR", "DAEMONEN", "ZAUBEREI",
			"ALCHEMIE", "VERZAUBER", "BESCHWOER", "ZERSTOER", "ZERBRECH", "ENTFESSELN",
			"VERNICHT", "QUANTUM", "NETZWERK", "DIGITAL", "VIRTUELL", "KOMPLEX", "PROGRAMM",
			"REAKTOR", "TURBINE", "KRISTALL", "ANTIKER", "EWIGER", "OBERSTER", "MYTHISCH",
			"PHANTOM", "GESPENST", "ZYKLON", "ORKAN", "INFERNO", "GLETSCHER", "TSUNAMI",
			"ERDBEBEN", "VULKAN", "LAWINE", "TORNADO", "HURRIKAN"
		],
		# 8-9 letter words (80 words)
		8: [
			"FEUERBALL", "EISSTURM", "BLITZSCHLAG", "FEUERSTURM", "SCHNEESTURM", "ERDBEBEN",
			"ASSASSINE", "WAECHTER", "VERTEIDIGER", "CHAMPION", "EROBERER", "RAEUBER",
			"OVERLORD", "ALPTRAUM", "FINSTERNIS", "VERGESSEN", "UNENDLICH", "PROTOKOLL",
			"FIREWALL", "RECHNER", "SOFTWARE", "HARDWARE", "DATENBANK", "SICHERHEIT",
			"TERMINAL", "DOWNLOAD", "SEQUENZ", "BERSERKER", "PALADIN", "WAECHTER",
			"KOLOSS", "BEHEMOTH", "LEVIATHAN", "MASSAKER", "BLUTBAD", "RASEREI", "ANSTURM"
		],
		9: [
			"LEGENDAER", "GEFAEHRLICH", "ALPTRAUM", "BLITZSCHLAG", "EXPLOSIV", "VERNICHTEN",
			"VERHEEREN", "AUSROTTEN", "ELIMINIER", "BEENDEN", "AUSLOESCHEN", "DEZIMIEREN",
			"FEUERKRAFT", "KYBERNETIK", "AUTOMATISCH", "SYNTHETISCH", "ENERGETISCH",
			"ZERSTOERER", "KOMMANDANT", "GLADIATOR", "UNSTERBLICH", "VERGELTUNG", "ABRECHNUNG",
			"ERZENGEL", "ERZDAEMON", "VERKUNDIGER", "HENKER", "EROBERER", "REBELLION",
			"EVOLUTION", "EXPLOSION", "IMPLOSION", "KOLLISION", "DIMENSION", "EXPANSION"
		],
		# 10+ letter words (60 words)
		10: [
			"APOKALYPSE", "ARMAGEDDON", "KATAKLYSMUS", "VERNICHTER", "TERMINATOR", "DEZIMATOR",
			"AUSLOESCHER", "ELIMINATOR", "DOMINATOR", "VERHEERER", "AUSROTTER", "INQUISITOR",
			"JUGGERNAUT", "MONSTRUM", "ABSCHEULICH", "KATASTROPHE", "ZERSTOERUNG", "REVOLUTION",
			"ENTWICKLUNG", "KORRUPTION", "DOMINANZ", "VERNICHTUNG", "AUSLOESCHUNG", "AUSROTTUNG",
			"BESCHLEUNIG", "VERLANGSAM"
		],
		11: [
			"UNAUFHALTSAM", "UNZERBRECHLICH", "UNBESIEGBAR", "UNZERSTOERBAR", "UEBERWELTLICH",
			"GEWITTERSTURM", "AUSLOESCHUNG", "VERNICHTUNG", "AUSROTTUNG", "DESINTEGRIEREN",
			"VERNICHTER", "SCHLACHTKREUZER", "SCHLACHTSCHIFF", "ABFANGJAEGER", "MUTTERSCHIFF"
		],
		12: [
			"EXTERMINIEREN", "VERNICHTEND", "AUSLOESCHEND", "UEBERWAELTIGEND", "DESINTEGRATION",
			"TRANSZENDENZ", "METAMORPHOSE", "GROSSARTIGKEIT", "AUSSERGEWOEHNLICH", "KATASTROPHAL"
		]
	}
}

func _ready() -> void:
	DebugHelper.log_info("WordSetLoader initialized with length-based word pools")

func set_language(lang: Language) -> void:
	if current_language != lang:
		current_language = lang
		reset_used_words()
		DebugHelper.log_info("Language set to: %s" % ("DE" if lang == Language.DE else "EN"))

func set_language_string(lang_str: String) -> void:
	match lang_str.to_upper():
		"DE", "DEUTSCH", "GERMAN":
			set_language(Language.DE)
		_:
			set_language(Language.EN)

func get_language() -> Language:
	return current_language

func get_language_string() -> String:
	return "DE" if current_language == Language.DE else "EN"

func reset_used_words() -> void:
	used_words.clear()

func get_words_for_length(length: int) -> Array:
	var lang_words: Dictionary = WORDS_BY_LENGTH[current_language]
	if lang_words.has(length):
		return lang_words[length]
	return []

func get_words_in_range(min_len: int, max_len: int) -> Array:
	var result: Array = []
	var lang_words: Dictionary = WORDS_BY_LENGTH[current_language]
	for length in lang_words.keys():
		if length >= min_len and length <= max_len:
			result.append_array(lang_words[length])
	return result

func get_random_word(options: Dictionary = {}) -> String:
	var min_length: int = options.get("min_length", 2)
	var max_length: int = options.get("max_length", 20)
	var avoid_letters: Array = options.get("avoid_letters", [])

	# Get all words in the length range
	var available_words: Array = []
	var lang_words: Dictionary = WORDS_BY_LENGTH[current_language]

	# Track used words key
	var range_key := "%d_%d_%d" % [current_language, min_length, max_length]
	if not used_words.has(range_key):
		used_words[range_key] = []

	# Collect words from appropriate length groups
	for length in lang_words.keys():
		if length >= min_length and length <= max_length:
			for word in lang_words[length]:
				# Skip used words
				if word in used_words[range_key]:
					continue

				# Avoid certain starting letters
				var skip := false
				for letter in avoid_letters:
					if word.begins_with(letter):
						skip = true
						break
				if skip:
					continue

				available_words.append(word)

	# Reset if all words used
	if available_words.is_empty():
		used_words[range_key] = []
		for length in lang_words.keys():
			if length >= min_length and length <= max_length:
				for word in lang_words[length]:
					var skip := false
					for letter in avoid_letters:
						if word.begins_with(letter):
							skip = true
							break
					if not skip:
						available_words.append(word)

	if available_words.is_empty():
		return "ERROR"

	# Pick random word
	var word: String = available_words[randi() % available_words.size()]
	used_words[range_key].append(word)
	return word

func get_word_for_wave(wave_number: int, avoid_letters: Array = []) -> String:
	# Calculate length range based on wave (scales to wave 50)
	# Wave 1-5:   2-3 letters (very easy)
	# Wave 6-10:  3-4 letters (easy)
	# Wave 11-15: 3-5 letters (easy-medium)
	# Wave 16-20: 4-5 letters (medium)
	# Wave 21-25: 4-6 letters (medium)
	# Wave 26-30: 5-7 letters (medium-hard)
	# Wave 31-35: 5-8 letters (hard)
	# Wave 36-40: 6-9 letters (hard)
	# Wave 41-45: 7-10 letters (very hard)
	# Wave 46-50: 8-11 letters (extreme)
	# Wave 50+:   9-12 letters (maximum)
	
	var min_len: int
	var max_len: int

	if wave_number <= 5:
		min_len = 2
		max_len = 3
	elif wave_number <= 10:
		min_len = 3
		max_len = 4
	elif wave_number <= 15:
		min_len = 3
		max_len = 5
	elif wave_number <= 20:
		min_len = 4
		max_len = 5
	elif wave_number <= 25:
		min_len = 4
		max_len = 6
	elif wave_number <= 30:
		min_len = 5
		max_len = 7
	elif wave_number <= 35:
		min_len = 5
		max_len = 8
	elif wave_number <= 40:
		min_len = 6
		max_len = 9
	elif wave_number <= 45:
		min_len = 7
		max_len = 10
	elif wave_number <= 50:
		min_len = 8
		max_len = 11
	else:
		# Wave 50+: Maximum difficulty
		min_len = 9
		max_len = 12

	return get_random_word({
		"min_length": min_len,
		"max_length": max_len,
		"avoid_letters": avoid_letters
	})

func generate_wave_words(wave_number: int, enemy_count: int) -> Array:
	var words: Array = []
	var used_first_letters: Array = []

	for i in range(enemy_count):
		var word := get_word_for_wave(wave_number, used_first_letters)
		words.append(word)

		# Track first letter to avoid conflicts
		if word.length() > 0:
			used_first_letters.append(word[0])

	return words

func get_word_complexity(word: String) -> int:
	var complexity := 1

	# Length adds complexity
	if word.length() >= 4:
		complexity += 1
	if word.length() >= 6:
		complexity += 1
	if word.length() >= 8:
		complexity += 1
	if word.length() >= 10:
		complexity += 1

	return mini(complexity, 5)

func get_total_word_count() -> int:
	var count := 0
	var lang_words: Dictionary = WORDS_BY_LENGTH[current_language]
	for length in lang_words.keys():
		count += lang_words[length].size()
	return count
