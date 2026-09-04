"""Sweep the segmenter input scale and run the whole weight branch end to end.

For each candidate `seg_cm_per_px_input` T, the image is placed inside the 640x640
canvas at content scale s = cm_per_px_actual / T (so one canvas pixel == T cm),
segmented, the mask mapped back to original pixels, resampled by
k = cm_per_px_actual / cm_per_px_target, measured, domain-checked, and predicted.
"""
import io, os, sys, json
import numpy as np, cv2, onnxruntime as ort
from PIL import Image, ImageOps
import pillow_heif
pillow_heif.register_heif_opener()

REPO = sys.argv[1]
MAN = json.load(open(os.path.join(REPO, "assets/ml/manifest.json")))
SEG = MAN["capabilities"]["segmentation"]
W = MAN["capabilities"]["weight"]
CONF, IOU = SEG["postprocess"]["conf"], SEG["postprocess"]["iou"]
IMGSZ, PADC = SEG["model"]["input"]["size"][0], SEG["model"]["letterbox"]["color"][0]
CMT = W["capture_contract"]["cm_per_px_target"]
TFW, TFH = W["capture_contract"]["training_frame_px"]
UNC = W["capture_contract"]["cm_per_px_target_uncertainty"]
DOM = W["feature_domain"]

seg = ort.InferenceSession(os.path.join(REPO, "assets/ml/segmentation/yolo.onnx"), providers=["CPUExecutionProvider"])
reg = ort.InferenceSession(os.path.join(REPO, "assets/ml/weight/xgboost.onnx"), providers=["CPUExecutionProvider"])
SIN, RIN = seg.get_inputs()[0].name, reg.get_inputs()[0].name


def load(p, cap=3000):
    im = ImageOps.exif_transpose(Image.open(p)).convert("RGB")
    w, h = im.size
    s = min(cap / w, cap / h, 1.0)
    if s < 1.0:
        im = im.resize((round(w * s), round(h * s)), Image.BILINEAR)
    b = io.BytesIO(); im.save(b, "JPEG", quality=92)
    return np.array(Image.open(io.BytesIO(b.getvalue())).convert("RGB"))


def canvas(img, s, dst=IMGSZ, color=PADC):
    h, w = img.shape[:2]
    nw, nh = max(1, round(w * s)), max(1, round(h * s))
    if nw > dst or nh > dst:
        return None
    r = cv2.resize(img, (nw, nh), interpolation=cv2.INTER_LINEAR)
    o = np.full((dst, dst, 3), color, np.uint8)
    pl, pt = (dst - nw) // 2, (dst - nh) // 2
    o[pt:pt + nh, pl:pl + nw] = r
    return o, s, pl, pt, nw, nh


def iou_xywh(a, b):
    ax1, ay1, ax2, ay2 = a[0]-a[2]/2, a[1]-a[3]/2, a[0]+a[2]/2, a[1]+a[3]/2
    bx1, by1, bx2, by2 = b[0]-b[2]/2, b[1]-b[3]/2, b[0]+b[2]/2, b[1]+b[3]/2
    iw = max(0.0, min(ax2, bx2) - max(ax1, bx1)); ih = max(0.0, min(ay2, by2) - max(ay1, by1))
    inter = iw * ih
    ua = max(0.0, ax2-ax1)*max(0.0, ay2-ay1) + max(0.0, bx2-bx1)*max(0.0, by2-by1) - inter
    return 0.0 if ua <= 0 else inter / ua


def nms(dets, thr):
    dets = sorted(dets, key=lambda d: -d["conf"])
    kept, sup = [], [False] * len(dets)
    for i in range(len(dets)):
        if sup[i]:
            continue
        kept.append(dets[i])
        for j in range(i + 1, len(dets)):
            if not sup[j] and iou_xywh(dets[i]["box"], dets[j]["box"]) > thr:
                sup[j] = True
    return kept


def keepmask(shape, bnd):
    ph, pw = shape
    ys = np.arange(ph)[:, None]; xs = np.arange(pw)[None, :]
    return (xs >= bnd[0]) & (xs < bnd[2]) & (ys >= bnd[1]) & (ys < bnd[3])


def lcf(mask):
    b = ((mask > 0).astype(np.uint8)) * 255
    c, _ = cv2.findContours(b, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not len(c):
        return b
    o = np.zeros_like(b)
    cv2.drawContours(o, [max(c, key=cv2.contourArea)], -1, 255, cv2.FILLED)
    return o


def feats(mask, rw, rh):
    cl = lcf(mask)
    cs, _ = cv2.findContours(cl, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    if not len(cs):
        return None
    c = max(cs, key=cv2.contourArea)
    if len(c) < 5:
        return None
    a, b = cv2.minAreaRect(c)[1]
    el = cv2.fitEllipse(c)[1]
    mn, mx = min(el), max(el)
    return dict(RA=int(cv2.countNonZero(cl)) / float(rw * rh), LC=float(cv2.arcLength(c, True)),
                BL=float(max(a, b)), BW=float(min(a, b)),
                E=float(np.sqrt(max(0.0, 1 - (mn / mx) ** 2))) if mx > 0 else 0.0)


def domain_ok(f):
    pw = {"RA": UNC ** 2, "LC": UNC, "BL": UNC, "BW": UNC, "E": 1.0}
    bad = []
    for n, d in DOM.items():
        lo = d["min"] * d["lower_multiplier"] / pw[n]
        hi = d["max"] * d["upper_multiplier"] * pw[n]
        if not (lo <= f[n] <= hi):
            bad.append("%s=%.4f[%.4f,%.4f]" % (n, f[n], lo, hi))
    return bad


def run_one(img, cmpx, s):
    oh, ow = img.shape[:2]
    c = canvas(img, s)
    if c is None:
        return None, "content larger than canvas"
    cv_, sc, pl, pt, nw, nh = c
    ten = (cv_.astype(np.float32) / 255).transpose(2, 0, 1)[None]
    p0, p1 = [x[0] for x in seg.run(None, {SIN: ten})]
    nco, ph, pw = p1.shape
    ncls = p0.shape[0] - 4 - nco
    conf = p0[4:4 + ncls].max(axis=0)
    idx = np.where(conf >= CONF)[0]
    if not len(idx):
        return None, "no detection"
    dets = [dict(box=p0[0:4, a].astype(float), conf=float(conf[a]), co=p0[4+ncls:4+ncls+nco, a]) for a in idx]
    kept = nms(dets, IOU)
    best, ba, bsig, bb = None, -1, None, None
    for d in kept:
        sig = 1 / (1 + np.exp(-np.tensordot(d["co"], p1, axes=(0, 0))))
        bx = d["box"]
        bnd = ((bx[0]-bx[2]/2)*pw/IMGSZ, (bx[1]-bx[3]/2)*ph/IMGSZ,
               (bx[0]+bx[2]/2)*pw/IMGSZ, (bx[1]+bx[3]/2)*ph/IMGSZ)
        a = int(((sig > 0.5) & keepmask(sig.shape, bnd)).sum())
        if a > ba:
            ba, best, bsig, bb = a, d, sig, bnd
    m = np.where(keepmask(bsig.shape, bb), bsig, 0.0).astype(np.float32)
    up = cv2.resize(m, (IMGSZ, IMGSZ), interpolation=cv2.INTER_LINEAR)
    binr = (up > 0.5).astype(np.uint8) * 255
    crop = binr[pt:pt + nh, pl:pl + nw]
    full = cv2.resize(crop, (ow, oh), interpolation=cv2.INTER_NEAREST)
    nz = cv2.countNonZero(full)
    if not nz:
        return None, "empty mask"
    ys, xs = np.nonzero(full)
    bw_, bh_ = xs.max()-xs.min()+1, ys.max()-ys.min()+1
    diag = (bw_**2 + bh_**2) ** 0.5 / (ow**2 + oh**2) ** 0.5
    k = cmpx / CMT
    sm = cv2.resize(full, (max(1, round(ow*k)), max(1, round(oh*k))), interpolation=cv2.INTER_NEAREST)
    f = feats(sm, TFW, TFH)
    if f is None:
        return None, "contour too small"
    f["conf"] = best["conf"]; f["diag"] = diag; f["cands"] = len(kept)
    return f, None


PHOTOS = [(".pig_pictures/92kg_pig_meter_stick.HEIC", 0.0647, 92.0),
          (".pig_pictures/118kg_pig_porac_stick.jpg", 0.0653, 118.0),
          (".pig_pictures/96kg_pig_porac_stick.HEIC", 0.0633, 96.0)]
IMGS = [(os.path.basename(p).split(".")[0], load(os.path.join(REPO, p)), c, t) for p, c, t in PHOTOS]

mode = sys.argv[2] if len(sys.argv) > 2 else "T"
if mode == "T":
    grid = [0.55, 0.65, 0.75, 0.85, 0.95, 1.05, 1.15, 1.30, 1.50]
    print("T(cm/px in 640 canvas) sweep")
    for T in grid:
        print("-" * 100)
        for name, img, cmpx, truth in IMGS:
            s = cmpx / T
            f, err = run_one(img, cmpx, s)
            if err:
                print("  T=%.2f s=%.4f %-24s -> %s" % (T, s, name, err)); continue
            bad = domain_ok(f)
            pred = float(reg.run(None, {RIN: np.array([[f["RA"], f["LC"], f["BL"], f["BW"], f["E"]]], np.float32)})[0][0][0])
            print("  T=%.2f s=%.4f %-24s cands=%d conf=%.2f diag=%.2f RA=%.4f LC=%.0f BL=%.0f BW=%.0f E=%.3f -> %7.1f kg (true %.0f) %s"
                  % (T, s, name, f["cands"], f["conf"], f["diag"], f["RA"], f["LC"], f["BL"], f["BW"], f["E"], pred, truth,
                     "OUT:" + ",".join(bad) if bad else "IN-DOMAIN"))
