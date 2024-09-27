# TableView
`TableView` is a custom class that implements a table view to display data as a table. It is similar to the built-in `Tree` class.

> [!IMPORTANT]
Only Godot 4.4+ is supported. This add-on is still in development and needs testing!

![](https://github.com/user-attachments/assets/ab17075f-dd90-4846-9fa3-7a18572d28ec)

# Features
- Column sorting capabilities
- Filter rows with a custom Callable method
- In-place cell value editing

# Installation
1. `git clone` this repository to `addons` folder.
2. Enable `Table View` in Plugins.
3. Done!

# Usage
A `TableView` does not provide a built-in user interface for managing columns and rows. Instead, all control and customization must be done programmatically through code.

## Getting Started
First, I recommend checking out the test [scene](example.tscn) in the repository.

## Prepare
Add `TableView` as a child node to the scene.

```gdscript
# Declare a `TableView` in a parent node.
@onready var table_view: TableView = $TableView
```

## Create columns
```gdscript
# The `add_column` method returns the index of the newly created column.
# The first argument defines the column title, and the second defines its data type.
var name = table_view.add_column("Name", TableView.Type.STRING)
var unique = table_view.add_column("Unique", TableView.Type.BOOL)
# The third argument defines the hint type.
var cost = table_view.add_column("Cost", TableView.Type.INT, TableView.Hint.RANGE, TableView.range_to_hint_string(0, 1000))
```

## Creating rows
```gdscript
for item: Dictionary in get_items(): # Returns an array of dictionaries.
	# Adds a new row and returns the index of the newly created row.
	var row = table_view.add_row()

	# Previously declared variables are passed as the column index argument.
	table_view.set_cell_value(row, name, item.name)
	table_view.set_cell_value(row, unique, item.unique)
	table_view.set_cell_value(row, cost, item.cost)
```

# FAQ
### Why would you implement a custom class when a `Tree` node can do almost all the same things?
Because I can.

# License
Copyright (c) 2024 Mansur Isaev and contributors

Unless otherwise specified, files in this repository are licensed under the
MIT license. See [LICENSE.md](LICENSE.md) for more information.
