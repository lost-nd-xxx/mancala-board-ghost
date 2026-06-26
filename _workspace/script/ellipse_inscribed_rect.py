"""
ellipse_inscribed_rect.py

PNG画像中の各色領域（楕円）に内接する最大面積長方形を求め、
座標と色情報をログファイルに書き出す。

前提：
  - 背景は (255, 255, 255)
  - 各楕円は単一色・塗りつぶし・重なりなし
  - 楕円は傾きなし（軸平行）だが手書きのため多少歪みあり
  - cv2 不使用 / pillow + numpy のみ
"""

import sys
import numpy as np
from PIL import Image
from datetime import datetime


# ------------------------------------------------------------------ #
# 設定
# ------------------------------------------------------------------ #
INPUT_IMAGE = "input.png"          # 入力画像パス（引数で上書き可）
OUTPUT_LOG  = "ellipse_rects.log"  # 出力ログパス（引数で上書き可）


# ------------------------------------------------------------------ #
# 楕円フィット：主軸平行を仮定した最小二乗楕円フィット
# ------------------------------------------------------------------ #
def fit_ellipse_axis_aligned(ys, xs):
    """
    ピクセル群 (xs, ys) に対し軸平行楕円をフィット。
    x^2/a^2 + y^2/b^2 = 1 の形で (cx, cy, a, b) を返す。
    a: 水平半径, b: 垂直半径
    """
    cx = (xs.max() + xs.min()) / 2.0
    cy = (ys.max() + ys.min()) / 2.0

    # 中心を原点に移動
    xc = xs - cx
    yc = ys - cy

    # 最小二乗: A*x^2 + B*y^2 = 1
    # → [x^2, y^2] * [A, B]^T = 1
    X = np.column_stack([xc**2, yc**2])
    ones = np.ones(len(xc))
    # 最小二乗解
    result, _, _, _ = np.linalg.lstsq(X, ones, rcond=None)
    A, B = result

    a = 1.0 / np.sqrt(max(A, 1e-12))   # 水平半径
    b = 1.0 / np.sqrt(max(B, 1e-12))   # 垂直半径

    return cx, cy, a, b


# ------------------------------------------------------------------ #
# 軸平行楕円に内接する最大面積長方形
# ------------------------------------------------------------------ #
def max_inscribed_rect_in_ellipse(cx, cy, a, b):
    """
    軸平行楕円 (cx,cy,a,b) に内接する最大面積の軸平行長方形。
    解析解: w = a*sqrt(2), h = b*sqrt(2)  (面積 = 2ab)
    左上・右下の整数座標を返す。
    """
    half_w = a / np.sqrt(2)
    half_h = b / np.sqrt(2)

    x1 = int(np.floor(cx - half_w))
    y1 = int(np.floor(cy - half_h))
    x2 = int(np.ceil(cx + half_w))
    y2 = int(np.ceil(cy + half_h))

    width  = x2 - x1
    height = y2 - y1

    return (x1, y1), (x2, y2), width, height


# ------------------------------------------------------------------ #
# メイン処理
# ------------------------------------------------------------------ #
def process(input_path, output_path):
    img = Image.open(input_path).convert("RGB")
    arr = np.array(img)

    H, W, _ = arr.shape
    bg = np.array([255, 255, 255], dtype=np.uint8)

    # 背景マスク（True = 背景）
    bg_mask = np.all(arr == bg, axis=2)

    # 非背景ピクセルの全座標
    fg_ys, fg_xs = np.where(~bg_mask)

    if len(fg_ys) == 0:
        print("非背景ピクセルが見つかりません。")
        return

    # 色ごとにグループ化
    fg_colors = arr[fg_ys, fg_xs]                       # shape (N, 3)
    unique_colors = np.unique(fg_colors, axis=0)         # shape (M, 3)

    results = []

    for color in unique_colors:
        mask = np.all(fg_colors == color, axis=1)
        ys = fg_ys[mask]
        xs = fg_xs[mask]

        if len(xs) < 5:
            # フィットに必要な点が足りない場合はスキップ
            continue

        rgb = tuple(int(c) for c in color)

        # 楕円フィット
        cx, cy, a, b = fit_ellipse_axis_aligned(ys, xs)

        # 内接最大長方形
        (x1, y1), (x2, y2), w, h = max_inscribed_rect_in_ellipse(cx, cy, a, b)

        # 画像範囲クリップ
        x1c = max(0, x1); y1c = max(0, y1)
        x2c = min(W, x2); y2c = min(H, y2)

        area = (x2c - x1c) * (y2c - y1c)

        results.append({
            "rgb":    rgb,
            "center": (round(cx, 2), round(cy, 2)),
            "semi_axes": (round(a, 2), round(b, 2)),
            "top_left":  (x1c, y1c),
            "bot_right": (x2c, y2c),
            "width":  x2c - x1c,
            "height": y2c - y1c,
            "area":   area,
            "pixel_count": int(len(xs)),
        })

    # y座標（上から順）でソート
    results.sort(key=lambda r: r["top_left"][1])

    # ログ書き出し
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    lines = []
    lines.append(f"# ellipse_inscribed_rect.py  {now}")
    lines.append(f"# input : {input_path}")
    lines.append(f"# image size : {W} x {H} px")
    lines.append(f"# detected ellipses : {len(results)}")
    lines.append("")
    lines.append(
        f"{'No':>3}  {'RGB':>20}  {'Center':>18}  "
        f"{'SemiAxes(a,b)':>18}  {'TopLeft':>14}  {'BotRight':>14}  "
        f"{'W':>5}  {'H':>5}  {'Area':>8}  {'Pixels':>7}"
    )
    lines.append("-" * 120)

    for i, r in enumerate(results, 1):
        rgb_str   = "({:3d},{:3d},{:3d})".format(*r["rgb"])
        cen_str   = "({:.1f},{:.1f})".format(*r["center"])
        axes_str  = "({:.1f},{:.1f})".format(*r["semi_axes"])
        tl_str    = "({:4d},{:4d})".format(*r["top_left"])
        br_str    = "({:4d},{:4d})".format(*r["bot_right"])
        lines.append(
            f"{i:>3}  {rgb_str:>20}  {cen_str:>18}  "
            f"{axes_str:>18}  {tl_str:>14}  {br_str:>14}  "
            f"{r['width']:>5}  {r['height']:>5}  {r['area']:>8}  {r['pixel_count']:>7}"
        )

    log_text = "\n".join(lines) + "\n"

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(log_text)

    print(log_text)
    print(f"→ ログを書き出しました: {output_path}")


# ------------------------------------------------------------------ #
# エントリポイント
# ------------------------------------------------------------------ #
if __name__ == "__main__":
    inp = sys.argv[1] if len(sys.argv) > 1 else INPUT_IMAGE
    out = sys.argv[2] if len(sys.argv) > 2 else OUTPUT_LOG
    process(inp, out)
