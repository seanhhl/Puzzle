class_name LevelSelectDialog
extends Control

signal level_selected(file_query: String)
signal dialog_closed

@onready var filename_input: LineEdit = %FilenameInput
@onready var load_button: Button = %LoadButton
@onready var quick_chips_container: HFlowContainer = %QuickChipsContainer
@onready var error_label: Label = %ErrorLabel
@onready var default_button: Button = %DefaultButton
@onready var close_button: Button = %CloseButton

func _ready() -> void:
	load_button.pressed.connect(_on_load_pressed)
	default_button.pressed.connect(_on_default_pressed)
	close_button.pressed.connect(close)
	filename_input.text_submitted.connect(_on_text_submitted)

## Opens the dialog and populates quick-select chips.
func open(suggested_files: Array[String] = []) -> void:
	visible = true
	error_label.text = ""
	filename_input.text = ""
	_populate_quick_chips(suggested_files)
	filename_input.grab_focus()

## Closes the dialog.
func close() -> void:
	visible = false
	dialog_closed.emit()

## Displays an error message to guide the user.
func show_error(message: String) -> void:
	error_label.text = message
	filename_input.grab_focus()
	filename_input.select_all()

func _on_load_pressed() -> void:
	var query := filename_input.text.strip_edges()
	level_selected.emit(query)

func _on_text_submitted(new_text: String) -> void:
	var query := new_text.strip_edges()
	level_selected.emit(query)

func _on_default_pressed() -> void:
	level_selected.emit("")

func _populate_quick_chips(files: Array[String]) -> void:
	for child in quick_chips_container.get_children():
		child.queue_free()

	for f in files:
		var btn := Button.new()
		btn.text = f
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(func():
			filename_input.text = f
			level_selected.emit(f)
		)
		quick_chips_container.add_child(btn)

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		close()
		get_viewport().set_input_as_handled()

