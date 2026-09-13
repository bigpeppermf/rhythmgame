# visual/

Everything about how the game looks. Gameplay never reads any of it.

The default tap notes and hold heads use the four gesture PNGs currently in
`assets/menu/`. `default/gesture_art.gd` maps each chart gesture to its image;
unrestricted notes use the open-palm image without adding a gesture requirement.
Artwork faces the camera, preserves its original colors, and fades with distance.
Hold trails retain the hand's lane color and duration. Adjust `HEIGHT` in that
script to resize all four icons together. Their imports enable mipmaps for
smoother rendering as notes approach from depth.

## Replacing the look

1. Duplicate `default_skin.tres`
2. Point its scene slots at your own scenes, and set the palette
3. Change `SKIN_PATH` in `scenes/play_3d.gd` (or set `Playfield.skin` directly)

`example_alt/` is a worked example — tumbling cubes instead of spheres, a warm
palette, a coarser grid. It reuses the default hold/cursor/flash scenes, which
is the normal case: replace the parts you have designed, inherit the rest.

## The contracts

Your scenes need only extend one of these and implement its methods. None of
them know what a chart, a beat, or a score is.

| Base | Implement | Called with |
|---|---|---|
| `NoteView` | `configure(note, skin)` `update_view(approach, progress)` `release()` | `approach` 1→0 as the note nears the hit plane; `progress` 0→1 for holds |
| `CursorView` | `configure(slot, skin)` `update_view(confidence, state)` | tracking confidence and TRACKED/COASTING/LOST |
| `FlashView` | `configure(verdict, skin)` `update_view(age)` `release()` | `age` 0→1 over `flash_duration` |

**Position and orientation are not yours to set.** The playfield places every
view from song time and aligns it with its panel, because that is gameplay
geometry. Your scene controls appearance, and may transform its own children
freely.

In the basis you are handed, **-Z runs away down the panel and +Y is up**, and
the panel's normal is local X. So a dash lying on the panel is simply a mesh
that is long in Z and thin in X; a ring lying flat in the panel is a torus
tipped 90 degrees about Z.

## Why it is split this way

The lane, the notes and the cursors are the only things the player looks at,
and they are the things most likely to change once someone is actually
designing. Keeping them behind three tiny interfaces means art can land
without a merge conflict in the Judge.
