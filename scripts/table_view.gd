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

signal column_created(column_idx: int, type: Type, hint: Hint, hint_string: String)
signal column_removed(column_idx: int)
signal column_visibility_changed(column_idx: int, visibility: bool)

signal row_created(row_idx: int)
signal row_removed(row_idx: int)

signal row_selection_changed
signal single_row_selected(row_idx: int)
signal multiple_rows_selected(selected_rows: PackedInt32Array)

signal cell_value_changed(row_idx: int, column_idx: int, value: Variant)


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
	INTERACTIVE,
	FIXED,
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


const NUMBERS_AFTER_DOT = 3
const COLUMN_MINIMUM_WIDTH = 50.0

const DEFAULT_NUM_MIN = -2147483648
const DEFAULT_NUM_MAX =  2147483647

const INVALID_COLUMN: int = -1
const INVALID_ROW: int = -1
const INVALID_CELL: int = -1

# TODO: Move to theme in the future.
const H_SEPARATION = 4


@export var column_resize_mode: ColumnResizeMode = ColumnResizeMode.STRETCH:
	set = set_column_resize_mode,
	get = get_column_resize_mode
@export var select_mode: SelectMode = SelectMode.SINGLE_ROW:
	set = set_select_mode,
	get = get_select_mode
@export var editable: bool = true:
	set = set_editable,
	get = is_editable


var _dirty: bool = true

var _header: Rect2i = Rect2i()

var _v_scroll: VScrollBar = null
var _h_scroll: HScrollBar = null

var _columns: Array[Dictionary] = []
var _rows: Array[Dictionary] = []

var _canvas: RID = RID()

var _cell_editor: Node = null
var _column_context_menu: PopupMenu = null

var _resized_column: int = INVALID_COLUMN
var _resized_column_width: int = 0

var _drag_from: Vector2 = Vector2.ZERO
var _drag_to: Vector2 = Vector2.ZERO

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
	self.column_rmb_clicked.connect(_on_column_rmb_clicked)

	self.cell_double_clicked.connect(_on_cell_double_click)

	self.row_rmb_clicked.connect(_on_row_rmb_clicked)
	self.row_selection_changed.connect(_on_row_selection_changed)

@warning_ignore("unsafe_call_argument")
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			update_table()

		NOTIFICATION_DRAW when DEBUG_ENABLED:
			if is_dirty():
				update_table()

			update_cell_editor_position_and_size()

			draw_rect(Rect2(Vector2.ZERO, get_size()), Color(Color.BLACK, 0.5))
			if has_focus():
				draw_rect(Rect2(Vector2.ZERO, get_size()), Color(Color.RED, 0.5), false)

			draw_rect(_header, Color(Color.RED, 0.25))
			draw_rect(_header, Color(Color.RED, 0.50), false)

			var drawable_rect: Rect2 = get_drawable_rect()
			draw_rect(drawable_rect, Color(Color.GREEN, 0.05))
			draw_rect(drawable_rect, Color(Color.GREEN, 0.10), false)

			#region draw rows
			for row: Dictionary in _rows:
				if not row.visible:
					continue

				var rect := scrolled_rect(row.rect)
				if not drawable_rect.intersects(rect):
					continue

				var color: Color = row.color
				if row.selected:
					color = color.lerp(Color.WHITE, 0.5)
				if rect.has_point(get_local_mouse_position()):
					color = color.lerp(Color.WHITE, 0.5)

				draw_rect(rect, Color(color, 0.25))
				draw_rect(rect, Color(color, 0.50), false)

				for cell: Dictionary in row.cells:
					rect = scrolled_rect(cell.rect)
					if not drawable_rect.intersects(rect):
						continue

					rect = margin_rect(rect)

					color = cell.color
					if rect.has_point(get_local_mouse_position()):
						color = color.lerp(Color.WHITE, 0.5)

					draw_rect(rect, Color(color, 0.25))
					draw_rect(rect, Color(color, 0.50), false)

					match cell.type_hint.type:
						Type.BOOL:
							var texture: Texture2D = _checked if cell.value else _unchecked
							texture.draw(get_canvas_item(), get_texture_position_in_rect(texture.get_size(), rect, HORIZONTAL_ALIGNMENT_LEFT))
						Type.COLOR:
							draw_rect(rect, cell.value)
						_:
							draw_text_line(get_canvas_item(), cell.text_line, Color.WHITE, 2, Color.BLACK, rect)
			#endregion

			#region draw columns
			for column: Dictionary in _columns:
				if not column.visible:
					continue

				var rect := scrolled_rect_horizontal(column.rect)
				if not drawable_rect.intersects(rect):
					continue

				var color: Color = column.color
				if column.draw_mode == DrawMode.HOVER:
					color = color.lerp(Color.WHITE, 0.5)

				rect = margin_rect(rect)
				draw_rect(rect, Color(color, 0.5))
				draw_rect(rect, Color(color, 0.75), false)

				var icon := get_sort_mode_icon(column.sort_mode)
				if is_instance_valid(icon):
					icon.draw(get_canvas_item(), get_texture_position_in_rect(icon.get_size(), rect, HORIZONTAL_ALIGNMENT_RIGHT))

				draw_text_line(get_canvas_item(), column.text_line, Color.WHITE, 2, Color.BLACK, margin_rect(rect))
			#endregion

			#region draw grip
			for column: Dictionary in _columns:
				if not column.visible:
					continue

				var rect := scrolled_rect_horizontal(column.rect)
				if not drawable_rect.intersects(rect):
					continue

				rect = grip_rect(rect)

				var color: Color = Color.BLUE
				if rect.has_point(get_local_mouse_position()):
					color = color.lerp(Color.WHITE, 0.5)

				draw_rect(rect, Color(color, 0.5))
				draw_rect(rect, Color(color, 0.75), false)
			#endregion

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
				elif draw_begun:
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
							texture.draw(_canvas, get_texture_position_in_rect(texture.get_size(), margin_rect(rect), HORIZONTAL_ALIGNMENT_LEFT))
						Type.COLOR:
							var color: Color = Color.BLACK if cell.value == null else cell.value
							RenderingServer.canvas_item_add_rect(_canvas, margin_rect(rect), color)
						_:
							draw_text_line(_canvas, cell.text_line, _font_color, _font_outline_size, _font_outline_color, margin_rect(rect))

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

				rect = margin_rect(rect)

				var icon := get_sort_mode_icon(column.sort_mode)
				if is_instance_valid(icon):
					icon.draw(_canvas, get_texture_position_in_rect(icon.get_size(), rect, HORIZONTAL_ALIGNMENT_RIGHT))

				draw_text_line(_canvas, column.text_line, _font_color, _font_outline_size, _font_outline_color, rect)

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


func _handle_column_event(event: InputEventMouseButton, position: Vector2) -> void:
	position = scrolled_position_horizontal(position)

	var column_idx := find_column_at_position(position)
	if column_idx == INVALID_COLUMN:
		return

	if event.get_button_index() == MOUSE_BUTTON_LEFT:
		if event.is_double_click():
			column_double_clicked.emit(column_idx)
		elif get_column_grip_rect(column_idx).has_point(position):
			_columns[column_idx][&"draw_mode"] = DrawMode.HOVER

			_resized_column = column_idx
			_resized_column_width = get_column_width(column_idx)

			_drag_from = position
		else:
			column_clicked.emit(column_idx)
	else:
		column_rmb_clicked.emit(column_idx)

func _handle_left_mouse_row_event(event: InputEventMouseButton, row_idx: int) -> void:
	if event.is_ctrl_pressed():
		toggle_row_selected(row_idx)
	elif event.is_shift_pressed():
		select_row(row_idx)
	elif event.is_double_click():
		row_double_clicked.emit(row_idx)
	else:
		select_single_row(row_idx)

func _handle_cell_event(event: InputEventMouseButton, row_idx: int, position: Vector2) -> void:
	var cell_idx := find_cell_at_position(row_idx, scrolled_position(position))
	if cell_idx == INVALID_CELL:
		return

	if event.get_button_index() == MOUSE_BUTTON_LEFT:
		if event.is_double_click():
			cell_double_clicked.emit(row_idx, cell_idx)
		else:
			cell_clicked.emit(row_idx, cell_idx)
	else:
		cell_rmb_clicked.emit(row_idx, cell_idx)

func _handle_row_event(event: InputEventMouseButton, position: Vector2) -> void:
	var row_idx := find_row_at_position(scrolled_position(position))
	if row_idx == INVALID_ROW:
		return

	if event.get_button_index() == MOUSE_BUTTON_LEFT:
		_handle_left_mouse_row_event(event, row_idx)
	else:
		row_rmb_clicked.emit(row_idx)

	_handle_cell_event(event, row_idx, position)

@warning_ignore("unsafe_method_access", "unsafe_call_argument", "return_value_discarded")
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var position: Vector2 = event.get_position()
		_drag_to = scrolled_position(position)

		if _resized_column == INVALID_COLUMN:
			for column in _columns:
				if not column.visible:
					continue

				var column_rect = scrolled_rect_horizontal(column.rect).grow_side(SIDE_LEFT, -2)
				column.draw_mode = DrawMode.HOVER if column_rect.has_point(position) else DrawMode.NORMAL

		# Handle interactive column resizing mode
		if column_resize_mode == ColumnResizeMode.INTERACTIVE:
			position = scrolled_position_horizontal(position)

			var is_resizing: bool = _resized_column != INVALID_COLUMN or find_resizable_column(position) != INVALID_COLUMN
			set_default_cursor_shape(CURSOR_HSIZE if is_resizing else CURSOR_ARROW)

			if _resized_column != INVALID_COLUMN:
				var new_width: int = _resized_column_width - (_drag_from.x - _drag_to.x)
				set_column_custom_width(_resized_column, new_width)

		queue_redraw()

	elif event is InputEventMouseButton:
		const SCROLL_FACTOR = 0.25

		match event.get_button_index():
			MOUSE_BUTTON_LEFT when event.is_released():
				_resized_column = INVALID_COLUMN
				_drag_from = Vector2.ZERO

			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				if is_instance_valid(_cell_editor):
					_cell_editor.queue_free()

				if is_select_mode_disabled():
					return

				var position: Vector2 = event.get_position()
				if header_has_point(position):
					_handle_column_event(event, position)
				else:
					_handle_row_event(event, position)

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
			var tooltip := get_column_tooltip(column_idx)
			if tooltip.is_empty():
				return get_column_title(column_idx)

			return tooltip
	else:
		at_position = scrolled_position(at_position)

		var row_idx := find_row_at_position(at_position)
		if row_idx != INVALID_ROW:
			var cell_idx := find_cell_at_position(row_idx, at_position)
			if cell_idx != INVALID_CELL:
				return stringify_cell(row_idx, cell_idx)

	return get_tooltip_text()


func margin_width(width: float) -> float:
	return width - _inner_margin_left - _inner_margin_right

## Returns [Rect2] with margin offsets.
func margin_rect(rect: Rect2) -> Rect2:
	return rect.grow_individual(-_inner_margin_left, -_inner_margin_top, -_inner_margin_right, -_inner_margin_bottom)


func mark_dirty() -> void:
	if _dirty:
		return

	_dirty = true
	queue_redraw()

func is_dirty() -> bool:
	return _dirty


func set_column_resize_mode(n_resize_mode: ColumnResizeMode) -> void:
	if column_resize_mode == n_resize_mode:
		return

	column_resize_mode = n_resize_mode
	mark_dirty()

func get_column_resize_mode() -> ColumnResizeMode:
	return column_resize_mode


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


func set_editable(value: bool) -> void:
	if value == false and is_instance_valid(_cell_editor):
		_cell_editor.queue_free()

	editable = value

func is_editable() -> bool:
	return editable


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


func update_column_text_line(text_line: TextLine, icon: Texture2D, rect: Rect2) -> void:
	rect = margin_rect(rect)

	if not is_instance_valid(icon):
		text_line.set_width(rect.size.x)
		return

	var text_width: float = text_line.get_line_width()
	var icon_width: float = icon.get_width()

	var offset_x: float = rect.size.x - text_width - icon_width * 2.0

	if offset_x < 0.0:
		text_width = text_width + offset_x + icon_width
	else:
		text_width = rect.size.x

	text_line.set_width(text_width)

@warning_ignore("unsafe_call_argument", "return_value_discarded", "narrowing_conversion")
func update_table() -> void:
	if _columns.is_empty():
		return

	var cell_height: int = _font.get_height(_font_size) + _inner_margin_top + _inner_margin_bottom
	var drawable_rect := get_drawable_rect()

	match column_resize_mode:
		ColumnResizeMode.STRETCH:
			var total_width: float = 0.0

			for column: Dictionary in _columns:
				if not column.visible:
					continue

				total_width += column.minimum_width

			var ofs_x: int = drawable_rect.position.x
			var ofs_y: int = drawable_rect.position.y

			_header.position = Vector2i(ofs_x, ofs_y)

			for column: Dictionary in _columns:
				if not column.visible:
					continue

				var ratio: float = column.minimum_width / total_width
				var width: float = maxf(ratio * drawable_rect.size.x, column.minimum_width)

				var rect := Rect2i(ofs_x, ofs_y, width, cell_height)
				update_column_text_line(column.text_line, get_sort_mode_icon(column.sort_mode), rect)

				column.rect = rect
				_header.end = rect.end

				ofs_x = rect.end.x

		ColumnResizeMode.INTERACTIVE, ColumnResizeMode.FIXED:
			var ofs_x: int = drawable_rect.position.x
			var ofs_y: int = drawable_rect.position.y

			_header.position = Vector2i(ofs_x, ofs_y)

			for column: Dictionary in _columns:
				if not column.visible:
					continue

				var rect := Rect2i(ofs_x, ofs_y, maxi(column.custom_width, column.minimum_width), cell_height)
				update_column_text_line(column.text_line, get_sort_mode_icon(column.sort_mode), rect)

				column.rect = rect
				_header.end = rect.end

				ofs_x = rect.end.x

	var content_rect: Rect2i = _header

	if _rows:
		var row_ofs: int = drawable_rect.position.y + _header.size.y

		var row_height: int = cell_height
		var row_width: int = _header.size.x

		for row: Dictionary in _rows:
			if not row.visible:
				continue

			var cells: Array[Dictionary] = row.cells
			var cell_ofs: int = drawable_rect.position.x

			for i: int in _columns.size():
				if not _columns[i][&"visible"]:
					continue

				var cell: Dictionary = cells[i]
				var cell_width: int = _columns[i].rect.size.x

				var text_line: TextLine = cell.text_line
				text_line.set_width(margin_width(cell_width))

				cell.rect = Rect2i(cell_ofs, row_ofs, cell_width, row_height)
				cell_ofs += cell_width

			row.rect = Rect2i(drawable_rect.position.x, row_ofs, row_width, row_height)
			content_rect.end = row.rect.end

			row_ofs += row_height

#region update scroll bars
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
#endregion

	_dirty = false
	queue_redraw()


func update_cell_editor_position_and_size() -> void:
	if not is_instance_valid(_cell_editor) or not _cell_editor.has_meta(&"cell"):
		return

	var cell: Dictionary = _cell_editor.get_meta(&"cell")
	var rect: Rect2 = scrolled_rect(cell.rect)

	if _cell_editor is Control:
		_cell_editor.set_position(rect.position)
		_cell_editor.set_size(rect.size)


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


static func create_type_hint(
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

				popup.set_meta(&"cell", cell)
				self.set_cell_editor(popup)

				popup.popup(get_screen_transform() * scrolled_rect(cell.rect))

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

				popup.set_meta(&"cell", cell)
				self.set_cell_editor(popup)

				popup.popup(get_screen_transform() * scrolled_rect(cell.rect))

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
				line_edit.grab_focus()

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
				line_edit.grab_focus()

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

				panel.set_meta(&"cell", cell)
				self.set_cell_editor(panel)

				panel.popup(get_screen_transform() * scrolled_rect(cell.rect))

	return Callable()

static func default_comparator(type: Type, hint: Hint, hint_string: String) -> Callable:
	match type:
		Type.STRING, Type.STRING_NAME:
			return func(a: String, b: String) -> bool:
				return a < b

		Type.COLOR when hint == Hint.COLOR_NO_ALPHA:
			return func(a: Color, b: Color) -> bool:
				if a.r != b.r:
					return a.r < b.r
				elif a.g != b.g:
					return a.g < b.g
				else:
					return a.b < b.b

		Type.COLOR:
			return func(a: Color, b: Color) -> bool:
				if a.r != b.r:
					return a.r < b.r
				elif a.g != b.g:
					return a.g < b.g
				elif a.b != b.b:
					return a.b < b.b
				else:
					return a.a < b.a

	return func(a: Variant, b: Variant) -> bool:
		return a < b


static func create_column(
		title: String,
		type: Type,
		hint: Hint,
		hint_string: String,
		stringifier: Callable,
		edit_handler: Callable,
		comparator: Callable,
	) -> Dictionary[StringName, Variant]:

	var text_line := TextLine.new()
	text_line.set_horizontal_alignment(HORIZONTAL_ALIGNMENT_CENTER)

	var column: Dictionary[StringName, Variant] = {
		&"rect": Rect2i(),
		&"title": title,
		&"tooltip": "",
		&"visible": true,
		&"text_line": text_line,
		&"type_hint": create_type_hint(
			type,
			hint,
			hint_string,
			stringifier,
			edit_handler,
		),
		&"draw_mode": DrawMode.NORMAL,
		&"sort_mode": SortMode.NONE,
		&"comparator": comparator,
		&"custom_width": 0.0,
		&"minimum_width": COLUMN_MINIMUM_WIDTH,
	}

	if DEBUG_ENABLED:
		column[&"color"] = Color(randf(), randf(), randf())

	return column


func add_column(
		title: String,
		type: Type,
		hint: Hint = Hint.NONE,
		hint_string: String = "",
		stringifier: Callable = stringifier_default(type, hint, hint_string),
		edit_handler: Callable = edit_handler_default(type, hint, hint_string),
		comparator: Callable = default_comparator(type, hint, hint_string),
	) -> int:

	var column: Dictionary[StringName, Variant] = create_column(
		title,
		type,
		hint,
		hint_string,
		stringifier,
		edit_handler,
		comparator
	)

	var text_line: TextLine = column.text_line
	text_line.add_string(title, _font, _font_size)

	_columns.push_back(column)

	var type_hint: Dictionary = column.type_hint
	for row: Dictionary in _rows:
		row.cells.push_back(create_cell(type_hint))

	column_created.emit(_columns.size() - 1, type, hint, hint_string)
	mark_dirty()

	return _columns.size() - 1

func remove_column(column_idx: int) -> void:
	_columns.remove_at(column_idx)

	for row: Dictionary in _rows:
		row.cells.remove_at(column_idx)

	column_removed.emit(column_idx)
	mark_dirty()


func set_column_count(new_size: int) -> void:
	var old_size: int = _columns.size()
	if old_size == new_size:
		return

	_columns.resize(new_size)
	for column: Dictionary in _columns:
		column.visible = true
		column.sort_mode = SortMode.NONE

	for row: Dictionary in _rows:
		row.cells.resize(new_size)

	while old_size < new_size:
		var column: Dictionary = create_column(
			"Column %d" % old_size,
			Type.BOOL,
			Hint.NONE,
			"",
			stringifier_default(Type.BOOL, Hint.NONE, ""),
			edit_handler_default(Type.BOOL, Hint.NONE, ""),
			default_comparator(Type.BOOL, Hint.NONE, ""),
		)
		_columns[old_size] = column

		var type_hint: Dictionary = column.type_hint
		for row: Dictionary in _rows:
			row.cells[old_size] = create_cell(type_hint)

		old_size += 1

	mark_dirty()

func get_column_count() -> int:
	return _columns.size()


func set_column_title(column_idx: int, title: String) -> void:
	var column: Dictionary = _columns[column_idx]
	if column.title == title:
		return

	var text_line: TextLine = column.text_line
	text_line.clear()
	text_line.add_string(title, _font, _font_size)

	column.title = title

	queue_redraw()

func get_column_title(column_idx: int) -> String:
	return _columns[column_idx][&"title"]


func set_column_tooltip(column_idx: int, tooltip: String) -> void:
	_columns[column_idx][&"tooltip"] = tooltip

func get_column_tooltip(column_idx: int) -> String:
	return _columns[column_idx][&"tooltip"]


## Returns [param true] if the column can be hidden.
func can_hide_column(column_idx: int) -> bool:
	if _columns.size() <= 1:
		return false

	var visible_columns: int = 0
	for i: int in _columns.size():
		if i != column_idx and _columns[i][&"visible"]:
			visible_columns += 1

	return visible_columns > 0

## Sets column visibility. Returns [param true] if updated successfully; otherwise, [param false].
func set_column_visible(column_idx: int, visible: bool) -> bool:
	if _columns[column_idx][&"visible"] == visible:
		return false

	if not visible and not can_hide_column(column_idx):
		return false

	_columns[column_idx][&"visible"] = visible
	column_visibility_changed.emit(column_idx, visible)

	return true

func is_column_visible(column_idx: int) -> bool:
	return _columns[column_idx][&"visible"]

## Sets the custom width for a column.
func set_column_custom_width(column_idx: int, custom_width: int) -> void:
	if _columns[column_idx][&"custom_width"] == maxf(custom_width, 0.0):
		return

	_columns[column_idx][&"custom_width"] = maxf(custom_width, 0.0)
	mark_dirty()
## Returns the custom width of a column.
func get_column_custom_width(column_idx: int) -> int:
	return _columns[column_idx][&"custom_width"]

## Sets the minimum width for a column.
func set_column_minimum_width(column_idx: int, minimum_width: int) -> void:
	if _columns[column_idx][&"minimum_width"] == maxf(minimum_width, COLUMN_MINIMUM_WIDTH):
		return

	_columns[column_idx][&"minimum_width"] = maxf(minimum_width, COLUMN_MINIMUM_WIDTH)
	mark_dirty()
## Returns the minimum width of a column.
func get_column_minimum_width(column_idx: int) -> int:
	return _columns[column_idx][&"minimum_width"]

## Returns the largest value between [param custom_width] and [param minimum_width].
func get_column_width(column_idx: int) -> int:
	return maxi(_columns[column_idx][&"custom_width"], _columns[column_idx][&"minimum_width"])


func set_column_type(
		column_idx: int,
		type: Type,
		hint: Hint = Hint.NONE,
		hint_string: String = "",
		stringifier: Callable = stringifier_default(type, hint, hint_string),
		edit_handler: Callable = edit_handler_default(type, hint, hint_string),
	) -> void:

	var type_hint: Dictionary[StringName, Variant] = _columns[column_idx][&"type_hint"]
	if type_hint.type == type and type_hint.hint == hint and type_hint.hint_string == hint_string:
		return

	type_hint.type = type
	type_hint.hint = hint
	type_hint.hint_string = hint_string
	type_hint.stringifier = stringifier
	type_hint.edit_handler = edit_handler

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


func set_column_metadata(column_idx: int, metadata: Variant) -> void:
	if metadata == null:
		_columns[column_idx].erase(&"metadata")
	else:
		_columns[column_idx][&"metadata"] = metadata

func get_column_metadata(column_idx: int, default: Variant = null) -> Variant:
	return _columns[column_idx].get(&"metadata", default)

## Returns the column header's rectangle.
func get_column_rect(column_idx: int) -> Rect2:
	return _columns[column_idx][&"rect"]

func get_column_grip_rect(column_idx: int) -> Rect2:
	return grip_rect(_columns[column_idx][&"rect"])


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

	mark_dirty()


## Returns an existing [PopupMenu] or creates a new one to control
## table column visibility, shown when right-clicking a column.
## The object is created once and not automatically created with the [TableView].
func get_or_create_column_context_menu() -> PopupMenu:
	if not is_instance_valid(_column_context_menu):
		_column_context_menu = PopupMenu.new()
		_column_context_menu.index_pressed.connect(func on_index_pressed(column_idx: int) -> void:
			var column: Dictionary = _columns[column_idx]

			column.visible = not column.visible
			_column_context_menu.set_item_checked(column_idx, column.visible)

			mark_dirty()
		)
		self.add_child(_column_context_menu)

	return _column_context_menu




static func create_cell(type_hint: Dictionary) -> Dictionary[StringName, Variant]:
	var text_line := TextLine.new()
	text_line.set_horizontal_alignment(HORIZONTAL_ALIGNMENT_LEFT)

	var cell: Dictionary[StringName, Variant] = {
		&"rect": Rect2i(),
		&"value": null,
		&"text_line": text_line,
		&"type_hint": type_hint,
	}

	if DEBUG_ENABLED:
		cell[&"color"] = Color(randf(), randf(), randf())

	return cell


static func create_row(columns: Array[Dictionary]) -> Dictionary[StringName, Variant]:
	var cells: Array[Dictionary] = []
	cells.resize(columns.size())

	for i: int in cells.size():
		cells[i] = create_cell(columns[i][&"type_hint"])

	var row: Dictionary[StringName, Variant] = {
		&"rect": Rect2i(),
		&"cells": cells,
		&"visible": true,
		&"selected": false,
	}

	if DEBUG_ENABLED:
		row[&"color"] = Color(randf(), randf(), randf())

	return row


func add_row() -> int:
	_rows.push_back(create_row(_columns))
	row_created.emit(_rows.size() - 1)

	return _rows.size() - 1

func remove_row(row_idx: int) -> void:
	_rows.remove_at(row_idx)
	row_removed.emit(row_idx)

	mark_dirty()


func set_row_count(new_size: int) -> void:
	var old_size: int = _rows.size()
	if old_size == new_size:
		return

	_rows.resize(new_size)
	for row: Dictionary in _rows:
		row.visible = true
		row.selected = false

	while old_size < new_size:
		_rows[old_size] = create_row(_columns)
		old_size += 1

	mark_dirty()

func get_row_count() -> int:
	return _rows.size()


func set_row_visible(row_idx: int, visible: bool) -> void:
	var row: Dictionary = _rows[row_idx]
	if row.visible == visible:
		return

	row.visible = visible
	mark_dirty()

func is_row_visible(row_idx: int) -> bool:
	return _rows[row_idx][&"visible"]

## Returns the count of visible rows, unlike [method get_visible_rows], which returns an array.
func get_visible_rows_count() -> int:
	var visible_rows: int = 0

	for row: Dictionary in _rows:
		if row.visible:
			visible_rows += 1

	return visible_rows

## Returns an array of visible row indices.
func get_visible_rows() -> PackedInt32Array:
	var visible_rows := PackedInt32Array()

	for i: int in _rows.size():
		if _rows[i][&"visible"]:
			visible_rows.push_back(i)

	return visible_rows


func set_row_metadata(row_idx: int, metadata: Variant) -> void:
	if metadata == null:
		_rows[row_idx].erase(&"metadata")
	else:
		_rows[row_idx][&"metadata"] = metadata

func get_row_metadata(row_idx: int, default: Variant = null) -> Variant:
	return _rows[row_idx].get(&"metadata", default)


func select_single_row(row_idx: int) -> void:
	for i: int in _rows.size():
		_rows[i][&"selected"] = i == row_idx

	row_selection_changed.emit()
	queue_redraw()

func select_row(row_idx: int) -> void:
	match get_select_mode():
		SelectMode.SINGLE_ROW:
			return select_single_row(row_idx)
		SelectMode.MULTI_ROW:
			_rows[row_idx][&"selected"] = true
		_:
			return

	row_selection_changed.emit()
	queue_redraw()

func deselect_row(row_idx: int) -> void:
	match get_select_mode():
		SelectMode.SINGLE_ROW, SelectMode.MULTI_ROW:
			_rows[row_idx][&"selected"] = false
		_:
			return

	row_selection_changed.emit()
	queue_redraw()

func is_row_selected(row_idx: int) -> bool:
	return _rows[row_idx][&"selected"]

func toggle_row_selected(row_idx: int) -> void:
	if is_row_selected(row_idx):
		deselect_row(row_idx)
	else:
		select_row(row_idx)

## Returns the count of selected rows, unlike [method get_selected_rows], which returns an array.
func get_selected_rows_count() -> int:
	if is_select_mode_disabled():
		return 0

	elif is_select_mode_single_row():
		for row: Dictionary in _rows:
			if row.selected:
				return 1

		return 0

	var selected_rows: int = 0

	for row: Dictionary in _rows:
		if row.selected:
			selected_rows += 1

	return selected_rows

## Returns an array of selected row indices.
func get_selected_rows() -> PackedInt32Array:
	match get_select_mode():
		SelectMode.SINGLE_ROW:
			for i: int in _rows.size():
				if _rows[i][&"selected"]:
					return [i]

		SelectMode.MULTI_ROW:
			var selected := PackedInt32Array()

			for i: int in _rows.size():
				if _rows[i][&"selected"]:
					selected.push_back(i)

			return selected

	return PackedInt32Array()


func select_all_rows() -> void:
	if is_select_mode_multi_row():
		for row: Dictionary in _rows:
			row.selected = row.visible
	else:
		return deselect_all_rows()

	row_selection_changed.emit()
	queue_redraw()

func deselect_all_rows() -> void:
	for row: Dictionary in _rows:
		row.selected = false

	row_selection_changed.emit()
	queue_redraw()




func set_cell_value_no_signal(row_idx: int, column_idx: int, value: Variant) -> bool:
	var cell: Dictionary = _rows[row_idx][&"cells"][column_idx]
	if is_same(cell.value, value):
		return false

	var text_line: TextLine = cell.text_line
	text_line.clear()

	var stringifier: Callable = cell.type_hint.stringifier
	if not stringifier.is_valid() or value == null:
		text_line.add_string("<null>", _font, _font_size)
	else:
		text_line.add_string(stringifier.call(value), _font, _font_size)

	cell.value = value

	return true

func set_cell_value(row_idx: int, column_idx: int, value: Variant) -> void:
	if set_cell_value_no_signal(row_idx, column_idx, value):
		cell_value_changed.emit(row_idx, column_idx, value)

func get_cell_value(row_idx: int, column_idx: int) -> Variant:
	return _rows[row_idx][&"cells"][column_idx][&"value"]


func set_cell_metadata(row_idx: int, column_idx: int, metadata: Variant) -> void:
	var cell: Dictionary = _rows[row_idx][&"cells"][column_idx]

	if metadata == null:
		cell.erase(&"metadata")
	else:
		cell[&"metadata"] = metadata

func get_cell_metadata(row_idx: int, column_idx: int, default: Variant = null) -> Variant:
	var cell: Dictionary = _rows[row_idx][&"cells"][column_idx]
	return cell.get(&"metadata", default)


func set_cell_custom_type(
		row_idx: int,
		column_idx: int,
		type: Type,
		hint: Hint = Hint.NONE,
		hint_string: String = "",
		stringifier: Callable = stringifier_default(type, hint, hint_string),
		edit_handler: Callable = edit_handler_default(type, hint, hint_string),
	) -> void:

	_rows[row_idx][&"cells"][column_idx][&"type_hint"] = create_type_hint(
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

	if cell.value == null:
		return "<null>"

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

	mark_dirty()


func find_column_at_position(point: Vector2) -> int:
	for i: int in _columns.size():
		var column: Dictionary = _columns[i]
		if column.visible and Rect2(column.rect).has_point(point):
			return i

	return INVALID_COLUMN


func grip_rect(rect: Rect2) -> Rect2:
	const GRIP_SIZE = 6

	return Rect2(
		rect.position.x + rect.size.x - GRIP_SIZE,
		rect.position.y,
		GRIP_SIZE * 2,
		rect.size.y,
	)

func find_resizable_column(point: Vector2) -> int:
	if not _header.has_point(point):
		return INVALID_COLUMN

	for i: int in _columns.size():
		if not _columns[i][&"visible"]:
			continue

		var rect := scrolled_rect_horizontal(_columns[i][&"rect"])
		if grip_rect(rect).has_point(point):
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

	for i: int in _columns.size():
		if _columns[i][&"visible"] and Rect2(cells[i][&"rect"]).has_point(point):
			return i

	return INVALID_CELL




func clear() -> void:
	_columns.clear()
	_rows.clear()

	if is_instance_valid(_cell_editor):
		_cell_editor.queue_free()

	queue_redraw()




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

func _on_column_rmb_clicked(column_idx: int) -> void:
	if not is_instance_valid(_column_context_menu):
		return

	_column_context_menu.set_item_count(get_column_count())

	for i: int in get_column_count():
		_column_context_menu.set_item_as_checkable(i, true)
		_column_context_menu.set_item_text(i, get_column_title(i))
		_column_context_menu.set_item_checked(i, is_column_visible(i))
		_column_context_menu.set_item_disabled(i, not can_hide_column(i))

	_column_context_menu.popup(Rect2i(get_screen_transform() * get_local_mouse_position(), Vector2i.ZERO))


func _on_row_selection_changed() -> void:
	match get_select_mode():
		SelectMode.SINGLE_ROW:
			var selected_rows := get_selected_rows()
			if selected_rows.is_empty():
				return

			single_row_selected.emit(selected_rows[0])

		SelectMode.MULTI_ROW:
			multiple_rows_selected.emit(get_selected_rows())


func _on_row_rmb_clicked(row_idx: int) -> void:
	if not is_row_selected(row_idx):
		select_single_row(row_idx)


func _on_cell_double_click(row_idx: int, column_idx: int) -> void:
	if not is_editable():
		return

	var row: Dictionary = _rows[row_idx]
	var cell: Dictionary = row[&"cells"][column_idx]

	var edit_handler: Callable = cell.type_hint.edit_handler
	if not edit_handler.is_valid():
		return

	var text_line: TextLine = cell.text_line
	var stringifier: Callable = cell.type_hint.stringifier

	var setter: Callable = func set_value(value: Variant) -> void:
		if is_same(cell.value, value):
			return

		text_line.clear()
		if value == null:
			text_line.add_string("<null>", _font, _font_size)
		else:
			text_line.add_string(stringifier.call(value), _font, _font_size)

		cell.value = value
		cell_value_changed.emit(row_idx, column_idx, value)

		queue_redraw()
	var getter: Callable = func get_value() -> Variant:
		return cell.value

	edit_handler.call(cell, setter, getter)


func _on_scroll_value_changed(_value) -> void:
	queue_redraw()




static func draw_text_line(ci: RID, text_line: TextLine, font_color: Color, outline_size: int, outline_color: Color, rect: Rect2) -> void:
	var text_position := Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 - text_line.get_size().y * 0.5)

	if outline_size and outline_color.a:
		text_line.draw_outline(ci, text_position, outline_size, outline_color)

	text_line.draw(ci, text_position, font_color)


static func get_texture_position_in_rect(texture_size: Vector2, rect: Rect2, alignment: HorizontalAlignment) -> Vector2:
	var horizontal_position: float
	match alignment:
		HORIZONTAL_ALIGNMENT_LEFT:
			horizontal_position = rect.position.x
		HORIZONTAL_ALIGNMENT_RIGHT:
			horizontal_position = rect.position.x + rect.size.x - texture_size.x
		_:
			horizontal_position = rect.get_center().x - texture_size.x * 0.5

	return Vector2(horizontal_position, rect.position.y + rect.size.y * 0.5 - texture_size.y * 0.5)
