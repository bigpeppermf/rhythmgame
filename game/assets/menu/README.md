# Ocean Motion menu assets

The main menu lives in `game/scenes/menu.tscn`. Open that scene in Godot to
select and reposition the individual artwork and buttons. Run the project
(F6 runs only this scene; F5 includes the game transitions).

- `ocean_motion_bg.png`: full-window background, cropped to fill without distortion.
- `main_title.png`: transparent title artwork.
- `play_button.png`: two-hand Play button. An AtlasTexture trims the empty side
  margins in Godot without modifying the original PNG.
- `1_hand.png`: launches one-hand play directly.
- `calibrate.png`: opens timing calibration.
- `options.png`: opens the Options panel.
- `bubble.png` and `star.png`: decorative accents positioned like the reference;
  they ignore mouse input so they cannot block buttons.
- `main_menu_look.png`: reference only; not displayed in the game.

The composition uses 1280×720 coordinates and scales uniformly to fit the
window. Its background fills the remaining space at other aspect ratios.
PNG transparency is preserved. No stingrays are added.

The Options panel contains input switching, calibration offset, both
Entertainer charts, the chart editor, and Quit.

Mouse clicks, Tab/Shift+Tab, arrow keys, and Enter/Space operate the buttons.
W/S also moves focus. Escape opens/closes Options; U switches the input source.
