"""M6 第一段本地 mock：WebDAV(PROPFIND 207) + AList(fs/list, fs/get) + Emby(Auth, Items)。

用法：
    python scripts/m6_mock.py 8768

要点（都是真机容易翻车的地方，mock 必须覆盖）：
- WebDAV：第一条 response 是目录自己；resourcetype 空标签=文件；href 里中文是 %XX；文件名里有 `+`
- AList：`/api/fs/get` 对 a.mp4 给 raw_url，对 b.mp4 只给 url（走代理），对 c.mp4 两个都空
- Emby：把收到的 DeviceId 原样回显进 ServerId，并在 devices.log 里记一行，便于核对两次登录是否同设备
"""

import base64
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(os.path.dirname(ROOT), "test", "fixtures")
DEVICES_LOG = os.path.join(ROOT, "..", "..", "_m0_tmp", "m6_devices.log")

WEBDAV_XML = """<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/dav/</D:href>
    <D:propstat><D:prop><D:displayname>dav</D:displayname>
      <D:resourcetype><D:collection/></D:resourcetype>
      <D:getlastmodified>Mon, 01 Jan 2024 00:00:00 GMT</D:getlastmodified>
    </D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/movies/</D:href>
    <D:propstat><D:prop><D:displayname>movies</D:displayname>
      <D:resourcetype><D:collection/></D:resourcetype>
      <D:getlastmodified>Mon, 01 Jan 2024 10:00:00 GMT</D:getlastmodified>
    </D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/%E4%B8%AD%E6%96%87%20%E7%89%87%E5%90%8D.mp4</D:href>
    <D:propstat><D:prop><D:displayname>中文 片名.mp4</D:displayname>
      <D:getcontentlength>12345678</D:getcontentlength>
      <D:getcontenttype>video/mp4</D:getcontenttype>
      <D:getlastmodified>Tue, 02 Jan 2024 12:34:56 GMT</D:getlastmodified>
      <D:resourcetype/></D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/a%2Bb.mp4</D:href>
    <D:propstat><D:prop><D:displayname>a+b.mp4</D:displayname>
      <D:getcontentlength>2048</D:getcontentlength>
      <D:getcontenttype>video/mp4</D:getcontenttype>
      <D:resourcetype/></D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat>
  </D:response>
</D:multistatus>
"""

ALIST_LIST = {
    "code": 200,
    "message": "success",
    "data": {
        "content": [
            {"name": "电影", "size": 0, "is_dir": True, "modified": "2024-01-01T00:00:00Z"},
            {"name": "a.mp4", "size": 12345, "is_dir": False, "modified": "2024-01-03T00:00:00Z", "sign": "abc"},
            {"name": "中文 片名.mkv", "size": 734003200, "is_dir": False, "modified": "2024-01-03T10:20:30Z", "sign": "def"},
        ],
        "total": 3,
    },
}

ALIST_GET = {
    "/a.mp4": {"code": 200, "data": {"name": "a.mp4", "size": 12345,
                                      "raw_url": "https://cdn.example.com/a.mp4?auth_key=1759000000&sign=zzz",
                                      "url": "https://alist.example.com/p/a.mp4", "provider": "AliyundriveOpen"}},
    "/b.mp4": {"code": 200, "data": {"name": "b.mp4", "size": 999, "raw_url": "",
                                      "url": "https://alist.example.com/p/b.mp4", "provider": "Local"}},
    "/c.mp4": {"code": 200, "data": {"name": "c.mp4", "size": 1, "raw_url": "", "url": "", "provider": "WebDAV"}},
}

EMBY_ITEMS = {
    "Items": [
        {"Id": "series-1", "Name": "示例剧集", "Type": "Series", "ImageTags": {"Primary": "t1"}},
        {"Id": "movie-1", "Name": "示例电影", "Type": "Movie", "ProductionYear": 2020,
         "RunTimeTicks": 72000000000, "ImageTags": {"Primary": "t2"}},
        {"Id": "ep-1", "Name": "第 1 集", "Type": "Episode", "RunTimeTicks": 15000000000,
         "UserData": {"PlaybackPositionTicks": 350000000}},
    ],
    "TotalRecordCount": 3,
}


class H(BaseHTTPRequestHandler):
    server_version = "M6Mock/1.0"

    def _json(self, obj, code=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _xml(self, body):
        raw = body.encode("utf-8")
        self.send_response(207)
        self.send_header("Content-Type", "application/xml; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_PROPFIND(self):
        # PROPFIND 也带 body，不读干净再回包会被客户端当成「连接被掐断」
        n = int(self.headers.get("Content-Length") or 0)
        if n:
            self.rfile.read(n)
        auth = self.headers.get("Authorization", "")
        if not auth.startswith("Basic "):
            self._json({"error": "no auth"}, 401)
            return
        try:
            user, pwd = base64.b64decode(auth[6:]).decode("utf-8").split(":", 1)
        except Exception:
            self._json({"error": "bad auth"}, 401)
            return
        if not (user == "m6" and pwd == "m6pass"):
            self._json({"error": "bad credentials"}, 401)
            return
        self._xml(WEBDAV_XML)

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b"{}"
        try:
            body = json.loads(raw.decode("utf-8") or "{}")
        except Exception:
            body = {}

        if self.path == "/Users/AuthenticateByName":
            hdr = self.headers.get("X-Emby-Authorization", "")
            # 从 "DeviceId=\"xxx\"" 里取出设备号，回显到 ServerId 便于核对
            dev = ""
            for part in hdr.split(","):
                part = part.strip()
                if part.lower().startswith("deviceid="):
                    dev = part.split("=", 1)[1].strip().strip('"')
            if not hdr or not dev:
                self._json({"error": "missing X-Emby-Authorization"}, 400)
                return
            if body.get("Pw") != "m6pass":
                self._json({"error": "bad password"}, 401)
                return
            with open(DEVICES_LOG, "a", encoding="utf-8") as f:
                f.write(dev + "\n")
            self._json({
                "User": {"Id": "user-m6", "Name": body.get("Username", "demo"), "HasPassword": True},
                "AccessToken": "tok_" + dev[:8],
                "ServerId": "srv_" + dev,
            })
            return

        if self.path == "/api/fs/list":
            if self.headers.get("Authorization", "") not in ("m6token", "Bearer m6token"):
                self._json({"code": 401, "message": "guest user is disabled"}, 200)
                return
            self._json(ALIST_LIST)
            return

        if self.path == "/api/fs/get":
            if self.headers.get("Authorization", "") not in ("m6token", "Bearer m6token"):
                self._json({"code": 401, "message": "guest user is disabled"}, 200)
                return
            p = body.get("path", "")
            self._json(ALIST_GET.get(p, {"code": 500, "message": "not found"}))
            return

        self._json({"code": 404}, 404)

    def do_GET(self):
        if self.path.startswith("/Users/") and "/Items" in self.path:
            if not self.headers.get("X-Emby-Token"):
                self._json({"error": "no token"}, 401)
                return
            self._json(EMBY_ITEMS)
            return
        if self.path.startswith("/Videos/") and "/stream" in self.path:
            self._json({"error": "mock 不提供真视频"}, 204)
            return
        # WebDAV 取文件：给一段真视频字节，验收「点文件出画面」时才不是 404
        if self.path.startswith("/dav/"):
            self._serve_media()
            return
        self._json({"code": 404}, 404)

    def _serve_media(self):
        fp = os.path.join(ROOT, "..", "..", "_m0_tmp", "sample.mkv")
        if not os.path.isfile(fp):
            self._json({"error": "缺样本文件"}, 404)
            return
        size = os.path.getsize(fp)
        rng = self.headers.get("Range", "")
        start, end = 0, size - 1
        if rng.startswith("bytes="):
            a, _, b = rng[6:].partition("-")
            if a:
                start = int(a)
            if b:
                end = int(b)
        end = min(end, size - 1)
        if start > end:
            self.send_response(416)
            self.send_header("Content-Range", "bytes */%d" % size)
            self.end_headers()
            return
        length = end - start + 1
        self.send_response(206 if rng else 200)
        self.send_header("Content-Type", "video/mp4")
        self.send_header("Accept-Ranges", "bytes")
        if rng:
            self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, size))
        self.send_header("Content-Length", str(length))
        self.end_headers()
        with open(fp, "rb") as f:
            f.seek(start)
            self.wfile.write(f.read(length))

    def log_message(self, fmt, *args):
        return


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8768
    print("m6 mock listening on 127.0.0.1:%d" % port)
    ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
