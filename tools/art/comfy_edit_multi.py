#!/usr/bin/env python3
"""comfy_edit_multi.py — Flux.2 Klein MULTI-REFERENCE edit.

Feeds 1..N reference images (each VAE-encoded and chained through its own ReferenceLatent) plus a
text instruction, so generation stays consistent with ALL supplied views/refs. Grafts onto our
working Klein-4b graph (klein-base-4b + qwen_3_4b + flux2-vae). Kept separate from comfy_edit.py so
in-flight batches that call comfy_edit.py are unaffected.

Usage:
  python tools/art/comfy_edit_multi.py --src front.png side.png back.png \
      --instruction "the same girl, three-quarter view walking" --out out.png [--seed N] [--size WxH]
"""
import argparse, json, os, sys, time, uuid, urllib.request, urllib.parse, random
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.join(HERE, "flux2_klein_workflow.json")


def _http(url, data=None, headers=None, timeout=600):
    req = urllib.request.Request(url, data=data, headers=headers or ({"Content-Type": "application/json"} if data else {}))
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def upload_image(path, server):
    b = uuid.uuid4().hex
    fname = "ref_%s_%s" % (uuid.uuid4().hex[:6], os.path.basename(path))
    body = b""
    body += ("--%s\r\n" % b).encode()
    body += ('Content-Disposition: form-data; name="image"; filename="%s"\r\n' % fname).encode()
    body += b"Content-Type: image/png\r\n\r\n" + open(path, "rb").read() + b"\r\n"
    body += ("--%s\r\n" % b).encode()
    body += b'Content-Disposition: form-data; name="overwrite"\r\n\r\ntrue\r\n'
    body += ("--%s--\r\n" % b).encode()
    r = json.loads(_http(server + "/upload/image", data=body,
                         headers={"Content-Type": "multipart/form-data; boundary=%s" % b}, timeout=60))
    return r["name"]


def find(g, ct):
    return [nid for nid, n in g.items() if n.get("class_type") == ct]


def build(ref_names, instruction, seed, steps, w, h, cfg, prefix):
    g = json.load(open(BASE))
    guider = find(g, "CFGGuider")[0]
    vae = find(g, "VAELoader")[0]
    prompt_node = find(g, "PrimitiveStringMultiline")[0]
    ints = find(g, "PrimitiveInt")
    noise = find(g, "RandomNoise")[0]
    sched = find(g, "Flux2Scheduler")[0]
    save = find(g, "SaveImage")[0]
    pos_cond = g[guider]["inputs"]["positive"][0]

    # Chain one LoadImage->VAEEncode->ReferenceLatent per reference image.
    prev = [pos_cond, 0]
    for i, name in enumerate(ref_names):
        li, en, rl = f"m_load{i}", f"m_enc{i}", f"m_ref{i}"
        g[li] = {"class_type": "LoadImage", "inputs": {"image": name}}
        g[en] = {"class_type": "VAEEncode", "inputs": {"pixels": [li, 0], "vae": [vae, 0]}}
        g[rl] = {"class_type": "ReferenceLatent", "inputs": {"conditioning": prev, "latent": [en, 0]}}
        prev = [rl, 0]
    g[guider]["inputs"]["positive"] = prev
    if "cfg" in g[guider]["inputs"]:
        g[guider]["inputs"]["cfg"] = cfg

    g[prompt_node]["inputs"]["value"] = instruction
    g[noise]["inputs"]["noise_seed"] = seed
    g[sched]["inputs"]["steps"] = steps
    if ints:
        g[ints[0]]["inputs"]["value"] = w
    if len(ints) > 1:
        g[ints[1]]["inputs"]["value"] = h
    g[save]["inputs"]["filename_prefix"] = prefix
    return g


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", nargs="+", required=True, help="1..N reference images")
    ap.add_argument("--instruction", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=int, default=-1)
    ap.add_argument("--steps", type=int, default=24)
    ap.add_argument("--cfg", type=float, default=4.0)
    ap.add_argument("--size", default="", help="WxH; default = first ref's size (rounded /16)")
    ap.add_argument("--server", default="http://127.0.0.1:8000")
    a = ap.parse_args()

    seed = a.seed if a.seed >= 0 else random.randint(0, 2**31 - 1)
    if a.size:
        w, h = (int(x) for x in a.size.lower().split("x"))
    else:
        w, h = Image.open(a.src[0]).size
    w -= w % 16; h -= h % 16
    names = [upload_image(p, a.server) for p in a.src]
    print(f"[medit] {len(names)} refs, {w}x{h}, seed {seed}: {names}")
    g = build(names, a.instruction, seed, a.steps, w, h, a.cfg, "AetherMEdit")

    pid = json.loads(_http(f"{a.server}/prompt", data=json.dumps({"prompt": g}).encode(), timeout=30))["prompt_id"]
    img = None; deadline = time.time() + 600
    while time.time() < deadline:
        time.sleep(2)
        hist = json.loads(_http(f"{a.server}/history/{pid}", timeout=30) or b"{}")
        if pid in hist:
            for no in hist[pid].get("outputs", {}).values():
                for i in no.get("images", []):
                    img = i; break
            if img: break
    if not img:
        print("[medit] ERROR: no image", file=sys.stderr); sys.exit(1)
    q = urllib.parse.urlencode({"filename": img["filename"], "subfolder": img.get("subfolder", ""), "type": img.get("type", "output")})
    data = _http(f"{a.server}/view?{q}", timeout=120)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    open(a.out, "wb").write(data)
    print(f"[medit] saved {len(data)} bytes -> {a.out} (seed {seed})")


if __name__ == "__main__":
    main()
