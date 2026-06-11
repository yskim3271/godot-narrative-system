extends SceneTree
## Rasterizes the repo icon.svg into icon.png (256x256) for the Asset
## Library icon URL (PNG recommended there; the SVG stays the source).
## Usage: godot --headless --path . -s res://scripts/make_icon.gd


func _initialize() -> void:
	var svg_text := FileAccess.get_file_as_string("res://icon.svg")
	if svg_text == "":
		printerr("make_icon: cannot read res://icon.svg")
		quit(1)
		return
	var image := Image.new()
	var err := image.load_svg_from_string(svg_text, 2.0)  # 128x128 source -> 256
	if err != OK:
		printerr("make_icon: SVG rasterization failed (%s)" % error_string(err))
		quit(1)
		return
	if image.get_width() != 256 or image.get_height() != 256:
		image.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	err = image.save_png("res://icon.png")
	if err != OK:
		printerr("make_icon: cannot write icon.png (%s)" % error_string(err))
		quit(1)
		return
	print("make_icon: wrote icon.png %dx%d" % [image.get_width(), image.get_height()])
	quit(0)
