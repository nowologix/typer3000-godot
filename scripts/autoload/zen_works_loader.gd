## zen_works_loader.gd
## Loads and manages literary works for ZEN mode
## Scans works folder and loads metadata dynamically
extends Node

# Work data structure
class ZenWork:
	var id: String
	var title: String
	var author: String
	var language: String  # "DE" or "EN"
	var description: String
	var folder_path: String
	var text_path: String
	var preview_path: String
	var background_path: String  # Video or image
	var overlay_path: String  # PNG overlay on top of text (optional)
	var music_path: String
	var word_count: int = 0
	var raw_text: String = ""
	var is_loaded: bool = false

# Registry of available works
var works: Dictionary = {}  # id -> ZenWork
var works_by_language: Dictionary = {"DE": [], "EN": []}

# Base path for works
const WORKS_BASE_PATH := "res://assets/zen/works/"

func _ready() -> void:
	_scan_works_folder()
	DebugHelper.log_info("ZenWorksLoader: Found %d works" % works.size())

func _scan_works_folder() -> void:
	var dir := DirAccess.open(WORKS_BASE_PATH)
	if dir == null:
		DebugHelper.log_error("ZenWorksLoader: Cannot open works folder: %s" % WORKS_BASE_PATH)
		return

	dir.list_dir_begin()
	var folder_name: String = dir.get_next()

	while folder_name != "":
		if dir.current_is_dir() and not folder_name.begins_with("."):
			_load_work_from_folder(folder_name)
		folder_name = dir.get_next()

	dir.list_dir_end()

func _load_work_from_folder(folder_name: String) -> void:
	var folder_path := WORKS_BASE_PATH + folder_name + "/"
	var meta_path := folder_path + "meta.json"

	# Check if meta.json exists
	if not FileAccess.file_exists(meta_path):
		DebugHelper.log_warning("ZenWorksLoader: No meta.json in %s" % folder_name)
		return

	# Load meta.json
	var file := FileAccess.open(meta_path, FileAccess.READ)
	if file == null:
		DebugHelper.log_error("ZenWorksLoader: Cannot read meta.json in %s" % folder_name)
		return

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(json_text)
	if error != OK:
		DebugHelper.log_error("ZenWorksLoader: Invalid JSON in %s: %s" % [folder_name, json.get_error_message()])
		return

	var meta: Dictionary = json.data

	# Create work entry
	var work := ZenWork.new()
	work.id = folder_name
	work.title = meta.get("title", folder_name)
	work.author = meta.get("author", "Unknown")
	work.language = meta.get("language", "DE")
	work.description = meta.get("description", "")
	work.folder_path = folder_path

	# Find text file
	work.text_path = _find_file(folder_path, ["text.html", "text.htm", "text.txt"])

	# Find preview image (640x380)
	work.preview_path = _find_file(folder_path, ["preview.png", "preview.jpg", "preview.jpeg", "preview.webp"])

	# Find background (video preferred, image fallback)
	work.background_path = _find_file(folder_path, ["background.ogv", "background.webm", "background.png", "background.jpg", "background.jpeg"])

	# Find music
	work.music_path = _find_file(folder_path, ["music.ogg", "music.mp3", "music.wav"])

	# Find overlay (optional, on top of text)
	work.overlay_path = _find_file(folder_path, ["overlay.png", "overlay.jpg", "overlay.webp"])

	if work.text_path.is_empty():
		DebugHelper.log_warning("ZenWorksLoader: No text file in %s" % folder_name)
		return

	# Register work
	works[work.id] = work
	if not works_by_language.has(work.language):
		works_by_language[work.language] = []
	works_by_language[work.language].append(work.id)

	DebugHelper.log_info("ZenWorksLoader: Registered '%s' by %s (%s) - text: %s, bg: %s" % [work.title, work.author, work.language, work.text_path, work.background_path])

func _find_file(folder_path: String, filenames: Array) -> String:
	for filename in filenames:
		var path: String = folder_path + filename
		if FileAccess.file_exists(path):
			DebugHelper.log_info("ZenWorksLoader: Found file: %s" % path)
			return path
	DebugHelper.log_warning("ZenWorksLoader: No file found in %s for patterns: %s" % [folder_path, filenames])
	return ""

func get_works_for_language(lang: String) -> Array:
	var result := []
	for work_id in works_by_language.get(lang, []):
		result.append(works[work_id])
	return result

func get_all_works() -> Array:
	return works.values()

func get_work(work_id: String) -> ZenWork:
	return works.get(work_id, null)

# Load and parse HTML content for a work
func load_work_content(work_id: String) -> String:
	DebugHelper.log_info("ZenWorksLoader: load_work_content called for: %s" % work_id)
	var work := get_work(work_id)
	if work == null:
		DebugHelper.log_error("ZenWorksLoader: Work not found: %s" % work_id)
		return ""

	DebugHelper.log_info("ZenWorksLoader: Work found - title: %s, text_path: %s, is_loaded: %s" % [work.title, work.text_path, work.is_loaded])

	if work.is_loaded:
		DebugHelper.log_info("ZenWorksLoader: Returning cached text (%d chars)" % work.raw_text.length())
		return work.raw_text

	# Check if file exists first
	if not FileAccess.file_exists(work.text_path):
		DebugHelper.log_error("ZenWorksLoader: File does not exist: %s" % work.text_path)
		return ""

	# Read text file
	DebugHelper.log_info("ZenWorksLoader: Opening file: %s" % work.text_path)
	var file := FileAccess.open(work.text_path, FileAccess.READ)
	if file == null:
		var error := FileAccess.get_open_error()
		DebugHelper.log_error("ZenWorksLoader: Cannot open file: %s (error: %d)" % [work.text_path, error])
		return ""

	var content := file.get_as_text(true)  # skip_cr for Windows
	file.close()
	DebugHelper.log_info("ZenWorksLoader: Read %d chars from file" % content.length())
	DebugHelper.log_info("ZenWorksLoader: First 100 chars: %s" % content.substr(0, 100))

	# Parse based on file type
	if work.text_path.ends_with(".html") or work.text_path.ends_with(".htm"):
		work.raw_text = _parse_html_to_text(content)
	else:
		work.raw_text = content

	work.word_count = work.raw_text.split(" ").size()
	work.is_loaded = true

	if work.raw_text.length() < 100:
		DebugHelper.log_error("ZenWorksLoader: Text too short for %s - parsing may have failed! First 200 chars of HTML: %s" % [work_id, content.substr(0, 200)])
	else:
		DebugHelper.log_info("ZenWorksLoader: Loaded %s (%d chars, ~%d words)" % [work_id, work.raw_text.length(), work.word_count])
	return work.raw_text

# Parse HTML and extract clean text with preserved structure
func _parse_html_to_text(html: String) -> String:
	var text := html
	DebugHelper.log_info("ZenWorksLoader: Parsing HTML, length: %d" % html.length())

	# Try to find content start - use flexible matching
	var start_patterns := [
		'<p class="first"',       # Gutenberg German (Zauberberg)
		'<div class="poem"',      # Poetry (Stundenbuch) - may have style attr
		'<div class="stanza"',    # Poetry stanzas
		'<div class="chapter"',   # Chapter start (Walden)
		'<p class="poem"',        # Gutenberg poetry
		'<p class="noindent"',    # Gutenberg prose
		'<p>INTRODUCTION',        # Nature/Emerson
		'<body',                  # Fallback: body tag
	]
	var found_marker := false
	for pattern in start_patterns:
		var idx := text.find(pattern)
		DebugHelper.log_info("ZenWorksLoader: Pattern '%s' -> idx %d" % [pattern, idx])
		if idx >= 0:  # Changed from > 0 to >= 0 to catch patterns at start
			text = text.substr(idx)
			DebugHelper.log_info("ZenWorksLoader: Found content start at '%s' (pos %d)" % [pattern, idx])
			found_marker = true
			break

	if not found_marker:
		DebugHelper.log_warning("ZenWorksLoader: No content marker found! Using full HTML. First 300 chars: %s" % html.substr(0, 300))

	# Remove <pre> blocks
	text = _remove_tag_content(text, "pre")

	# Remove script and style tags
	text = _remove_tag_content(text, "script")
	text = _remove_tag_content(text, "style")

	# Remove comments
	var regex := RegEx.new()
	regex.compile("<!--[\\s\\S]*?-->")
	text = regex.sub(text, "", true)

	# Convert <br> to newlines
	regex.compile("<br\\s*/?>")
	text = regex.sub(text, "\n", true)

	# Convert paragraph and div endings to double newlines
	regex.compile("</p>|</div>")
	text = regex.sub(text, "\n\n", true)

	# Convert headers to newlines with the text preserved
	regex.compile("<h[1-6][^>]*>")
	text = regex.sub(text, "\n\n", true)
	regex.compile("</h[1-6]>")
	text = regex.sub(text, "\n\n", true)

	# Remove all remaining HTML tags
	regex.compile("<[^>]+>")
	text = regex.sub(text, "", true)

	# Decode HTML entities
	text = _decode_html_entities(text)

	# Normalize whitespace
	regex.compile("[ \\t]+")
	text = regex.sub(text, " ", true)

	# Replace multiple newlines with double newline (paragraph break)
	regex.compile("\\n\\s*\\n\\s*\\n+")
	text = regex.sub(text, "\n\n", true)

	# Trim leading/trailing whitespace from each line
	var lines := text.split("\n")
	var cleaned_lines := []
	for line in lines:
		var trimmed := line.strip_edges()
		if not trimmed.is_empty():
			cleaned_lines.append(trimmed)

	text = "\n".join(cleaned_lines)
	text = text.strip_edges()

	DebugHelper.log_info("ZenWorksLoader: Parsed text length: %d chars, first 200: %s" % [text.length(), text.substr(0, 200)])
	return text

func _remove_tag_content(text: String, tag: String) -> String:
	var regex := RegEx.new()
	regex.compile("<%s[^>]*>[\\s\\S]*?</%s>" % [tag, tag])
	return regex.sub(text, "", true)

func _decode_html_entities(text: String) -> String:
	var entities := {
		"&nbsp;": " ",
		"&amp;": "&",
		"&lt;": "<",
		"&gt;": ">",
		"&quot;": "\"",
		"&apos;": "'",
		"&#39;": "'",
		"&auml;": "ä",
		"&ouml;": "ö",
		"&uuml;": "ü",
		"&Auml;": "Ä",
		"&Ouml;": "Ö",
		"&Uuml;": "Ü",
		"&szlig;": "ß",
		"&mdash;": "—",
		"&ndash;": "–",
		"&hellip;": "…",
		"&laquo;": "«",
		"&raquo;": "»",
		"&bdquo;": "„",
		"&ldquo;": """,
		"&rdquo;": """,
	}

	for entity in entities:
		text = text.replace(entity, entities[entity])

	# Handle numeric entities like &#228; (ä)
	var regex := RegEx.new()
	regex.compile("&#(\\d+);")
	var matches := regex.search_all(text)
	for m in matches:
		var code := int(m.get_string(1))
		if code > 0 and code < 65536:
			text = text.replace(m.get_string(), char(code))

	return text

# Get text as an array of glyphs for rendering
class Glyph:
	var char: String
	var index: int
	var is_typed: bool = false
	var is_whitespace: bool = false
	var is_newline: bool = false
	var line_index: int = 0
	var char_in_line: int = 0

func text_to_glyphs(text: String) -> Array:
	var glyphs := []
	var line_idx := 0
	var char_in_line := 0

	for i in range(text.length()):
		var c := text[i]
		var glyph := Glyph.new()
		glyph.char = c
		glyph.index = i
		glyph.is_whitespace = c == " " or c == "\t"
		glyph.is_newline = c == "\n"
		glyph.line_index = line_idx
		glyph.char_in_line = char_in_line

		glyphs.append(glyph)

		if glyph.is_newline:
			line_idx += 1
			char_in_line = 0
		else:
			char_in_line += 1

	return glyphs
