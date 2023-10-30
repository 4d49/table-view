# TableView
`TableView` is a custom class that implements a table view to display data as a table. It is similar to the built-in `Tree` class.

> [!WARNING]
> Only Godot 4.4+ is supported. This add-on is still in development and needs testing!

![](https://github.com/user-attachments/assets/56584f78-3155-46da-95d3-516edd7efd00)

# Installation:
1. `git clone` this repository to `addons` folder.
2. Enable `Table View` in Plugins.
3. Done!

# First step:
The first thing I would recommend is to check out the test [scene](example.tscn) in the repository.

# Usage:
`TableView` does not have a user interface for managing columns and rows; all management is done programmatically.

## Prepare.
Add `TableView` as a child node to the scene.

```gdscript
# Declare a `TableView` in a parent node.
@onready var table_view: TableView = $TableView
```

## Create columns.
```gdscript
# The `add_column` method returns the index of the new column.
# The first argument is the column title, the second its type.
var uid := table_view.add_column("UID", TableView.Type.STRING_NAME)
var name := table_view.add_column("Name", TableView.Type.STRING)
var unique := table_view.add_column("Unique", TableView.Type.BOOL)
# The third argument is the type of hint.
var description := table_view.add_column("Description", TableView.Type.STRING, TableView.Hint.MULTILINE_TEXT)
# The fourth argument is a type hint string.
var cost := table_view.add_column("Cost", TableView.Type.INT, TableView.Hint.RANGE, "0,9999")
var weight := table_view.add_column("Weight", TableView.Type.FLOAT, TableView.Hint.RANGE, "0.0,99.99,0.1")
```

## Creating rows.
```gdscript
# Some method returning an array with dictionaries.
for data: Dictionary in get_some_data():
	var row_idx := table_view.add_row()
	# Previously declared variables are used as the column index.
	table_view.set_cell_value(row_idx, uid, data.uid)
	table_view.set_cell_value(row_idx, name, data.name)
	table_view.set_cell_value(row_idx, unique, data.unique)
	table_view.set_cell_value(row_idx, cost, data.cost)
	table_view.set_cell_value(row_idx, weight, data.weight)
```

# FAQ:
### Why would you implement a custom class when a `Tree` node can do almost all the same things?
Because I can.

# License
Copyright (c) 2024 Mansur Isaev and contributors

Unless otherwise specified, files in this repository are licensed under the
MIT license. See [LICENSE.md](LICENSE.md) for more information.
