# TableView Documentation

`TableView` is a high-performance, programmatic table control designed for Godot 4.6+. Unlike standard UI nodes that rely on individual child nodes for every cell, `TableView` utilizes the `RenderingServer` to draw data directly. This architecture allows for the efficient display and interaction of massive datasets containing thousands of rows without significant performance degradation.

> [!IMPORTANT]
> **Requirements:** Godot 4.6 or higher.
> **Status:** This project is under active development. Use with caution in production environments.

![](https://github.com/user-attachments/assets/ab17075f-dd904846-9fa3-7a18572d28ec)

## Features

*   **High-Performance Rendering:** Optimized drawing via `RenderingServer` for large datasets.
*   **Column-Based Sorting:** Support for ascending and descending sort modes per column.
*   **In-Place Cell Editing:** Type-safe editing with specialized input handlers (SpinBoxes, LineEdits, ColorPickers, Popups, etc.).
*   **Advanced Data Hints:** Built-in support for Ranges, Enums, Bitwise Flags, and Button-style Callables.
*   **Row Filtering:** Dynamic row visibility control using custom `Callable` predicates.
*   **Metadata Support:** Manually attach arbitrary data (objects, dictionaries) to rows and cells.
*   **Flexible Selection:** Supports Single-row and Multi-row selection modes.
*   **Dynamic Structure:** Columns and rows can be added, removed, or resized at any time.

## Installation

1. Clone this repository into your project's `addons/` folder.
2. Open Godot, navigate to **Project Settings > Plugins**.
3. Enable the **Table View** plugin.

## Usage

`TableView` is designed to be controlled entirely through code. It does not provide a visual editor interface for configuring columns or rows.

### 1. Initialization

Add a `TableView` node to your scene and reference it in your script.

```gdscript
@onready var table: TableView = $TableView
```

> [!TIP]
> For a complete working demonstration of all features, including complex data types, custom context menus, and filtering, refer to the `example.tscn` scene included in this repository.

### 2. Managing Columns

Columns can be added at any time, even after rows have been populated. The table structure is fully dynamic. The `add_column` method returns the index of the created column, which should be stored for later data assignment.

```gdscript
# Basic String column
var col_name: int = table.add_column("Name", TableView.Type.STRING)

# Boolean column (Checkboxes)
var col_active: int = table.add_column("Active", TableView.Type.BOOL)

# Integer column with a Range hint (creates a SpinBox editor)
var col_score: int = table.add_column("Score", TableView.Type.INT, TableView.hint_range(0, 100, 1))

# Enum column (creates a PopupMenu editor)
# Note: GDScript enums are compiled to dictionaries internally
var col_class: int = table.add_column("Class", TableView.Type.INT, TableView.hint_enum(CharacterClass))
```

### 3. Managing Rows and Cell Values

Rows can be added incrementally or pre-allocated in bulk. Choose the approach that best matches your data flow and performance requirements.

#### Option A: Incremental Updates
Best for dynamic lists where the total size is unknown or changes frequently.

```gdscript
func populate_incrementally(data_list: Array[Dictionary]):
    for item: Dictionary in data_list:
        var row_idx: int = table.add_row()
        # Use set_cell_value to ensure signals are emitted for single updates
        table.set_cell_value(row_idx, col_name, item["name"])
        table.set_cell_value(row_idx, col_score, item["score"])
```

#### Option B: Bulk Pre-allocation (Recommended for large datasets)
When loading thousands of rows, pre-allocating the row count and using the `no_signal` variant significantly reduces overhead.

```gdscript
func populate_bulk(data_list: Array[Dictionary]):
    # Pre-allocate the exact number of rows needed
    table.set_row_count(data_list.size())

    for i: int in data_list.size():
        # Use set_cell_value_no_signal to avoid emitting thousands of signals during initialization
        table.set_cell_value_no_signal(i, col_name, data_list[i]["name"])
        table.set_cell_value_no_signal(i, col_score, data_list[i]["score"])
```

## Advanced Functionality

### Cell Value Management

*   **`set_cell_value(row_idx, column_idx, value)`**: Sets the cell value and emits the `cell_value_changed` signal. Use this for individual updates, such as when a user interacts with an editor or when a single value changes during gameplay.
*   **`set_cell_value_no_signal(row_idx, column_idx, value) -> bool`**: Sets the cell value and updates the visual text representation without emitting any signals. Returns `true` if the value actually changed. Use this for mass data loading or heavy background updates to maintain high performance.

### Metadata Attachment
Metadata allows you to manually associate an arbitrary object or data structure with a specific row or cell. This is used to retrieve your underlying data model when a row or cell is interacted with, without storing the actual object inside the cell's displayed value.

```gdscript
# Attach a complex object to a row
var row_idx = table.add_row()
table.set_row_metadata(row_idx, my_game_item_instance)

# Retrieve the object when a row is selected
func _on_row_selected(row_idx: int):
	var item = table.get_row_metadata(row_idx)
	print("Interacting with: ", item.get_name())
```

### Filtering Rows
You can hide rows based on a condition. This is highly efficient for search bars or dynamic views.

```gdscript
func _on_search_changed(text: String) -> void:
	# Filters the 'Name' column (index 0) to only show rows where
	# the name contains the search text
	table.filter_rows_by_callable(0, text.is_subsequence_ofn)
```

### Sorting
Sorting is handled per column using the `sort_by_column` method. The table automatically manages sort mode icons and delegates comparison logic to the column's configured comparator.

```gdscript
# Sort the 'Score' column in descending order
table.sort_by_column(col_score, TableView.SortMode.DESCENDING)
```

## FAQ

### Why would you implement a custom class when a `Tree` node can do almost all the same things?
While the built-in `Tree` node is a versatile tool, it lacks native support for column-based sorting and custom in-place cell editors. I needed those features, but the primary reason is: because I can.

# License
Copyright (c) 2024-2026 Mansur Isaev and contributors

Unless otherwise specified, files in this repository are licensed under the
MIT license. See [LICENSE.md](LICENSE.md) for more information.
