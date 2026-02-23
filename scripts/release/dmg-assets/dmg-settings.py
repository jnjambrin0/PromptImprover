import os

app = defines.get("app")
background_path = defines.get("background")
app_name = os.path.basename(app)

format = "UDZO"
size = None
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extensions = [app_name]
badge_icon = app

background = background_path
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
window_rect = ((200, 200), (660, 400))
default_view = "icon-view"
show_icon_preview = False
include_icon_view_settings = "auto"
include_list_view_settings = False
icon_size = 128
text_size = 14
label_pos = "bottom"

icon_locations = {
    app_name: (170, 190),
    "Applications": (490, 190),
}
