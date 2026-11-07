"""画像本体と、multipartの付帯情報を含む受信上限を定義する。"""

MAX_DEMO_UPLOAD_BYTES = 20 * 1024 * 1024
# 境界文字列・ファイル名等の余白を確保し、本文全体にも上限を設ける。
MAX_DEMO_REQUEST_BYTES = MAX_DEMO_UPLOAD_BYTES + 64 * 1024
