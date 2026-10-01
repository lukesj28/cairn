# -*- coding: utf-8 -*-
import os

# Application bundle path
app_path = defines.get('app', 'Cairn.app')
app_name = os.path.basename(app_path)

# Volume format and filesystem
format = defines.get('format', 'UDZO')
filesystem = 'HFS+'

# Window dimensions: 600x400
window_width = 600
window_height = 400
window_rect = ((200, 120), (window_width, window_height))

# Background image
# dmgbuild automatically detects background@2x.png in the same directory and creates a HiDPI multi-resolution TIFF.
dmg_dir = os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else 'packaging/dmg'
background = defines.get('background', os.path.join(dmg_dir, 'background.png'))

# Content files and symlinks
files = [app_path]
symlinks = {'Applications': '/Applications'}

# Icon locations:
# - App icon sits at 25% of window width
# - Applications folder sits at 75% of window width
# - Centered vertically at 50% of window height
app_x = int(window_width * 0.25)       # 150
folder_x = int(window_width * 0.75)    # 450
icon_y = int(window_height * 0.50)     # 200

icon_locations = {
    app_name: (app_x, icon_y),
    'Applications': (folder_x, icon_y),
}

# Icon view settings
default_view = 'icon-view'
icon_size = 120.0
text_size = 14.0
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

# Volume badge icon (optional)
badge_icon = defines.get('badge_icon', None)
if not badge_icon:
    candidate_icns = os.path.join(app_path, 'Contents', 'Resources', 'AppIcon.icns')
    if os.path.isfile(candidate_icns):
        badge_icon = candidate_icns
