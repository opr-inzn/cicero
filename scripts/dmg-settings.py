# dmgbuild's settings for the DMG make-dmg.sh builds: Cicero and a link to Applications, each on its well
# in Resources/DMG/background.png (drawn by make-dmg-background.mjs), in a window that fits the picture.
# dmgbuild writes the window's .DS_Store itself, so the Finder isn't involved.
import mac_alias

app = defines["app"]  # noqa: F821, both given by make-dmg.sh with -D

# dmgbuild points at the picture with an alias and a bookmark (pBBk). The Finder of macOS 26 goes by the bookmark, can't resolve the one dmgbuild makes up, and shows no picture at all. Without it, it uses the alias.
mac_alias.Bookmark.for_file = staticmethod(lambda path: None)

format = "ULMO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}

background = defines["background"]  # noqa: F821

# The Finder puts its title and tab bars (68 pt) above the picture's 400 and its path and status bars (56 pt) below it when turned on, which a window can't undo.
window_rect = ((200, 120), (660, 68 + 400 + 56))
show_toolbar = False
default_view = "icon-view"
icon_size = 128
text_size = 13
icon_locations = {"Cicero.app": (190, 212), "Applications": (470, 212)}
