set -e
cd /c/Users/cpjel/Desktop/RPG_game
SRC=art/pixel_anim/master_base_south.png
LEFT="the same pixel art girl character, now in a mid-walking step pose seen from the front, her LEFT foot stepped forward and lifted, right foot back on its toe, arms swinging naturally opposite the legs, keep her exact hair face short tan jacket cream shirt glowing amber pendant brown trousers boots and the identical 16-bit SNES pixel art style and palette, plain solid gray background, full body centered"
RIGHT="the same pixel art girl character, now in a mid-walking step pose seen from the front, her RIGHT foot stepped forward and lifted, left foot back on its toe, arms swinging naturally opposite the legs, keep her exact hair face short tan jacket cream shirt glowing amber pendant brown trousers boots and the identical 16-bit SNES pixel art style and palette, plain solid gray background, full body centered"
for s in 1 2 3 4 5 6 7 8; do
  python tools/art/comfy_edit.py --src "$SRC" --seed $s --steps 20 --instruction "$LEFT"  --out art/pixel_anim/candidates/left_s$s.png  2>&1 | tail -1
done
for s in 1 2 3 4 5 6 7 8; do
  python tools/art/comfy_edit.py --src "$SRC" --seed $s --steps 20 --instruction "$RIGHT" --out art/pixel_anim/candidates/right_s$s.png 2>&1 | tail -1
done
echo "WALK_BATCH_DONE"
