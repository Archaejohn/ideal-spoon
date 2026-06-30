#!/usr/bin/env python3
"""comfy_gen.py — generate a REFERENCE image from the local ComfyUI server (Flux.2 Klein 4B).

These images are concept/reference only — the shipped art is original authored SVG traced/based
on them (see docs/art/STYLE_GUIDE.md). The game itself never touches ComfyUI or any network.

Usage:
  python tools/art/comfy_gen.py --prompt "..." --out art/refs/foo.png [--seed N]
        [--steps 20] [--width 1024] [--height 1024] [--neg "..."] [--server http://127.0.0.1:8000]

Drives the proven workflow in tools/art/flux2_klein_workflow.json (UNETLoader flux-2-klein-base-4b
+ CLIPLoader qwen_3_4b + flux2-vae). Injects prompt/seed/size by node class_type so it survives
node-id changes. Polls /history, downloads the PNG via /view.
"""
import argparse, json, os, sys, time, urllib.request, urllib.parse, random

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = os.path.join(HERE, "flux2_klein_workflow.json")


def _http(url, data=None, timeout=600):
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"} if data else {})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def build_graph(prompt, neg, seed, steps, width, height, prefix):
    g = json.load(open(TEMPLATE))
    # Positive text lives in a PrimitiveStringMultiline; negative is the empty-text CLIPTextEncode.
    for nid, node in g.items():
        ct = node.get("class_type"); ins = node.setdefault("inputs", {})
        if ct == "PrimitiveStringMultiline":
            ins["value"] = prompt
        elif ct == "CLIPTextEncode" and isinstance(ins.get("text"), str):
            ins["text"] = neg  # the literal-string CLIPTextEncode is the negative prompt
        elif ct == "RandomNoise":
            ins["noise_seed"] = seed
        elif ct == "Flux2Scheduler" and "steps" in ins:
            ins["steps"] = steps
        elif ct == "PrimitiveInt":
            # width/height primitives — set both; harmless if one is something else.
            pass
        elif ct == "SaveImage":
            ins["filename_prefix"] = prefix
    # width/height: the EmptyFlux2LatentImage + scheduler read PrimitiveInt nodes; set those.
    int_nodes = [n for n in g.values() if n.get("class_type") == "PrimitiveInt"]
    if len(int_nodes) >= 2:
        int_nodes[0].setdefault("inputs", {})["value"] = width
        int_nodes[1].setdefault("inputs", {})["value"] = height
    return g


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prompt", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--neg", default="")
    ap.add_argument("--seed", type=int, default=-1)
    ap.add_argument("--steps", type=int, default=20)
    ap.add_argument("--width", type=int, default=1024)
    ap.add_argument("--height", type=int, default=1024)
    ap.add_argument("--prefix", default="AetherRef")
    ap.add_argument("--server", default="http://127.0.0.1:8000")
    a = ap.parse_args()

    seed = a.seed if a.seed >= 0 else random.randint(0, 2**31 - 1)
    graph = build_graph(a.prompt, a.neg, seed, a.steps, a.width, a.height, a.prefix)

    payload = json.dumps({"prompt": graph}).encode()
    resp = json.loads(_http(f"{a.server}/prompt", data=payload, timeout=30))
    pid = resp["prompt_id"]
    print(f"[gen] queued prompt_id={pid} seed={seed} steps={a.steps} {a.width}x{a.height}")

    # Poll history for completion.
    img = None
    deadline = time.time() + 600
    while time.time() < deadline:
        time.sleep(2)
        hist = json.loads(_http(f"{a.server}/history/{pid}", timeout=30) or b"{}")
        if pid in hist:
            outs = hist[pid].get("outputs", {})
            for node_out in outs.values():
                for im in node_out.get("images", []):
                    img = im
                    break
            if img:
                break
    if not img:
        print("[gen] ERROR: no image produced before timeout", file=sys.stderr)
        sys.exit(1)

    q = urllib.parse.urlencode({"filename": img["filename"], "subfolder": img.get("subfolder", ""), "type": img.get("type", "output")})
    data = _http(f"{a.server}/view?{q}", timeout=120)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, "wb") as f:
        f.write(data)
    print(f"[gen] saved {len(data)} bytes -> {a.out}  (seed {seed})")


if __name__ == "__main__":
    main()
