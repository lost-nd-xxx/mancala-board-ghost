"""
透過情報付き32bit PNG画像をHSV色相シフトして48枚生成するスクリプト。
色相を7.5°刻みで0°〜352.5°の48種類作成します。

使い方:
    1. このスクリプトを input.png と同じフォルダに置く
    2. python hue_shift.py を実行
    3. output/ フォルダに image_00.png 〜 image_47.png が生成される
"""

from pathlib import Path
import numpy as np
from PIL import Image


def shift_hue(image: Image.Image, degrees: float) -> Image.Image:
    """RGBAのPIL画像の色相をdegrees度シフトして返す。アルファチャンネルはそのまま保持。"""
    # RGBA に統一
    img = image.convert("RGBA")
    r, g, b, a = img.split()

    # RGB部分をHSVに変換（numpy利用）
    rgb = np.array(img.convert("RGB"), dtype=np.float32) / 255.0  # shape: (H, W, 3)

    r_ch = rgb[:, :, 0]
    g_ch = rgb[:, :, 1]
    b_ch = rgb[:, :, 2]

    c_max = rgb.max(axis=2)
    c_min = rgb.min(axis=2)
    delta = c_max - c_min

    # Hue 計算
    hue = np.zeros_like(c_max)
    mask = delta != 0

    # R が最大
    m = mask & (c_max == r_ch)
    hue[m] = (60 * ((g_ch[m] - b_ch[m]) / delta[m])) % 360

    # G が最大
    m = mask & (c_max == g_ch)
    hue[m] = 60 * ((b_ch[m] - r_ch[m]) / delta[m]) + 120

    # B が最大
    m = mask & (c_max == b_ch)
    hue[m] = 60 * ((r_ch[m] - g_ch[m]) / delta[m]) + 240

    # Saturation
    sat = np.where(c_max == 0, 0.0, delta / c_max)

    # Value
    val = c_max

    # 色相シフト
    hue = (hue + degrees) % 360

    # HSV → RGB に戻す
    h_i = (hue / 60).astype(int) % 6
    f = hue / 60 - np.floor(hue / 60)
    p = val * (1 - sat)
    q = val * (1 - f * sat)
    t = val * (1 - (1 - f) * sat)

    new_r = np.select(
        [h_i == 0, h_i == 1, h_i == 2, h_i == 3, h_i == 4, h_i == 5],
        [val, q, p, p, t, val],
    )
    new_g = np.select(
        [h_i == 0, h_i == 1, h_i == 2, h_i == 3, h_i == 4, h_i == 5],
        [t, val, val, q, p, p],
    )
    new_b = np.select(
        [h_i == 0, h_i == 1, h_i == 2, h_i == 3, h_i == 4, h_i == 5],
        [p, p, t, val, val, q],
    )

    # 無彩色（sat==0）はそのまま
    new_r = np.where(sat == 0, val, new_r)
    new_g = np.where(sat == 0, val, new_g)
    new_b = np.where(sat == 0, val, new_b)

    rgb_shifted = np.stack(
        [new_r, new_g, new_b], axis=2
    )
    rgb_shifted = np.clip(rgb_shifted * 255, 0, 255).astype(np.uint8)

    # アルファチャンネルを合成して返す
    result = Image.fromarray(rgb_shifted, mode="RGB")
    result.putalpha(a)
    return result


def main():
    input_path = Path("input.png")
    output_dir = Path("output")
    output_dir.mkdir(exist_ok=True)

    if not input_path.exists():
        print(f"エラー: {input_path} が見つかりません。")
        return

    src = Image.open(input_path)
    print(f"入力画像: {input_path}  サイズ: {src.size}  モード: {src.mode}")

    total = 48
    step = 360 / total  # 7.5°

    for i in range(total):
        degrees = step * i
        shifted = shift_hue(src, degrees)
        out_path = output_dir / f"image_{i:02d}.png"
        shifted.save(out_path, format="PNG")
        print(f"  [{i+1:2d}/{total}] {out_path}  (色相 +{degrees:.1f}°)")

    print(f"\n完了: {output_dir}/ に {total} 枚生成しました。")


if __name__ == "__main__":
    main()
