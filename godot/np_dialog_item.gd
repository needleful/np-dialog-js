class_name NPDialogItem
extends Object

enum Type {
	Narration,
	Message,
	Option
}

var on_enter := -1
var on_skip := -1
var bb_text := ""
var can_enter: Callable
var get_next: Callable
var run_effects: Callable
var interpolation: Callable
var options: Array[int]

func get_text(ctx):
	if interpolation:
		bbText.format(interpolation.call(ctx))
	else:
		return bbText