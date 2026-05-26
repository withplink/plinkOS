#!/usr/bin/env python3
"""
Renders a status screen on the Inky Impression 7.3" display.
Usage:
  python3 show_hotspot_screen.py ap <password>   — show AP mode screen with QR code
  python3 show_hotspot_screen.py default         — show empty-queue placeholder screen
"""

import sys
from PIL import Image, ImageDraw, ImageFont

try:
    from inky.inky_e673 import Inky
    inky = Inky(resolution=(800, 480), colour="multi")
    W, H = inky.width, inky.height
except Exception:
    inky = None
    W, H = 800, 480  # fallback for testing

SSID = "plink-setup"
FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONT_BOLD_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def make_font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except Exception:
        return ImageFont.load_default()


def qr_image(data: str, box_size: int = 6) -> Image.Image:
    """Generate a QR code PIL image without external qrcode library.

    Falls back to the qrcode library if installed; otherwise renders
    a plain text fallback so the script never crashes.
    """
    try:
        import qrcode
        qr = qrcode.QRCode(box_size=box_size, border=2)
        qr.add_data(data)
        qr.make(fit=True)
        return qr.make_image(fill_color="black", back_color="white").convert("RGB")
    except ImportError:
        # Fallback: small grey placeholder square
        side = box_size * 20
        img = Image.new("RGB", (side, side), "white")
        ImageDraw.Draw(img).rectangle([4, 4, side - 4, side - 4], outline="black", width=2)
        return img


def draw_ap_screen(password: str) -> Image.Image:
    img = Image.new("RGB", (W, H), "white")
    draw = ImageDraw.Draw(img)

    font_title = make_font(FONT_BOLD_PATH, 38)
    font_label = make_font(FONT_BOLD_PATH, 20)
    font_value = make_font(FONT_PATH, 20)
    font_hint = make_font(FONT_PATH, 16)

    # Title
    draw.text((40, 36), "Connect to Frame", font=font_title, fill="black")
    draw.line([(40, 86), (W - 40, 86)], fill="#cccccc", width=1)

    # WiFi QR code — encodes the network join string iOS camera understands
    wifi_uri = f"WIFI:S:{SSID};T:WPA;P:{password};;"
    qr = qr_image(wifi_uri, box_size=7)
    qr_x, qr_y = 40, 106
    img.paste(qr, (qr_x, qr_y))
    qr_w, qr_h = qr.size

    # Instructions alongside the QR code
    text_x = qr_x + qr_w + 36
    y = qr_y

    draw.text((text_x, y), "1  Point your phone camera", font=font_label, fill="black")
    draw.text((text_x, y + 26), "   at the QR code", font=font_value, fill="#444444")
    y += 70

    draw.text((text_x, y), '2  Tap "Join Network"', font=font_label, fill="black")
    y += 56

    draw.text((text_x, y), "3  Open Plink app —", font=font_label, fill="black")
    draw.text((text_x, y + 26), "   frame appears automatically", font=font_value, fill="#444444")
    y += 70

    # Manual credentials (small, below instructions)
    draw.line([(text_x, y), (W - 40, y)], fill="#eeeeee", width=1)
    y += 14
    draw.text((text_x, y), "Network", font=font_label, fill="#888888")
    draw.text((text_x + 110, y), SSID, font=font_value, fill="black")
    y += 30
    draw.text((text_x, y), "Password", font=font_label, fill="#888888")
    draw.text((text_x + 110, y), password, font=font_value, fill="black")

    # Footer hint
    draw.text((40, H - 38), "Hold Button A again to return to normal WiFi mode",
              font=font_hint, fill="#aaaaaa")

    return img


DEFAULT_SCREEN_PATH = "/home/pi/PiInk/assets/default_screen.png"


def draw_default_screen() -> Image.Image:
    try:
        img = Image.open(DEFAULT_SCREEN_PATH).convert("RGB")
        img = img.resize((W, H), Image.LANCZOS)
        return img
    except Exception:
        pass
    img = Image.new("RGB", (W, H), "white")
    draw = ImageDraw.Draw(img)
    font_title = make_font(FONT_BOLD_PATH, 38)
    font_body = make_font(FONT_PATH, 22)
    draw.text((40, 36), "Ready", font=font_title, fill="black")
    draw.text((40, 100), "Open Plink and upload your first photo.", font=font_body, fill="#444444")
    return img


def show(img: Image.Image):
    try:
        if inky is None:
            raise RuntimeError("inky not initialised")
        inky.set_image(img)
        inky.show()
    except Exception as e:
        print(f"Display unavailable ({e}); saving preview to /tmp/plink_screen.png")
        img.save("/tmp/plink_screen.png")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "default"
    if mode == "ap":
        password = sys.argv[2] if len(sys.argv) > 2 else "plink123"
        show(draw_ap_screen(password))
    else:
        show(draw_default_screen())
