#!/usr/bin/env python3
"""本地假 MacCMS 采集站（M4 验收用，不联网）。

用法：python scripts/mock_maccms.py [端口] [素材目录]
默认端口 8765，素材目录取环境变量 YQK_MEDIA_DIR，未设置则用仓库根目录下的 media/
（放一个 sample.mkv 进去即可当片源）。

接口：
  /api.php/provide/vod/?ac=detail&wd=test   搜索 test，固定返回 3 条
  /api.php/provide/vod/?ac=detail&ids=1     详情
  /media/ep1.mkv /media/ep2.mkv             真素材（支持 Range）

手机侧要让 127.0.0.1:8765 指到电脑：adb reverse tcp:8765 tcp:8765
"""
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
MEDIA_DIR = (
    sys.argv[2]
    if len(sys.argv) > 2
    else os.environ.get("YQK_MEDIA_DIR")
    or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "media")
)

# 三条结果共用同一个素材，但集数/线路写成 MacCMS 的多层分隔格式：
# vod_play_from 用 $$$ 分线路，vod_play_url 用 # 分集，每集用 $ 分「名|地址」
MEDIA_FILES = ["sample.mkv", "sample.mkv", "sample.mkv"]


def _episodes(host: str, index: int) -> str:
    ep1 = f"http://{host}/media/ep{index}a.mkv"
    ep2 = f"http://{host}/media/ep{index}b.mkv"
    return f"第1集${ep1}#第2集${ep2}"


def build_payload(host: str):
    items = []
    for i in range(1, 4):
        items.append(
            {
                "vod_id": i,
                "vod_name": f"测试片{i} test sample",
                "vod_pic": f"http://{host}/pic/{i}.jpg",
                "vod_remarks": "已完结",
                "vod_year": "2024",
                "vod_area": "大陆",
                "vod_content": "本地假采集站，用于验收，不含任何真实片源。",
                "vod_play_from": "线路一$$$线路二",
                "vod_play_url": f"{_episodes(host, i)}$$$备份线路$http://example.invalid/x.m3u8",
            }
        )
    return {"code": 1, "msg": "数据列表", "page": 1, "pagecount": 1, "total": len(items), "list": items}


class Handler(BaseHTTPRequestHandler):
    server_version = "MockMacCMS/1.0"

    def log_message(self, fmt, *args):  # noqa: A003 - 保持标准签名
        sys.stderr.write("[mock] " + fmt % args + "\n")

    def _json(self, obj):
        import json

        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _media(self, name: str):
        path = os.path.join(MEDIA_DIR, "sample.mkv")
        if not os.path.isfile(path):
            self.send_error(404, "no media")
            return
        size = os.path.getsize(path)
        start, end = 0, size - 1
        rng = self.headers.get("Range")
        partial = False
        if rng:
            m = re.match(r"bytes=(\d*)-(\d*)", rng)
            if m:
                if m.group(1):
                    start = int(m.group(1))
                if m.group(2):
                    end = min(int(m.group(2)), size - 1)
                partial = True
        length = end - start + 1
        self.send_response(206 if partial else 200)
        self.send_header("Content-Type", "video/x-matroska")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(length))
        if partial:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        with open(path, "rb") as fh:
            fh.seek(start)
            left = length
            while left > 0:
                chunk = fh.read(min(65536, left))
                if not chunk:
                    break
                self.wfile.write(chunk)
                left -= len(chunk)

    def do_GET(self):  # noqa: N802 - 保持标准签名
        host = self.headers.get("Host") or f"127.0.0.1:{PORT}"
        path = self.path.split("?")[0]
        if path.startswith("/api.php"):
            self._json(build_payload(host))
            return
        if path.startswith("/media/"):
            self._media(path)
            return
        if path.startswith("/pic/"):
            self.send_error(404, "no pic")
            return
        self.send_error(404, "not found")


if __name__ == "__main__":
    srv = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"[mock] MacCMS on http://127.0.0.1:{PORT}/api.php/provide/vod/  media={MEDIA_DIR}")
    srv.serve_forever()
