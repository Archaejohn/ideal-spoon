set -e; cd /c/Users/cpjel/Desktop/RPG_game
E=art/pixel_anim/master_base_east.png; N=art/pixel_anim/master_base_north.png
EF="the same pixel art girl in right-side profile facing right, mid-walk stride, her near (front) leg stepped forward and lifted, far leg pushing back, arms swinging opposite the legs, keep exact wheat-gold hair tan jacket cream shirt amber pendant brown trousers boots and identical 16-bit SNES pixel art style and palette, plain solid gray background, full body"
EB="the same pixel art girl in right-side profile facing right, mid-walk stride, her far leg swung forward and near leg back on its toe, arms swinging opposite, keep exact wheat-gold hair tan jacket cream shirt amber pendant brown trousers boots and identical 16-bit SNES pixel art style and palette, plain solid gray background, full body"
NF="the same pixel art girl seen from behind facing away (back view, no face), mid-walk step, her left leg stepped forward and lifted, right leg back, arms swinging, back of bob hair and jacket visible, keep identical 16-bit SNES pixel art style and palette brown trousers boots, plain solid gray background, full body"
NB="the same pixel art girl seen from behind facing away (back view, no face), mid-walk step, her right leg stepped forward and lifted, left leg back, arms swinging, back of bob hair and jacket visible, keep identical 16-bit SNES pixel art style and palette brown trousers boots, plain solid gray background, full body"
for s in 1 2 3 4; do python tools/art/comfy_edit.py --src "$E" --seed $s --steps 20 --instruction "$EF" --out art/pixel_anim/candidates/east_fwd_s$s.png 2>&1|tail -1; done
for s in 1 2 3 4; do python tools/art/comfy_edit.py --src "$E" --seed $s --steps 20 --instruction "$EB" --out art/pixel_anim/candidates/east_back_s$s.png 2>&1|tail -1; done
for s in 1 2 3 4; do python tools/art/comfy_edit.py --src "$N" --seed $s --steps 20 --instruction "$NF" --out art/pixel_anim/candidates/north_fwd_s$s.png 2>&1|tail -1; done
for s in 1 2 3 4; do python tools/art/comfy_edit.py --src "$N" --seed $s --steps 20 --instruction "$NB" --out art/pixel_anim/candidates/north_back_s$s.png 2>&1|tail -1; done
echo BATCH2_DONE
