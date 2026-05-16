# Copyright (c) 2024-2026 Mansur Isaev and contributors - MIT License
# See `LICENSE` included in the source distribution for details.

@tool
extends EditorPlugin


const TYPE = "TableView"
const BASE = "Control"
const SCRIPT = preload("res://addons/table-view/scripts/table_view.gd")
const ICON = preload("res://addons/table-view/icons/table_view.svg")


func _enter_tree() -> void:
	add_custom_type(TYPE, BASE, SCRIPT, ICON)


func _exit_tree() -> void:
	remove_custom_type(TYPE)
