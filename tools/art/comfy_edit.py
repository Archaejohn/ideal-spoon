#!/usr/bin/env python3
"""comfy_edit.py — Flux.2 Klein IMAGE EDIT via ComfyUI ReferenceLatent.

Feeds an ORIGINAL image + an edit instruction: the source is VAE-encoded and fed as a
ReferenceLatent to condition generation, so the character's identity is preserved while the
instruction changes pose/expression. Grafts the edit nodes onto our working text-gen graph
(same installed models: klein-base-4b + qwen_3_4b + flux2-vae).

Usage:
  python tools/art/comfy_edit.py --src art/refs/wren_fullbody_v1.png \
      --instruction "the same girl waving her right hand high" --out art/refs/edit_wave.png [--seed N]
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
    fname = os.path.basename(path)
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


def build(src_name, instruction, seed, steps, w, h, cfg, prefix):
    g = json.load(open(BASE))
    # locate key nodes by class_type
    guider = find(g, "CFGGuider")[0]
    vae = find(g, "VAELoader")[0]
    prompt_node = find(g, "PrimitiveStringMultiline")[0]
    ints = find(g, "PrimitiveInt")
    noise = find(g, "RandomNoise")[0]
    sched = find(g, "Flux2Scheduler")[0]
    save = find(g, "SaveImage")[0]
    pos_cond = g[guider]["inputs"]["positive"][0]   # the positive CLIPTextEncode node id

    # edit nodes
    g["e_load"] = {"class_type": "LoadImage", "inputs": {"image": src_name}}
    g["e_enc"] = {"class_type": "VAEEncode", "inputs": {"pixels": ["e_load", 0], "vae": [vae, 0]}}
    g["e_ref"] = {"class_type": "ReferenceLatent", "inputs": {"conditioning": [pos_cond, 0], "latent": ["e_enc", 0]}}
    # rewire guider positive -> reference-conditioned
    g[guider]["inputs"]["positive"] = ["e_ref", 0]
    if "cfg" in g[guider]["inputs"]:
        g[guider]["inputs"]["cfg"] = cfg

    # set instruction, seed, size
    g[prompt_node]["inputs"]["value"] = instruction
    g[noise]["inputs"]["noise_seed"] = seed
    g[sched]["inputs"]["steps"] = steps
    for i in ints[:1]:
        g[i]["inputs"]["value"] = w
    for i in ints[1:2]:
        g[i]["inputs"]["value"] = h
    g[save]["inputs"]["filename_prefix"] = prefix
    return g


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--instruction", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=int, default=-1)
    ap.add_argument("--steps", type=int, default=28)
    ap.add_argument("--cfg", type=float, default=4.0)
    ap.add_argument("--server", default="http://127.0.0.1:8000")
    a = ap.parse_args()

    seed = a.seed if a.seed >= 0 else random.randint(0, 2**31 - 1)
    im = Image.open(a.src); w, h = im.size
    w -= w % 16; h -= h % 16
    name = upload_image(a.src, a.server)
    print(f"[edit] uploaded {name}  size {w}x{h}  seed {seed}")
    g = build(name, a.instruction, seed, a.steps, w, h, a.cfg, "AetherEdit")

    pid = json.loads(_http(f"{a.server}/prompt", data=json.dumps({"prompt": g}).encode(), timeout=30))["prompt_id"]
    print("[edit] queued", pid)
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
        print("[edit] ERROR: no image", file=sys.stderr); sys.exit(1)
    q = urllib.parse.urlencode({"filename": img["filename"], "subfolder": img.get("subfolder", ""), "type": img.get("type", "output")})
    data = _http(f"{a.server}/view?{q}", timeout=120)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    open(a.out, "wb").write(data)
    print(f"[edit] saved {len(data)} bytes -> {a.out} (seed {seed})")


if __name__ == "__main__":
    main()
