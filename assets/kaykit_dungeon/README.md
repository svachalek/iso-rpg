Furniture models from KayKit - Dungeon Asset Pack 1.1 by Kay Lousberg
(https://kaylousberg.itch.io/kaykit-dungeon), CC0, see LICENSE.txt.
Loaded at runtime by scripts/tile_library.gd; the .gdignore keeps the editor
from importing them as scenes.

This folder holds only the models in use, copied from the full pack
(assets/KayKit_Dungeon_Pack_1.1_EXTRA, ignored by git and Godot); to add one,
copy its .gltf and .bin from Assets/gltf and name it in FURNITURE_SPECS. They
share dungeon_texture.png, which each .gltf refers to by name.

These used to come from the older Dungeon Remastered pack, whose models are
the same size to the millimetre; the two atlases differ only in the second
half of the last row, which nothing here samples.

The fireplace and shop counter are not from the pack: scripts/tile_library.gd
builds them from chamfered boxes mapped onto the pack's atlas so they match.
