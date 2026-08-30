# Media/ — custom pet-model backgrounds (optional, player-supplied)

This folder is **empty on purpose**. PetStableManagement ships no image files so the
addon stays small. It exists only as the place the **Custom** pet model background
looks for images.

When you pick **Options → Pet Stable Management → Pet Model Background → Custom**, the
addon draws a per-specialization image behind the 3D model in the Owned Pets panel and
the Models Browser. It loads three files from this folder, one per spec. A missing file
falls back to the plain background for that spec, so you can supply one, two, or all
three.

## Files to add

Put these in `Interface/AddOns/PetStableManagement/Media/`:

| Specialization | File name         |
|----------------|-------------------|
| Ferocity       | `bg_ferocity.tga` |
| Tenacity       | `bg_tenacity.tga` |
| Cunning        | `bg_cunning.tga`  |

## Format

- **`.tga`** (32-bit uncompressed) or **`.blp`**. If you use `.blp`, keep the name
  `bg_ferocity` etc. — WoW resolves the extensionless path to `.blp` first, then `.tga`.
- **Power-of-two dimensions**: 256×256, 512×512, or 1024×512. Square (512×512) is a safe
  default — the image is stretched to fill each row/popup.
- No spaces or non-ASCII characters in the file name.
- `/reload` after adding or changing files.

## Heads up: updates wipe this folder

Most addon updaters (like CurseForge app) replace the entire
`PetStableManagement/` directory on update, which deletes anything you added here. Your
*setting* survives, so the background just reverts to plain until you put the files
back. **Keep your three images somewhere safe** and re-copy them after each update.
