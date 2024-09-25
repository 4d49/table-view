# Copyright (c) 2024 Mansur Isaev and contributors - MIT License
# See `LICENSE.md` included in the source distribution for details.

class_name TableView
extends Control


signal column_clicked(column_idx: int)
signal column_rmb_clicked(column_idx: int)
signal column_double_clicked(column_idx: int)

signal row_clicked(row_idx: int)
signal row_rmb_clicked(row_idx: int)
signal row_double_clicked(row_idx: int)

signal cell_clicked(row_idx: int, column_idx: int)
signal cell_rmb_clicked(row_idx: int, column_idx: int)
signal cell_double_clicked(row_idx: int, column_idx: int)

signal row_selected(row_idx: int)


const NUMBERS_AFTER_DOT = 3

const DEBUG_ENABLED: bool = false


enum Type {
	BOOL = TYPE_BOOL,
	INT = TYPE_INT,
	FLOAT = TYPE_FLOAT,
	STRING = TYPE_STRING,
	COLOR = TYPE_COLOR,
	STRING_NAME = TYPE_STRING_NAME,
	MAX,
}
enum Hint {
	NONE = PROPERTY_HINT_NONE,
	RANGE = PROPERTY_HINT_RANGE,
	ENUM = PROPERTY_HINT_ENUM,
	FLAGS = PROPERTY_HINT_FLAGS,
	COLOR_NO_ALPHA = PROPERTY_HINT_COLOR_NO_ALPHA,
}
enum DrawMode {
	NORMAL,
	PRESSED,
	HOVER,
}
enum ColumnResizeMode {
	STRETCH,
#	INTERACTIVE,
#	FIXED,
#	RESIZE_TO_CONTENTS,
}
enum SortMode {
	NONE,
	ASCENDING,
	DESCENDING,
}
enum SelectMode {
	DISABLED,
	SINGLE_ROW,
	MULTI_ROW,
}


const DEFAULT_NUM_MIN = -2147483648
const DEFAULT_NUM_MAX =  2147483647

const INVALID_COLUMN: int = -1
const INVALID_ROW: int = -1
const INVALID_CELL: int = -1


@export var column_resize_mode: ColumnResizeMode = ColumnResizeMode.STRETCH
@export var select_mode: SelectMode = SelectMode.SINGLE_ROW:
	set = set_select_mode,
	get = get_select_mode


var _dirty: bool = true

var _header: Rect2i = Rect2i()

var _v_scroll: VScrollBar = null
var _h_scroll: HScrollBar = null

var _columns: Array[Dictionary] = []
var _rows: Array[Dictionary] = []

var _canvas: RID = RID()

var _cell_editor: Node = null

#region theme cache
var _inner_margin_left: float = 0
var _inner_margin_right: float = 0
var _inner_margin_top: float = 0
var _inner_margin_bottom: float = 0

var _font: Font = null
var _font_size: int = 0
var _font_color: Color = Color.BLACK

var _font_outline_size: int = 0
var _font_outline_color: Color = Color.BLACK

var _panel: StyleBox = null
var _focus: StyleBox = null

var _row_normal: StyleBox = null
var _row_selected: StyleBox = null
var _row_alternate: StyleBox = null

var _column_normal: StyleBox = null
var _column_hover: StyleBox = null
var _column_pressed: StyleBox = null

var _cell_edit: StyleBox = null
var _cell_edit_empty: StyleBox = null

var _checked: Texture2D = null
var _unchecked: Texture2D = null

var _sort_ascending: Texture2D = null
var _sort_descending: Texture2D = null
#endregion


@warning_ignore("return_value_discarded")
func _init() -> void:
	self.set_clip_contents(not DEBUG_ENABLED)
	self.set_focus_mode(Control.FOCUS_CLICK)
	self.set_mouse_filter(Control.MOUSE_FILTER_STOP)

	_v_scroll = VScrollBar.new()
	_v_scroll.hide()
	_v_scroll.set_step(1.0)
	_v_scroll.set_use_rounded_values(true)
	_v_scroll.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_v_scroll.value_changed.connect(_on_scroll_value_changed)
	self.add_child(_v_scroll)

	_h_scroll = HScrollBar.new()
	_h_scroll.hide()
	_h_scroll.set_step(1.0)
	_h_scroll.set_use_rounded_values(true)
	_h_scroll.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_h_scroll.value_changed.connect(_on_scroll_value_changed)
	self.add_child(_h_scroll)

	self.column_clicked.connect(_on_column_clicked)
	self.cell_double_clicked.connect(_on_cell_double_click)
	self.row_clicked.connect(select_single_row)

@warning_ignore("unsafe_call_argument")
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			update_table(true)

		NOTIFICATION_DRAW when DEBUG_ENABLED:
			if is_dirty():
				update_table()

			update_cell_editor_position_and_size()

			draw_rect(Rect2(Vector2.ZERO, get_size()), Color(Color.BLACK, 0.5))
			if has_focus():
				draw_rect(Rect2(Vector2.ZERO, get_size()), Color(Color.RED, 0.5), false, 2.0)

			draw_rect(_header, Color(Color.RED, 0.5))

			var drawable_rect: Rect2 = get_drawable_rect()
			draw_rect(drawable_rect, Color(Color.GREEN, 0.25))

			for row: Dictionary in _rows:
				if not row.visible:
					continue

				var rect := scrolled_rect(row.rect)
				if not drawable_rect.intersects(rect):
					continue

				if row.selected:
					draw_rect(rect, Color(Color.WHITE.lerp(row.color, 0.25), 0.5))
				else:
					draw_rect(rect, Color(row.color, 0.5))

				for cell: Dictionary in row.cells:
					rect = scrolled_rect(cell.rect)
					if not drawable_rect.intersects(rect):
						continue

					rect = inner_margin_rect(rect)
					draw_rect(rect, Color(cell.color, 0.25))

					match cell.type_hint.type:
						Type.BOOL:
							var texture: Texture2D = _checked if cell.value else _unchecked
							texture.draw(get_canvas_item(), get_text_position(rect, texture.get_size(), HORIZONTAL_ALIGNMENT_LEFT))
						Type.COLOR:
							draw_rect(inner_margin_rect(rect), cell.value)
						_:
							draw_text_line(get_canvas_item(), cell.text_line, Color.WHITE, 2, Color.BLACK, rect)

			for column: Dictionary in _columns:
				if not column.visible:
					continue

				var rect := scrolled_rect_horizontal(column.rect)
				if not drawable_rect.intersects(rect):
					continue

				rect = inner_margin_rect(rect)
				draw_rect(rect, Color(column.color, 0.5))
				draw_text_line(get_canvas_item(), column.text_line, Color.WHITE, 2, Color.BLACK, rect)

		NOTIFICATION_DRAW:
			if is_dirty():
				update_table()

			update_cell_editor_position_and_size()

			_panel.draw(get_canvas_item(), Rect2(Vector2.ZERO, get_size()))
			if has_focus():
				_focus.draw(get_canvas_item(), Rect2(Vector2.ZERO, get_size()))

			RenderingServer.canvas_item_clear(_canvas)

			var drawable_rect: Rect2 = get_drawable_rect()
			RenderingServer.canvas_item_set_custom_rect(_canvas, true, drawable_rect)
			RenderingServer.canvas_item_set_clip(_canvas, true)

			var draw_begun: bool = false

			var idx: int = 0
			for row: Dictionary in _rows:
				if not row.visible:
					continue

				var rect := scrolled_rect(row.rect)
				if drawable_rect.intersects(rect):
					draw_begun = true
				else:
					if draw_begun:
						break
					else:
						continue

				if row.selected:
					_row_selected.draw(_canvas, rect)
				elif idx % 2:
					_row_alternate.draw(_canvas, rect)
				else:
					_row_normal.draw(_canvas, rect)

				var cells: Array[Dictionary] = row.cells
				for j: int in _columns.size():
					if not _columns[j][&"visible"]:
						continue

					var cell: Dictionary = cells[j]
					rect = scrolled_rect(cell.rect)
					if not drawable_rect.intersects(rect):
						continue

					match cell.type_hint.type:
						Type.BOOL:
							var texture: Texture2D = _checked if cell.value else _unchecked
							texture.draw(_canvas, get_text_position(inner_margin_rect(rect), texture.get_size(), HORIZONTAL_ALIGNMENT_LEFT))
						Type.COLOR:
							RenderingServer.canvas_item_add_rect(_canvas, inner_margin_rect(rect), cell.value)
						_:
							draw_text_line(_canvas, cell.text_line, _font_color, _font_outline_size, _font_outline_color, inner_margin_rect(rect))

				idx += 1

			for column: Dictionary in _columns:
				if not column.visible:
					continue

				var rect := scrolled_rect_horizontal(column.rect)
				if not drawable_rect.intersects(rect):
					continue

				match column.draw_mode:
					DrawMode.NORMAL:
						_column_normal.draw(_canvas, rect)
					DrawMode.HOVER:
						_column_hover.draw(_canvas, rect)
					DrawMode.PRESSED:
						_column_pressed.draw(_canvas, rect)

				var icon := get_sort_mode_icon(column.sort_mode)
				if is_instance_valid(icon):
					icon.draw(_canvas, get_text_position(inner_margin_rect(rect), icon.get_size(), HORIZONTAL_ALIGNMENT_RIGHT))

				draw_text_line(_canvas, column.text_line, _font_color, _font_outline_size, _font_outline_color, inner_margin_rect(rect))

		NOTIFICATION_THEME_CHANGED:
			_inner_margin_left = get_theme_constant(&"inner_margin_left", &"TableView")
			_inner_margin_right = get_theme_constant(&"inner_margin_right", &"TableView")
			_inner_margin_top = get_theme_constant(&"inner_margin_top", &"TableView")
			_inner_margin_bottom = get_theme_constant(&"inner_margin_bottom", &"TableView")

			_font = get_theme_font(&"font", &"TableView")
			_font_size = get_theme_font_size(&"font_size", &"TableView")
			_font_color = get_theme_color(&"font_color", &"TableView")

			_font_outline_size = get_theme_constant(&"outline_size", &"TableView")
			_font_outline_color = get_theme_color(&"font_outline_color", &"TableView")

			_panel = get_theme_stylebox(&"panel", &"TableView")
			_focus = get_theme_stylebox(&"focus", &"TableView")

			_row_normal = get_theme_stylebox(&"row_normal", &"TableView")
			_row_selected = get_theme_stylebox(&"row_selected", &"TableView")
			_row_alternate = get_theme_stylebox(&"row_alternate", &"TableView")

			_column_hover = get_theme_stylebox(&"column_hover", &"TableView")
			_column_normal = get_theme_stylebox(&"column_normal", &"TableView")
			_column_pressed = get_theme_stylebox(&"column_pressed", &"TableView")

			_cell_edit = get_theme_stylebox(&"cell_edit", &"TableView")
			_cell_edit_empty = get_theme_stylebox(&"cell_edit_empty", &"TableView")

			# INFO: To avoid adding custom icons, used icons from Tree.
			_checked = get_theme_icon(&"checked", &"Tree")
			_unchecked = get_theme_icon(&"unchecked", &"Tree")

			_sort_ascending = get_theme_icon(&"sort_ascending", &"TableView")
			_sort_descending = get_theme_icon(&"sort_descending", &"TableView")

		NOTIFICATION_ENTER_CANVAS:
			_canvas = RenderingServer.canvas_item_create()
			RenderingServer.canvas_item_set_parent(_canvas, get_canvas_item())

		NOTIFICATION_EXIT_CANVAS:
			RenderingServer.free_rid(_canvas)

@warning_ignore("unsafe_method_access", "unsafe_call_argument", "return_value_discarded")
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		for column: Dictionary in _columns:
			if not column.visible:
				continue
			elif scrolled_rect_horizontal(column.rect).has_point(event.get_position()):
				column.draw_mode = DrawMode.HOVER
			else:
				column.draw_mode = DrawMode.NORMAL

		queue_redraw()

	elif event is InputEventMouseButton and event.is_pressed():
		const SCROLL_FACTOR = 0.25

		match event.get_button_index():
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				if is_select_mode_disabled():
					return
				elif header_has_point(event.get_position()):
					var column_idx := find_column_at_position(scrolled_position_horizontal(event.get_position()))
					if column_idx == INVALID_COLUMN:
						return
					elif event.get_button_index() == MOUSE_BUTTON_LEFT:
						if event.is_double_click():
							column_double_clicked.emit(column_idx)
						else:
							column_clicked.emit(column_idx)
					else:
						column_rmb_clicked.emit(column_idx)
				else:
					var row_idx := find_row_at_position(scrolled_position(event.get_position()))
					if row_idx == INVALID_ROW:
						return
					elif event.get_button_index() == MOUSE_BUTTON_LEFT:
						if event.is_ctrl_pressed():
							toggle_row_selected(row_idx)
						elif event.is_shift_pressed():
							select_row(row_idx)
						elif event.is_double_click():
							row_double_clicked.emit(row_idx)
						else:
							row_clicked.emit(row_idx)
					else:
						row_rmb_clicked.emit(row_idx)

					var cell_idx := find_cell_at_position(row_idx, scrolled_position(event.get_position()))
					if cell_idx == INVALID_CELL:
						return
					elif event.get_button_index() == MOUSE_BUTTON_LEFT:
						if event.is_double_click():
							cell_double_clicked.emit(row_idx, cell_idx)
						else:
							cell_clicked.emit(row_idx, cell_idx)
					else:
						cell_rmb_clicked.emit(row_idx, cell_idx)

			MOUSE_BUTTON_WHEEL_DOWN:
				if event.is_shift_pressed():
					_horizontal_scroll(event.get_factor() * SCROLL_FACTOR)
				else:
					_vertical_scroll(event.get_factor() * SCROLL_FACTOR)
			MOUSE_BUTTON_WHEEL_UP:
				if event.is_shift_pressed():
					_horizontal_scroll(-event.get_factor() * SCROLL_FACTOR)
				else:
					_vertical_scroll(-event.get_factor() * SCROLL_FACTOR)

	elif event.is_action_pressed(&"ui_text_select_all"):
		select_all_rows()

	else:
		return

	accept_event()


func _get_tooltip(at_position: Vector2) -> String:
	if header_has_point(at_position):
		var column_idx := find_column_at_position(scrolled_position_horizontal(at_position))
		if column_idx != INVALID_COLUMN:
			return get_column_title(column_idx)
	else:
		at_position = scrolled_position(at_position)

		var row_idx := find_row_at_position(at_position)
		if row_idx != INVALID_ROW:
			var cell_idx := find_cell_at_position(row_idx, at_position)
			if cell_idx != INVALID_CELL:
				return stringify_cell(row_idx, cell_idx)

	return get_tooltip_text()

## Returns [Rect2] with margin offsets.
func inner_margin_rect(rect: Rect2) -> Rect2:
	return rect.grow_individual(-_inner_margin_left, -_inner_margin_top, -_inner_margin_right, -_inner_margin_bottom)


func mark_dirty() -> void:
	if _dirty:
		return

	_dirty = true
	queue_redraw()

func is_dirty() -> bool:
	return _dirty


func set_select_mode(n_select_mode: SelectMode) -> void:
	if select_mode == n_select_mode:
		return

	select_mode = n_select_mode

func get_select_mode() -> SelectMode:
	return select_mode

func is_select_mode_disabled() -> bool:
	return select_mode == SelectMode.DISABLED

func is_select_mode_single_row() -> bool:
	return select_mode == SelectMode.SINGLE_ROW

func is_select_mode_multi_row() -> bool:
	return select_mode == SelectMode.MULTI_ROW



func header_has_point(point: Vector2) -> bool:
	return _header.has_point(point)


func get_drawable_rect() -> Rect2i:
	var drawable_rect := Rect2i(Vector2i.ZERO, get_size())

	@warning_ignore("narrowing_conversion")
	drawable_rect = drawable_rect.grow_individual(
		-_panel.get_margin(SIDE_LEFT),
		-_panel.get_margin(SIDE_TOP),
		-_v_scroll.get_minimum_size().x if _v_scroll.is_visible() else -_panel.get_margin(SIDE_RIGHT),
		-_h_scroll.get_minimum_size().y if _h_scroll.is_visible() else -_panel.get_margin(SIDE_BOTTOM),
	)

	return drawable_rect.abs()


func get_sort_mode_icon(sort_mode: SortMode) -> Texture2D:
	match sort_mode:
		SortMode.ASCENDING:
			return _sort_ascending
		SortMode.DESCENDING:
			return _sort_descending

	return null

func calculate_column_rect(text_size: Vector2i, texture: Texture2D) -> Rect2i:
	const H_SEPARATION = 4

	var rect := Rect2i(Vector2i.ZERO, text_size)
	if is_instance_valid(texture):
		return rect.merge(Rect2i(
				rect.position.x + rect.size.x + H_SEPARATION,
				rect.position.y + rect.size.y / 2 - texture.get_height() / 2,
				texture.get_width(), texture.get_height()
			)
		)

	return rect

@warning_ignore("unsafe_call_argument", "return_value_discarded", "narrowing_conversion")
func update_table(force: bool = false) -> void:
	if _columns.is_empty():
		return

	#region update column text
	for column: Dictionary in _columns:
		if not column.visible:
			continue

		var text_line: TextLine = column.text_line
		if force or column.dirty:
			text_line.clear()
			text_line.add_string(column.title, _font, _font_size)

		column.rect = calculate_column_rect(text_line.get_size(), get_sort_mode_icon(column.sort_mode))
		column.dirty = false
	#endregion

	var cell_height: int = _font.get_height(_font_size) + _inner_margin_top + _inner_margin_bottom
	var drawable_rect := get_drawable_rect()

	match column_resize_mode:
		ColumnResizeMode.STRETCH:
			var min_size := Vector2i.ZERO

			var count_visible_columns: int = 0
			for column: Dictionary in _columns:
				if not column.visible:
					continue

				min_size = min_size.max(column.rect.size)
				count_visible_columns += 1

			var ofs_x: int = drawable_rect.position.x
			var ofs_y: int = drawable_rect.position.y

			var rect := Rect2i(ofs_x, ofs_y, maxi(min_size.x + _inner_margin_left + _inner_margin_right, drawable_rect.size.x / count_visible_columns), cell_height)
			_header = rect

			for column: Dictionary in _columns:
				if not column.visible:
					continue

				column.rect = rect
				_header.end = rect.end

				rect.position.x += rect.size.x

	if _rows:
		var content_rect := drawable_rect

		var row_ofs: int = drawable_rect.position.y + _header.size.y

		var row_height: int = cell_height
		var row_width: int = _header.size.x

		for row: Dictionary in _rows:
			if not row.visible:
				continue

			var cell_ofs: int = drawable_rect.position.x

			if force or row.dirty:
				for i: int in _columns.size():
					if not _columns[i][&"visible"]:
						continue

					var cell: Dictionary = row.cells[i]
					var cell_width: int = _columns[i].rect.size.x

					var stringifier: Callable = cell.type_hint.stringifier

					var text_line: TextLine = cell.text_line
					text_line.clear()
					text_line.add_string(stringifier.call(cell.value), _font, _font_size)
					text_line.set_width(cell_width)

					cell.rect = Rect2i(cell_ofs, row_ofs, cell_width, row_height)
					cell_ofs += cell_width

			row.rect = Rect2i(drawable_rect.position.x, row_ofs, row_width, row_height)
			content_rect.end = row.rect.end

			row.dirty = false

			row_ofs += row_height

		if force:
			_h_scroll.set_max(content_rect.size.x)
			_h_scroll.set_page(drawable_rect.size.x)
			_h_scroll.set_visible(floorf(content_rect.size.x) > drawable_rect.size.x)
			_h_scroll.set_size(Vector2(drawable_rect.size.x, 0.0))
			_h_scroll.set_position(Vector2(0.0, size.y - _h_scroll.get_minimum_size().y))

			_v_scroll.set_max(content_rect.size.y)
			_v_scroll.set_page(drawable_rect.size.y)
			_v_scroll.set_visible(floorf(content_rect.size.y) > drawable_rect.size.y)
			_v_scroll.set_size(Vector2(0.0, drawable_rect.size.y))
			_v_scroll.set_position(Vector2(get_size().x - _v_scroll.get_minimum_size().x, 0.0))

	_dirty = false
	queue_redraw()


func update_cell_editor_position_and_size() -> void:
	if not is_instance_valid(_cell_editor) or not _cell_editor.has_meta(&"cell"):
		return

	var cell: Dictionary = _cell_editor.get_meta(&"cell")
	var rect: Rect2 = scrolled_rect(cell.rect)

	if _cell_editor.has_method(&"set_position"):
		_cell_editor.call(&"set_position", rect.position)
	if _cell_editor.has_method(&"set_size"):
		_cell_editor.call(&"set_size", rect.size)

	if _cell_editor.has_method(&"popup"):
		_cell_editor.call(&"popup")


static func color_to_string_no_alpha(color: Color) -> String:
	return (
		  "R: " + str(color.r).pad_decimals(NUMBERS_AFTER_DOT) +
		"\nG: " + str(color.g).pad_decimals(NUMBERS_AFTER_DOT) +
		"\nB: " + str(color.b).pad_decimals(NUMBERS_AFTER_DOT)
	)
static func color_to_string(color: Color) -> String:
	return (
			  "R: " + str(color.r).pad_decimals(NUMBERS_AFTER_DOT) +
			"\nG: " + str(color.g).pad_decimals(NUMBERS_AFTER_DOT) +
			"\nB: " + str(color.b).pad_decimals(NUMBERS_AFTER_DOT) +
			"\nA: " + str(color.a).pad_decimals(NUMBERS_AFTER_DOT)
		)

static func stringifier_default(type: Type, hint: Hint, hint_string: String) -> Callable:
	match type:
		Type.INT when hint == Hint.ENUM:
			var enumeration := hint_string_to_enum(hint_string)

			var values: Dictionary[int, String] = {}
			for key: StringName in enumeration:
				values[enumeration[key]] = String(key)

			values.make_read_only()

			return func(value: int) -> String:
				return values.get(value, "")

		Type.INT when hint == Hint.FLAGS:
			var flags := hint_string_to_flags(hint_string)

			return func(value: int) -> String:
				var string: String = ""

				for key: String in flags:
					if value & flags[key]:
						string += key + ", "

				return string.left(-2)

		Type.FLOAT:
			return hint_string.num.bind(NUMBERS_AFTER_DOT)
		Type.COLOR:
			return color_to_string_no_alpha if hint == Hint.COLOR_NO_ALPHA else color_to_string

	return str


static func type_hint_create(
		type: Type,
		hint: Hint,
		hint_string: String,
		stringifier: Callable,
		edit_handler: Callable,
	) -> Dictionary[StringName, Variant]:

	return {
		&"type": type,
		&"hint": hint,
		&"hint_string": hint_string,
		&"stringifier": stringifier,
		&"edit_handler": edit_handler,
	}


static func range_to_hint_string(min: float, max: float, step: float = 0.001) -> String:
	return String.num(min, NUMBERS_AFTER_DOT) + "," + String.num(max, NUMBERS_AFTER_DOT) + "," + String.num(maxf(step, 0.001), NUMBERS_AFTER_DOT)

static func hint_string_to_range(hint_string: String) -> PackedFloat64Array:
	var split: PackedStringArray = hint_string.split(",")

	return [
		split[0].to_float() if split.size() > 0 and split[0].is_valid_float() else DEFAULT_NUM_MIN,
		split[1].to_float() if split.size() > 1 and split[1].is_valid_float() else DEFAULT_NUM_MAX,
		split[2].to_float() if split.size() > 2 and split[2].is_valid_float() else 0.001,
	]


static func enum_to_hint_string(enumeration: Dictionary) -> String:
	var hint_string: String = ""

	for key: String in enumeration:
		hint_string += key + ":" + String.num_int64(enumeration[key]) + ","

	return hint_string.left(-1)

static func hint_string_to_enum(hint_string: String) -> Dictionary[StringName, int]:
	var enumeration: Dictionary[StringName, int] = {}

	var split: PackedStringArray = hint_string.split(",")
	for i: int in split.size():
		var subsplit: PackedStringArray = split[i].split(":")
		if subsplit.size() > 1:
			enumeration[StringName(subsplit[0])] = subsplit[1].to_int()
		else:
			enumeration[StringName(subsplit[0])] = i

	enumeration.make_read_only()
	return enumeration


static func flags_to_hint_string(flags: Dictionary) -> String:
	return enum_to_hint_string(flags)

static func hint_string_to_flags(hint_string: String) -> Dictionary[StringName, int]:
	var flags: Dictionary[StringName, int] = {}

	var split: PackedStringArray = hint_string.split(",")
	for i: int in split.size():
		var subsplit: PackedStringArray = split[i].split(":")
		if subsplit.size() > 1:
			flags[StringName(subsplit[0])] = subsplit[1].to_int()
		else:
			flags[StringName(subsplit[0])] = 1 << i

	flags.make_read_only()
	return flags


func set_cell_editor(cell_editor: Node) -> void:
	if is_instance_valid(_cell_editor):
		_cell_editor.queue_free()

	if is_instance_valid(cell_editor) and cell_editor.has_method(&"get_canvas_item"):
		RenderingServer.canvas_item_set_parent(cell_editor.call(&"get_canvas_item"), _canvas)

	_cell_editor = cell_editor


func edit_handler_default(type: Type, hint: Hint, hint_string: String) -> Callable:
	match type:
		Type.BOOL:
			return func(cell: Dictionary, setter: Callable, getter: Callable) -> void:
				setter.call(not getter.call())

		Type.INT when hint == Hint.ENUM:
			var enumeration := hint_string_to_enum(hint_string)

			return func(cell: Dictionary, setter: Callable, getter: Callable) -> void:
				var popup := PopupMenu.new()
				popup.add_theme_font_override(&"font", _font)
				popup.add_theme_font_size_override(&"font_size", _font_size)
				popup.add_theme_color_override(&"font_color", _font_color)
				popup.add_theme_constant_override(&"outline_size", _font_outline_size)
				popup.add_theme_color_override(&"font_outline_color", _font_outline_color)
				popup.add_theme_stylebox_override(&"panel", _cell_edit)

				for key: String in enumeration:
					popup.add_item(key, enumeration[key])

				popup.id_pressed.connect(setter)
				popup.focus_exited.connect(popup.queue_free)
				self.add_child(popup)

				var rect := scrolled_rect(cell.rect)
				popup.set_position(rect.position)
				popup.set_size(rect.size)

				popup.set_meta(&"cell", cell)
				self.set_cell_editor(popup)

				popup.popup()

		Type.INT when hint == Hint.FLAGS:
			var flags := hint_string_to_flags(hint_string)

			return func(cell: Dictionary, setter: Callable, getter: Callable) -> void:
				var popup := PopupMenu.new()
				popup.add_theme_font_override(&"font", _font)
				popup.add_theme_font_size_override(&"font_size", _font_size)
				popup.add_theme_color_override(&"font_color", _font_color)
				popup.add_theme_constant_override(&"outline_size", _font_outline_size)
				popup.add_theme_color_override(&"font_outline_color", _font_outline_color)
				popup.add_theme_stylebox_override(&"panel", _cell_edit)

				var value: int = getter.call()
				for key: StringName in flags:
					popup.add_check_item(key, flags[key])
					popup.set_item_checked(-1, value & flags[key])

				popup.id_pressed.connect(func(id: int) -> void:
					value = getter.call()

					if popup.is_item_checked(popup.get_item_index(id)):
						value &= ~id
					else:
						value |= id

					popup.set_item_checked(popup.get_item_index(id), not popup.is_item_checked(popup.get_item_index(id)))
					setter.call(value)
				)
				popup.focus_exited.connect(popup.queue_free)
				self.add_child(popup)

				var rect := scrolled_rect(cell.rect)
				popup.set_position(rect.position)
				popup.set_size(rect.size)

				popup.set_meta(&"cell", cell)
				self.set_cell_editor(popup)

				popup.popup()

		Type.INT, Type.FLOAT:
			return func(cell: Dictionary, setter: Callable, getter: Callable) -> void:
				var spin_box := SpinBox.new()
				spin_box.set_use_rounded_values(type == Type.INT)

				var range := hint_string_to_range(hint_string)
				spin_box.set_min(range[0])
				spin_box.set_max(range[1])
				spin_box.set_step(maxf(range[2], 1.0) if type == Type.INT else range[2])
				spin_box.set_value(getter.call())

				if type == Type.INT:
					spin_box.value_changed.connect(func(value: int) -> void:
						setter.call(value)
					)
				else:
					spin_box.value_changed.connect(setter)

				var line_edit := spin_box.get_line_edit()
				line_edit.add_theme_font_override(&"font", _font)
				line_edit.add_theme_font_size_override(&"font_size", _font_size)
				line_edit.add_theme_color_override(&"font_color", _font_color)
				line_edit.add_theme_constant_override(&"outline_size", _font_outline_size)
				line_edit.add_theme_color_override(&"font_outline_color", _font_outline_color)
				line_edit.add_theme_stylebox_override(&"normal", _cell_edit)
				line_edit.add_theme_stylebox_override(&"focus", _cell_edit_empty)

				self.add_child(spin_box)

				var rect := scrolled_rect(cell.rect)
				spin_box.set_position(rect.position)
				spin_box.set_size(rect.size)

				spin_box.set_meta(&"cell", cell)
				self.set_cell_editor(spin_box)

		Type.STRING, Type.STRING_NAME:
			return func(cell: Dictionary, setter: Callable, getter: Callable) -> void:
				var line_edit := LineEdit.new()
				line_edit.add_theme_font_override(&"font", _font)
				line_edit.add_theme_font_size_override(&"font_size", _font_size)
				line_edit.add_theme_color_override(&"font_color", _font_color)
				line_edit.add_theme_constant_override(&"outline_size", _font_outline_size)
				line_edit.add_theme_color_override(&"font_outline_color", _font_outline_color)
				line_edit.add_theme_stylebox_override(&"normal", _cell_edit)
				line_edit.add_theme_stylebox_override(&"focus", _cell_edit_empty)
				line_edit.set_text(getter.call())

				if type == Type.STRING_NAME:
					line_edit.text_changed.connect(func(text: StringName) -> void:
						setter.call(text)
					)
				else:
					line_edit.text_changed.connect(setter)

				self.add_child(line_edit)

				var rect := scrolled_rect(cell.rect)
				line_edit.set_position(rect.position)
				line_edit.set_size(rect.size)

				line_edit.set_meta(&"cell", cell)
				self.set_cell_editor(line_edit)

		Type.COLOR:
			return func(cell: Dictionary, setter: Callable, getter: Callable) -> void:
				var panel := PopupPanel.new()
				panel.add_theme_stylebox_override(&"panel", _cell_edit)
				panel.focus_exited.connect(panel.queue_free)

				var color_picker := ColorPicker.new()
				color_picker.set_edit_alpha(hint != Hint.COLOR_NO_ALPHA)
				color_picker.set_pick_color(getter.call())
				color_picker.set_presets_visible(false)
				color_picker.set_sampler_visible(false)
				color_picker.set_modes_visible(false)
				color_picker.color_changed.connect(setter)
				panel.add_child(color_picker)

				self.add_child(panel)

				var rect := scrolled_rect(cell.rect)
				panel.set_position(rect.position)
				panel.set_size(rect.size)

				panel.set_meta(&"cell", cell)
				self.set_cell_editor(panel)

				panel.popup()

	return Callable()

func default_comparator(type: Type, hint: Hint, hint_string: String) -> Callable:
	match type:
		Type.STRING, Type.STRING_NAME:
			return func(a: String, b: String) -> bool:
				return a < b
		Type.COLOR:
			return func(a: Color, b: Color) -> bool:
				return hash(a) < hash(b)

	return func(a: Variant, b: Variant) -> bool:
		return a < b


func add_column(
		title: String,
		type: Type,
		hint: Hint = Hint.NONE,
		hint_string: String = "",
		stringifier: Callable = stringifier_default(type, hint, hint_string),
		edit_handler: Callable = edit_handler_default(type, hint, hint_string),
		comparator: Callable = default_comparator(type, hint, hint_string),
	) -> int:

	var text_line := TextLine.new()
	text_line.set_horizontal_alignment(HORIZONTAL_ALIGNMENT_LEFT)
	text_line.set_horizontal_alignment(HORIZONTAL_ALIGNMENT_CENTER)

	var column: Dictionary[StringName, Variant] = {
		&"title": title,
		&"rect": Rect2i(),
		&"dirty": true,
		&"visible": true,
		&"text_line": text_line,
		&"type_hint": type_hint_create(
			type,
			hint,
			hint_string,
			stringifier,
			edit_handler,
		),
		&"draw_mode": DrawMode.NORMAL,
		&"comparator": comparator,
		&"sort_mode": SortMode.NONE,
	}

	if DEBUG_ENABLED:
		column[&"color"] = Color(randf(), randf(), randf())

	_columns.push_back(column)
	update_table(true)

	return _columns.size() - 1


func set_column_title(column_idx: int, title: String) -> void:
	if _columns[column_idx][&"title"] == title:
		return

	_columns[column_idx][&"title"] = title
	_columns[column_idx][&"dirty"] = true

	update_table(true)

func get_column_title(column_idx: int) -> String:
	return _columns[column_idx][&"title"]


func set_column_visible(column_idx: int, visible: bool) -> void:
	if _columns[column_idx][&"visible"] == visible:
		return

	_columns[column_idx][&"visible"] = visible
	queue_redraw()

func is_column_visible(column_idx: int) -> bool:
	return _columns[column_idx][&"visible"]


func set_column_type(column_idx: int, type: Type, hint: Hint = Hint.NONE, hint_string: String = "") -> void:
	var type_hint: Dictionary[StringName, Variant] = _columns[column_idx][&"type_hint"]
	if type_hint.type == type and type_hint.hint == hint and type_hint.hint_string == hint_string:
		return

	type_hint.type = type
	type_hint.hint = hint
	type_hint.hint_string = hint_string

func get_column_type(column_idx: int) -> Type:
	return _columns[column_idx][&"type_hint"][&"type"]

func get_column_hint(column_idx: int) -> Hint:
	return _columns[column_idx][&"type_hint"][&"hint"]

func get_column_hint_string(column_idx: int) -> String:
	return _columns[column_idx][&"type_hint"][&"hint_string"]

## Sets the [Callable] that will be used to sort the column. If set invalid [Callable], sorting for the column will be disabled.
func set_column_comparator(column_idx: int, comparator: Callable) -> void:
	_columns[column_idx][&"comparator"] = comparator

func get_column_comparator(column_idx: int) -> Callable:
	return _columns[column_idx][&"comparator"]


func get_column_sort_mode(column_idx: int) -> SortMode:
	return _columns[column_idx][&"sort_mode"]


func sort_by_column(column_idx: int, sort_mode: SortMode) -> void:
	if sort_mode == SortMode.NONE:
		return

	var column: Dictionary = _columns[column_idx]

	var comparator: Callable = column.comparator
	if not comparator.is_valid():
		return

	for c: Dictionary in _columns:
		c.sort_mode = SortMode.NONE

	column.sort_mode = sort_mode

	if sort_mode == SortMode.ASCENDING:
		_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return comparator.call(a.cells[column_idx].value, b.cells[column_idx].value)
		)
	else:
		_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return comparator.call(b.cells[column_idx].value, a.cells[column_idx].value)
		)

	update_table(true)




func add_row() -> int:
	var cells: Array[Dictionary] = []
	if cells.resize(_columns.size()):
		return INVALID_ROW

	for i: int in _columns.size():
		var text_line := TextLine.new()
		text_line.set_horizontal_alignment(HORIZONTAL_ALIGNMENT_LEFT)

		var cell: Dictionary[StringName, Variant] = {
			&"rect": Rect2i(),
			&"value": null,
			&"text_line": text_line,
			&"type_hint": _columns[i][&"type_hint"],
		}

		if DEBUG_ENABLED:
			cell[&"color"] = Color(randf(), randf(), randf())

		cells[i] = cell

	var row: Dictionary[StringName, Variant] = {
		&"rect": Rect2i(),
		&"cells": cells,
		&"dirty": true,
		&"visible": true,
		&"selected": false,
	}

	if DEBUG_ENABLED:
		row[&"color"] = Color(randf(), randf(), randf())

	_rows.push_back(row)

	return _rows.size() - 1

func remove_row(row_idx: int) -> void:
	_rows.remove_at(row_idx)
	mark_dirty()


func select_single_row(row_idx: int) -> void:
	for i: int in _rows.size():
		_rows[i][&"selected"] = i == row_idx

	row_selected.emit(row_idx)
	queue_redraw()

func select_row(row_idx: int) -> void:
	match get_select_mode():
		SelectMode.SINGLE_ROW:
			return select_single_row(row_idx)
		SelectMode.MULTI_ROW:
			_rows[row_idx][&"selected"] = true
		_:
			return

	row_selected.emit(row_idx)
	queue_redraw()

func deselect_row(row_idx: int) -> void:
	match get_select_mode():
		SelectMode.SINGLE_ROW, SelectMode.MULTI_ROW:
			_rows[row_idx][&"selected"] = false
		_:
			return

	queue_redraw()

func is_row_selected(row_idx: int) -> bool:
	return _rows[row_idx][&"selected"]

func toggle_row_selected(row_idx: int) -> void:
	if is_row_selected(row_idx):
		deselect_row(row_idx)
	else:
		select_row(row_idx)


func get_selected_rows() -> PackedInt32Array:
	var selected := PackedInt32Array()

	for i: int in _rows.size():
		if _rows[i][&"selected"]:
			selected.push_back(i)

	return selected


func select_all_rows() -> void:
	if is_select_mode_multi_row():
		for row: Dictionary in _rows:
			row.selected = row.visible
	else:
		return deselect_all_rows()

	queue_redraw()

func deselect_all_rows() -> void:
	for row: Dictionary in _rows:
		row.selected = false

	queue_redraw()





func set_cell_value_no_update(row_idx: int, column_idx: int, value: Variant) -> bool:
	if is_same(_rows[row_idx][&"cells"][column_idx][&"value"], value):
		return false

	_rows[row_idx][&"dirty"] = true
	_rows[row_idx][&"cells"][column_idx][&"value"] = value

	return true

func set_cell_value(row_idx: int, column_idx: int, value: Variant) -> void:
	if set_cell_value_no_update(row_idx, column_idx, value):
		mark_dirty()

func get_cell_value(row_idx: int, column_idx: int) -> Variant:
	return _rows[row_idx][&"cells"][column_idx][&"value"]


func set_cell_custom_type(
		row_idx: int,
		column_idx: int,
		type: Type,
		hint: Hint = Hint.NONE,
		hint_string: String = "",
		stringifier: Callable = stringifier_default(type, hint, hint_string),
		edit_handler: Callable = edit_handler_default(type, hint, hint_string),
	) -> void:

	_rows[row_idx][&"cells"][column_idx][&"type_hint"] = type_hint_create(
		type,
		hint,
		hint_string,
		stringifier,
		edit_handler,
	)

func get_cell_type(row_idx: int, column_idx: int) -> Type:
	return _rows[row_idx][&"cells"][column_idx][&"type_hint"][&"type"]

func get_cell_hint(row_idx: int, column_idx: int) -> Hint:
	return _rows[row_idx][&"cells"][column_idx][&"type_hint"][&"hint"]

func get_cell_hint_string(row_idx: int, column_idx: int) -> String:
	return _rows[row_idx][&"cells"][column_idx][&"type_hint"][&"hint_string"]

func get_cell_edit_handler(row_idx: int, column_idx: int) -> Callable:
	return _rows[row_idx][&"cells"][column_idx][&"type_hint"][&"edit_handler"]


func stringify_cell(row_idx: int, column_idx: int) -> String:
	var cell: Dictionary = _rows[row_idx][&"cells"][column_idx]

	var stringifier: Callable = cell.type_hint.stringifier
	if stringifier.is_valid():
		return stringifier.call(cell.value)

	return str(cell.value)


func filter_rows_by_callable(column_idx: int, callable: Callable) -> void:
	if not callable.is_valid():
		return

	for row: Dictionary in _rows:
		if callable.call(row.cells[column_idx][&"value"]):
			row.visible = true
		else:
			row.visible = false
			row.selected = false

	update_table(true)


func find_column_at_position(point: Vector2) -> int:
	for i: int in _columns.size():
		if Rect2(_columns[i][&"rect"]).has_point(point):
			return i

	return INVALID_COLUMN

func find_row_at_position(point: Vector2) -> int:
	for i: int in _rows.size():
		var row: Dictionary = _rows[i]
		if not row.visible:
			continue

		if Rect2(row.rect).has_point(point):
			return i

	return INVALID_ROW

func find_cell_at_position(row_idx: int, point: Vector2) -> int:
	var cells: Array[Dictionary] = _rows[row_idx][&"cells"]
	for i: int in cells.size():
		if Rect2(cells[i][&"rect"]).has_point(point):
			return i

	return INVALID_CELL





func scrolled_position(point: Vector2) -> Vector2:
	return Vector2(_h_scroll.get_value(), _v_scroll.get_value()) + point

func scrolled_position_horizontal(point: Vector2) -> Vector2:
	return Vector2(_h_scroll.get_value(), 0.0) + point


func scrolled_rect(rect: Rect2, horizontal_only := false) -> Rect2:
	return Rect2(rect.position - Vector2(_h_scroll.get_value(), _v_scroll.get_value()), rect.size)

func scrolled_rect_horizontal(rect: Rect2) -> Rect2:
	return Rect2(rect.position - Vector2(_h_scroll.get_value(), 0.0), rect.size)




func _vertical_scroll(pages: float) -> bool:
	var prev_value: float = _v_scroll.get_value()
	_v_scroll.set_value(prev_value + _v_scroll.get_page() * pages)

	return _v_scroll.get_value() != prev_value

func _horizontal_scroll(pages: float) -> bool:
	var prev_value: float = _h_scroll.get_value()
	_h_scroll.set_value(prev_value + _h_scroll.get_page() * pages)

	return _h_scroll.get_value() != prev_value



func _on_column_clicked(column_idx: int) -> void:
	if get_column_sort_mode(column_idx) == SortMode.ASCENDING:
		sort_by_column(column_idx, SortMode.DESCENDING)
	else:
		sort_by_column(column_idx, SortMode.ASCENDING)


func _on_cell_double_click(row_idx: int, column_idx: int) -> void:
	var row: Dictionary = _rows[row_idx]
	var cell: Dictionary = row[&"cells"][column_idx]

	var edit_handler: Callable = cell.type_hint.edit_handler
	if not edit_handler.is_valid():
		return

	var setter: Callable = func set_value(value: Variant) -> void:
		if is_same(cell.value, value):
			return

		cell.value = value
		row.dirty = true

		mark_dirty()
	var getter: Callable = func get_value() -> Variant:
		return cell.value

	edit_handler.call(cell, setter, getter)


func _on_scroll_value_changed(_value) -> void:
	queue_redraw()




static func get_text_position(rect: Rect2, text_size: Vector2, alignment: HorizontalAlignment) -> Vector2:
	if alignment == HORIZONTAL_ALIGNMENT_CENTER:
		return rect.get_center() - text_size * 0.5
	elif alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		return Vector2(rect.position.x + rect.size.x - text_size.x, rect.position.y + rect.size.y * 0.5 - text_size.y * 0.5)

	return Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 - text_size.y * 0.5)

static func draw_text_line(ci: RID, text_line: TextLine, font_color: Color, outline_size: int, outline_color: Color, rect: Rect2) -> void:
	var text_position := get_text_position(rect, text_line.get_size(), text_line.get_horizontal_alignment())

	if outline_size and outline_color.a:
		text_line.draw_outline(ci, text_position, outline_size, outline_color)

	text_line.draw(ci, text_position, font_color)
