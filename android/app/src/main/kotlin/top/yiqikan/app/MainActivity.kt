package top.yiqikan.app

import android.app.ActivityManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.util.Log
import android.util.Rational
import androidx.annotation.RequiresApi
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 画中画通道实现。
 * 契约来自旧 APK 反汇编（classes2.dex 的 zc/q.smali、原版 MainActivity.smali）：
 *   MethodChannel "top.yiqikan/pip_control"：
 *     enterPipMode(width,height) / setAutoEnterPipEnabled(enabled) /
 *     setPipInPlayerPage(inPlayerPage) / updatePipActions(action,playing) / isPipSupported
 *   EventChannel "top.yiqikan/pip"：PIP 状态与按钮事件
 *   广播 action：top.yiqikan.pip.PLAY_PAUSE / FORWARD / REWIND
 */
class MainActivity : FlutterActivity() {

    /** Dart 侧注册 handler 之后才非空；之前收到的链接先存 [deepLinkPending]。 */
    private var deepLinkChannel: MethodChannel? = null
    private var deepLinkPending: String? = null

    /**
     * 深链：yiqikan://play?url=... -> 路由 /play?url=...
     *
     * 静态入口只处理 play / sniff；房间链接不走这里（见 isRoomLink / deliverDeepLink），
     * 因为建房/进房要带 pwd，且进房失败要按来源给不同文案，路由层拿不到这些上下文。
     * 返回 null 表示走默认路由（首页）。
     */
    private fun deepLinkRoute(intent: Intent?): String? {
        val data = intent?.data ?: return null
        if (data.scheme != "yiqikan") return null
        // 只放行明确登记过的 host，避免随便一个链接就把用户带进某个页面
        val path = when (data.host) {
            "play" -> "/play"
            "sniff" -> "/sniff"
            // yiqikan://room/{code} —— 交给 MethodChannel，别在这里拼路由
            "room" -> return null
            // 验收用：真机对着屏幕扫不方便，debug 包里允许直接喂一张图给扫码页
            "scan" -> if (isDebuggable()) "/scan" else return null
            else -> return null
        }
        val query = intent.dataString?.substringAfter('?', "") ?: ""
        return if (query.isEmpty()) path else "$path?$query"
    }

    /** debug 包才有的入口（扫码喂图这类验收辅助）走这个判断。 */
    private fun isDebuggable(): Boolean =
        (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0

    /** 房间链接：yiqikan://room/{code} 与 https://{host}/r/{code}（分享短链）。 */
    private fun isRoomLink(data: Uri?): Boolean {
        if (data == null) return false
        if (data.scheme == "yiqikan") return data.host == "room"
        val s = data.scheme?.lowercase() ?: return false
        if (s != "http" && s != "https") return false
        val seg = data.pathSegments ?: return false
        return seg.size >= 2 && seg[0].equals("r", ignoreCase = true)
    }

    /** 把房间链接丢给 Dart；Dart 侧还没注册 handler 时先存着，等它来取。 */
    private fun deliverDeepLink(url: String) {
        Log.i(TAG_LINK, "[YQK-LINK] deliver url=$url")
        val ch = deepLinkChannel
        if (ch == null) {
            deepLinkPending = url
            Log.i(TAG_LINK, "[YQK-LINK] channel not ready, pending")
            return
        }
        ch.invokeMethod("onDeepLink", url, null)
    }

    override fun getInitialRoute(): String? = deepLinkRoute(intent)

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // singleTask 下再次唤起不会重建 Activity：房间链接走 channel（可能带 pwd，
        // 也可能指到另一个房间，需要先关掉旧房），其余静态深链继续推路由。
        if (isRoomLink(intent.data)) {
            intent.dataString?.let { deliverDeepLink(it) }
            return
        }
        val route = deepLinkRoute(intent) ?: return
        flutterEngine?.navigationChannel?.pushRoute(route)
    }

    private var eventSink: EventChannel.EventSink? = null
    private var autoEnter = true
    private var inPlayerPage = false
    private var playing = false
    private var width = 16
    private var height = 9

    private val pipReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                ACTION_PLAY_PAUSE -> eventSink?.success(mapOf("action" to "play_pause", "playing" to !playing))
                ACTION_FORWARD -> eventSink?.success(mapOf("action" to "forward"))
                ACTION_REWIND -> eventSink?.success(mapOf("action" to "rewind"))
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, "top.yiqikan/pip").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                }

                override fun onCancel(args: Any?) {
                    eventSink = null
                }
            }
        )

        // 深链进房：Dart 启动时调 getInitialLink 取冷启动那条，之后靠 onDeepLink 回调
        val linkChannel = MethodChannel(messenger, CHANNEL_LINK)
        deepLinkChannel = linkChannel
        linkChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialLink" -> {
                    // 冷启动：优先用 onNewIntent 期间攒下的那条，否则读当前 intent
                    val pending = deepLinkPending
                    deepLinkPending = null
                    val url = pending ?: intent?.dataString?.takeIf { isRoomLink(intent.data) }
                    Log.i(TAG_LINK, "[YQK-LINK] getInitialLink -> $url")
                    result.success(url)
                }
                "ready" -> result.success(true)
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "top.yiqikan/pip_control").setMethodCallHandler { call, result ->
            when (call.method) {
                "isPipSupported" ->
                    result.success(packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE))
                "enterPipMode" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                        result.error("UNAVAILABLE", "画中画模式需要 Android 8.0 或更高版本", null)
                    } else {
                        width = (call.argument<Int>("width") ?: 16).coerceAtLeast(1)
                        height = (call.argument<Int>("height") ?: 9).coerceAtLeast(1)
                        if (enterPip()) result.success(true)
                        else result.error("PIP_ERROR", "进入画中画模式失败", null)
                    }
                }
                "setAutoEnterPipEnabled" -> {
                    autoEnter = call.argument<Boolean>("enabled") ?: true
                    result.success(null)
                }
                "setPipInPlayerPage" -> {
                    inPlayerPage = call.argument<Boolean>("inPlayerPage") ?: false
                    result.success(null)
                }
                "updatePipActions" -> {
                    playing = call.argument<Boolean>("playing") ?: playing
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) updatePipParams()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // 探针：验证 Java 源集与 TVBox 兼容层（P-1 / P0a / P0b / P0c），只打日志
        MethodChannel(messenger, "yiqikan/probe").setMethodCallHandler { call, result ->
            when (call.method) {
                "ping" -> result.success(top.yiqikan.app.probe.Hello.ping())
                "loadSpider" -> result.success(top.yiqikan.app.probe.Hello.loadSpider())
                "newAlist" -> result.success(top.yiqikan.app.probe.Hello.newAlist())
                "spiderApiGetAddress" -> result.success(
                    com.github.catvod.crawler.SpiderApi().getAddress(true)
                )
                // P0c 统计轮：148 个 type=3 里 113 个 csp 源顺序跑一遍（工作线程，源 10s 超时）
                "tvboxBatch" -> Thread({
                    val r = try {
                        top.yiqikan.app.server.TvboxBatch.runAll(applicationContext)
                    } catch (t: Throwable) {
                        "ERR " + t.javaClass.simpleName + ": " + (t.message ?: "")
                    }
                    android.os.Handler(mainLooper).post { result.success(r) }
                }, "yqk-tvbox-batch").start()
                "netGet" -> result.success(top.yiqikan.app.probe.Hello.netGet("https://www.hdmoli.me/"))
                // P3：QuickJS 能不能跑。QuickJS 非线程安全，必须整段在同一个工作线程里跑。
                // 用 FongMi 的配对件：wrapper-java.jar（com.fongmi.quickjs）+ libquickjs-wrapper.so。
                // 每步之间单独打日志，崩了就知道崩在哪一句。
                "quickjsPing" -> Thread({
                    val sb = StringBuilder()
                    var ctx: com.fongmi.quickjs.QuickJSContext? = null
                    try {
                        // 先把 native 库显式 load 进来：QuickJS 类里的 loadLibrary 藏在构造路径里，
                        // 静态入口（bootstrapThread0）会先于它触发 JNI 查找
                        try {
                            System.loadLibrary("quickjs-wrapper")
                            android.util.Log.i(TAG_QJS, "[YQK-QJS] loadLibrary quickjs-wrapper = ok")
                            sb.append("loadLibrary = ok\n")
                        } catch (t: Throwable) {
                            android.util.Log.i(TAG_QJS, "[YQK-QJS] loadLibrary failed: ${t.javaClass.simpleName} / ${t.message}")
                            sb.append("loadLibrary failed: ").append(t.javaClass.simpleName).append(" / ").append(t.message ?: "").append('\n')
                        }
                        android.util.Log.i(TAG_QJS, "[YQK-QJS] step=1 create")
                        val pss0 = android.os.Debug.getPss()
                        val c = com.fongmi.quickjs.QuickJSContext.create()
                        ctx = c
                        c.setMaxStackSize(1024 * 1024)
                        sb.append("create = ok\n")

                        val r = c.evaluate("1 + 2")
                        android.util.Log.i(TAG_QJS, "[YQK-QJS] eval 1+2 = $r")
                        sb.append("eval 1+2 = ").append(r).append('\n')

                        val obj = c.evaluate("JSON.stringify({a:1,b:[2,3]})")
                        android.util.Log.i(TAG_QJS, "[YQK-QJS] eval json = $obj")
                        sb.append("eval json = ").append(obj).append('\n')

                        val fn = c.evaluate("(function(x){ return x * 2; })")
                        val called = (fn as com.fongmi.quickjs.JSFunction).call(21)
                        android.util.Log.i(TAG_QJS, "[YQK-QJS] fn(21) = $called")
                        sb.append("fn(21) = ").append(called).append('\n')

                        try {
                            val t1 = c.evaluate("throw new Error('boom')")
                            android.util.Log.i(TAG_QJS, "[YQK-QJS] eval throw = no-exception?! $t1")
                            sb.append("eval throw = no-exception?! ").append(t1).append('\n')
                        } catch (e: Throwable) {
                            android.util.Log.i(TAG_QJS, "[YQK-QJS] eval throw caught: ${e.javaClass.simpleName} / ${e.message}")
                            sb.append("eval throw caught: ").append(e.javaClass.simpleName).append(" / ").append(e.message ?: "").append('\n')
                        }

                        var i = 0
                        while (i < 100) {
                            c.evaluate("" + i + " + 1")
                            i++
                        }
                        android.util.Log.i(TAG_QJS, "[YQK-QJS] loop100 = ok")
                        sb.append("loop100 = ok\n")

                        android.util.Log.i(TAG_QJS, "[YQK-QJS] step=9 destroy")
                        c.destroy()
                        ctx = null
                        android.util.Log.i(TAG_QJS, "[YQK-QJS] destroy = ok")
                        sb.append("destroy = ok\n")
                        val pss1 = android.os.Debug.getPss()
                        android.util.Log.i(TAG_QJS, "[YQK-QJS] pss before=${pss0}KB after=${pss1}KB delta=${pss1 - pss0}KB")
                        sb.append("pss delta = ").append(pss1 - pss0).append("KB\n")
                    } catch (t: Throwable) {
                        sb.append("FATAL ").append(t.javaClass.name).append(": ").append(t.message ?: "").append('\n')
                        android.util.Log.i(TAG_QJS, "[YQK-QJS] FATAL " + t.javaClass.name + ": " + (t.message ?: ""))
                        try { ctx?.destroy() } catch (ignored: Throwable) {}
                    }
                    val out = sb.toString()
                    android.os.Handler(mainLooper).post { result.success(out) }
                }, "yqk-quickjs").start()
                // P3 第三步：drpy2 完整链（encoding → performance → console → 宿主六个全局 → module → DRPY.init/home）。
                // 六个全局全部假实现（不接 HTTP / JSoup），只验链路能不能走到 home() 并返回 JSON。
                "drpy2Probe" -> Thread({
                    val sb = StringBuilder()
                    var ctx: com.fongmi.quickjs.QuickJSContext? = null
                    fun log(line: String) {
                        android.util.Log.i(TAG_QJS, "[YQK-DRPY] $line")
                        sb.append(line).append('\n')
                    }
                    try {
                        System.loadLibrary("quickjs-wrapper")
                        val t0 = System.currentTimeMillis()
                        val encJs = assets.open("tvbox/encoding.js").bufferedReader().use { it.readText() }
                        val consoleJs = assets.open("tvbox/console.js").bufferedReader().use { it.readText() }
                        val coreJs = assets.open("tvbox/drpy-core-lite.min.js").bufferedReader().use { it.readText() }
                        val engineJs = assets.open("tvbox/drpy2.min.js").bufferedReader().use { it.readText() }
                        log("read enc=${encJs.length} console=${consoleJs.length} core=${coreJs.length} engine=${engineJs.length} readMs=${System.currentTimeMillis() - t0}")

                        val c = com.fongmi.quickjs.QuickJSContext.create()
                        ctx = c
                        c.setMaxStackSize(1024 * 1024)
                        c.setMemoryLimit(256 * 1024 * 1024)
                        val heap0 = try { c.getMemoryUsedSize() } catch (t: Throwable) { -1L }

                        fun step(name: String, body: () -> Unit) {
                            val s = System.currentTimeMillis()
                            try { body(); log("$name ok ms=${System.currentTimeMillis() - s}") }
                            catch (t: Throwable) { log("$name err ${t.javaClass.name}: ${t.message ?: ""}") }
                        }

                        // 1) encoding.js —— TextEncoder / TextDecoder
                        step("enc") { c.evaluate(encJs) }
                        // 2) performance —— console.js 要 performance.now
                        step("perf") { c.evaluate("globalThis.performance = { now: function(){ return Date.now(); } };") }
                        // 3) console.js
                        step("console") { c.evaluate(consoleJs) }
                        // 4) 宿主六个全局（全假实现）
                        val hostJs = """
                            globalThis.CATE_EXCLUDE = '';
                            globalThis.TAB_EXCLUDE = '';
                            globalThis.模板 = { getMubans: function(){ return {}; } };
                            globalThis.req = function(url, obj){
                              return '{"code":1,"msg":"mock","list":[{"vod_id":"m1","vod_name":"假片子","vod_pic":"","vod_remarks":"mock"}]}';
                            };
                            globalThis.req2 = globalThis.req;
                            // drpy2 顶层会直接引用 pdfl / pdfh，宿主必须提供（全假实现）
                            globalThis.pdfl = function(html, rule, base){ return []; };
                            globalThis.pdfh = function(html, rule){ return ''; };
                            globalThis.pdfa = function(html, rule){ return []; };
                            globalThis.pd = function(html, rule, base){ return ''; };
                            // console.js 的 log 最终写 stdout/stderr，宿主提供最小实现
                            globalThis.stdout = { write: function(s){ return s; } };
                            globalThis.stderr = { write: function(s){ return s; } };
                            // console.js 的 print 依赖宿主 stdout，这里直接把 console 覆盖成静默实现
                            globalThis.console = {
                              log: function(){}, info: function(){}, warn: function(){}, error: function(){},
                              debug: function(){}, trace: function(){}, time: function(){}, timeEnd: function(){}
                            };
                            globalThis.parseTags = {
                              getParse: function(tag){
                                return {
                                  pdfa: function(html, rule){ return []; },
                                  pdfh: function(html, rule){ return ''; },
                                  pd:    function(html, rule, base){ return ''; }
                                };
                              }
                            };
                            'host-ready'
                        """.trimIndent()
                        step("host") {
                            val hr = c.evaluate(hostJs)
                            log("host value=$hr")
                        }

                        // 4b) 真宿主：把 Java 方法绑成 JS 函数（JSCallFunction），覆盖上一步的假实现
                        fun jsStr(a: Array<out Any?>, i: Int): String = a.getOrNull(i)?.toString() ?: ""
                        step("bind") {
                            val g = c.getGlobalObject()
                            val fnReq = object : com.fongmi.quickjs.JSCallFunction {
                                override fun call(vararg args: Any?): Any? = DrpyHost.req(jsStr(args, 0), jsStr(args, 1))
                            }
                            g.setProperty("req", fnReq)
                            g.setProperty("req2", fnReq)
                            val fnPdfh = object : com.fongmi.quickjs.JSCallFunction {
                                override fun call(vararg args: Any?): Any? = DrpyHost.pdfh(jsStr(args, 0), jsStr(args, 1))
                            }
                            val fnPdfa = object : com.fongmi.quickjs.JSCallFunction {
                                override fun call(vararg args: Any?): Any? = DrpyHost.pdfa(jsStr(args, 0), jsStr(args, 1))
                            }
                            val fnPd = object : com.fongmi.quickjs.JSCallFunction {
                                override fun call(vararg args: Any?): Any? = DrpyHost.pd(jsStr(args, 0), jsStr(args, 1), jsStr(args, 2))
                            }
                            g.setProperty("pdfh", fnPdfh)
                            g.setProperty("pdfa", fnPdfa)
                            g.setProperty("pd", fnPd)
                            val tags = c.evaluate("({})") as com.fongmi.quickjs.JSObject
                            tags.setProperty("getParse", object : com.fongmi.quickjs.JSCallFunction {
                                override fun call(vararg args: Any?): Any? {
                                    val o = c.evaluate("({})") as com.fongmi.quickjs.JSObject
                                    o.setProperty("pdfa", fnPdfa)
                                    o.setProperty("pdfh", fnPdfh)
                                    o.setProperty("pd", fnPd)
                                    return o
                                }
                            })
                            g.setProperty("parseTags", tags)
                            g.setProperty("__setBase", object : com.fongmi.quickjs.JSCallFunction {
                                override fun call(vararg args: Any?): Any? {
                                    DrpyHost.base = jsStr(args, 0)
                                    return DrpyHost.base
                                }
                            })
                            log("bind ok req/pdfh/pdfa/pd/parseTags")
                        }

                        // 4c) V1–V4：四个 Java 方法单独验
                        step("selftest") {
                            val t = System.currentTimeMillis()
                            val html = "<html><body><div class=\"myui-vodlist__box\"><a class=\"myui-vodlist__thumb\" title=\"流浪地球\" href=\"/movie/index1477.html\">x</a></div></body></html>"
                            val r1 = DrpyHost.req("https://www.hdmoli.me", "")
                            log("V1 req len=${r1.length} ms=${System.currentTimeMillis() - t}")
                            val r2 = DrpyHost.pdfh(html, ".myui-vodlist__thumb@title")
                            log("V2 pdfh = $r2")
                            val r3 = DrpyHost.pdfa(html, ".myui-vodlist__box")
                            log("V3 pdfa len=${r3.length} head=${r3.take(80)}")
                            val r4 = DrpyHost.pd("{\"a\":{\"b\":[{\"c\":\"x\"}]}}", "\$.a.b[0].c", "")
                            log("V4 pd = $r4")
                        }

                        // 5) 全 script 模式：core 与 engine 的 import/export 已在 asset 里改写成 globalThis 赋值
                        step("core") {
                            val t = System.currentTimeMillis()
                            c.evaluate(coreJs)
                            log("core ms=${System.currentTimeMillis() - t} = " + c.evaluate("typeof globalThis.__core"))
                            log("core keys = " + c.evaluate("Object.keys(globalThis.__core||{}).length"))
                        }
                        step("engine") {
                            val t = System.currentTimeMillis()
                            c.evaluate(engineJs)
                            log("engine ok ms=${System.currentTimeMillis() - t}")
                        }
                        // 6) 引擎尾部把导出挂到 globalThis.__drpyExport
                        step("export") {
                            log("typeof __drpyExport = " + c.evaluate("typeof globalThis.__drpyExport"))
                            log("keys = " + c.evaluate("Object.keys(globalThis.__drpyExport||{}).length"))
                            log("DRPY = " + c.evaluate("typeof (globalThis.__drpyExport||{}).DRPY"))
                        }
                        // 7) 整条链在 JS 侧跑完，不跨 JNI 取属性
                        step("drive") {
                            val rule = assets.open("tvbox/rules/360影视.js").bufferedReader().use { it.readText() }
                            c.getGlobalObject().setProperty("__ruleSrc", rule)
                            log("rule src len=${rule.length} head=${rule.take(40).replace('\n', ' ')}")
                            val drv = """
                                (function(){
                                  var out = { step: 'start' };
                                  try {
                                    var E = globalThis.__drpyExport;
                                    out.step = 'ctor';
                                    var d = E.DRPY();
                                    out.step = 'init';
                                    d.init(globalThis.__ruleSrc);
                                    out.step = 'rule';
                                    out.url = String((d.getRule ? d.getRule('url') : '') || '');
                                    if (typeof globalThis.__setBase === 'function') {
                                      globalThis.__setBase(String((d.getRule ? d.getRule('host') : '') || ''));
                                    }
                                    out.base = String(globalThis.__hostEcho || '');
                                    out.step = 'home';
                                    var h = d.home(false, '', '');
                                    out.homeN = (JSON.parse(h || '{}').class || []).length;
                                    out.home = String(h).slice(0, 300);
                                    out.step = 'search';
                                    out.tSearchFn = typeof d.search;
                                    // A：五个诊断值（先打出来，再谈怎么修）
                                    out.dSearchUrl = JSON.stringify(d.getRule ? d.getRule('searchUrl') : '');
                                    out.dSou = JSON.stringify(d.getRule ? d.getRule('搜索') : '');
                                    out.dYi = JSON.stringify(d.getRule ? d.getRule('一级') : '');
                                    out.dHeaders = typeof (d.getRule ? d.getRule('headers') : undefined);
                                    out.dGetItem = typeof getItem;
                                    out.step = 'search';
                                    try {
                                      var s = d.search('流浪地球', false, 1);
                                      var ss = JSON.parse(s || '{}');
                                      out.searchN = (ss.list || []).length;
                                      out.search = String(s).slice(0, 300);
                                      if (out.searchN > 0) {
                                        out.vname = String(ss.list[0].vod_name || '');
                                        out.vid = String(ss.list[0].vod_id || '');
                                      }
                                    } catch (e) {
                                      out.searchErr = (e && e.message) ? String(e.message) : String(e);
                                    }
                                    out.step = 'category';
                                    var cat = d.category('movie', 1, false, {});
                                    var cc = JSON.parse(cat || '{}');
                                    var cl = cc.list || [];
                                    out.catN = cl.length;
                                    out.catHead = String(cat).slice(0, 200);
                                    if (cl.length > 0) {
                                      out.vid = String(cl[0].vod_id || '');
                                      out.vname = String(cl[0].vod_name || '');
                                      out.step = 'detail2';
                                      var det = d.detail(out.vid);
                                      var dd = JSON.parse(det || '{}');
                                      var dl = (dd.list || [])[0] || {};
                                      out.from = String(dl.vod_play_from || '').slice(0, 200);
                                      out.playUrlRaw = String(dl.vod_play_url || '').slice(0, 200);
                                      var line0 = String(dl.vod_play_url || '').split('#')[0] || '';
                                      out.ep1 = line0.slice(0, 120);
                                      out.step = 'play';
                                      var flag = String(dl.vod_play_from || '').split('$$$')[0] || '';
                                      var pid = (line0.split('$')[1] || '').split('#')[0] || '';
                                      out.flag = flag;
                                      out.pid = pid;
                                      var pl = d.play(flag, pid);
                                      var pp = JSON.parse(pl || '{}');
                                      out.playUrl = String(pp.url || '').slice(0, 160);
                                      out.playHead = String(pl).slice(0, 200);
                                    }
                                    out.step = 'done';
                                  } catch (e) {
                                    out.err = (e && e.stack) ? String(e.stack).slice(0, 400) : String(e);
                                  }
                                  return JSON.stringify(out);
                                })()
                            """.trimIndent()
                            val t7 = System.currentTimeMillis()
                            log("drive ms=${System.currentTimeMillis() - t7} = " + c.evaluate(drv))
                        }

                        val heap1 = try { c.getMemoryUsedSize() } catch (t: Throwable) { -1L }
                        log("heap used before=${heap0}B after=${heap1}B used=${heap1 - heap0}B peakUsed=$heap1")

                        c.destroy()
                        ctx = null
                        log("destroy ok totalMs=${System.currentTimeMillis() - t0}")
                    } catch (t: Throwable) {
                        log("FATAL ${t.javaClass.name}: ${t.message ?: ""}")
                        try { ctx?.destroy() } catch (ignored: Throwable) {}
                    }
                    val out = sb.toString()
                    android.os.Handler(mainLooper).post { result.success(out) }
                }, "yqk-drpy2").start()
                // P0c：DexClassLoader 加载外部 spider.jar。Handler(mainLooper) 保证整段在主线程跑
                "probeJar" -> top.yiqikan.app.probe.Hello.probeJar(
                    applicationContext,
                    "/sdcard/Android/data/top.yiqikan.app.debug/cache/spider.jar",
                    "com.github.catvod.spider.App99",
                    "流浪地球",
                    android.os.Handler(mainLooper),
                ) { r -> result.success(r) }
                "probeJarBg" -> top.yiqikan.app.probe.Hello.probeJarBg(
                    applicationContext,
                    "/sdcard/Android/data/top.yiqikan.app.debug/cache/spider.jar",
                    "流浪地球",
                    android.os.Handler(mainLooper),
                ) { r -> result.success(r) }
                "probeJarScan" -> top.yiqikan.app.probe.Hello.probeJarScan(
                    applicationContext,
                    "/sdcard/Android/data/top.yiqikan.app.debug/cache/spider.jar",
                    "流浪地球",
                    android.os.Handler(mainLooper),
                ) { r -> result.success(r) }
                // P1：TVBox 单源 搜索 / 详情 / 播放。全部走工作线程，结果 Handler.post 回主线程
                "tvboxSearch", "tvboxDetail", "tvboxPlay" -> Thread({
                    val a = call.arguments as? List<*>
                    val r = try {
                        when (call.method) {
                            "tvboxSearch" -> top.yiqikan.app.server.TvboxBatch.searchOne(
                                applicationContext,
                                a?.getOrNull(0) as? String ?: "",
                                a?.getOrNull(1) as? String ?: "",
                                a?.getOrNull(2) as? String ?: "",
                            )
                            "tvboxDetail" -> top.yiqikan.app.server.TvboxBatch.detailOne(
                                applicationContext,
                                a?.getOrNull(0) as? String ?: "",
                                a?.getOrNull(1) as? String ?: "",
                                a?.getOrNull(2) as? String ?: "",
                            )
                            else -> top.yiqikan.app.server.TvboxBatch.playOne(
                                applicationContext,
                                a?.getOrNull(0) as? String ?: "",
                                a?.getOrNull(1) as? String ?: "",
                                a?.getOrNull(2) as? String ?: "",
                                a?.getOrNull(3) as? String ?: "",
                            )
                        }
                    } catch (t: Throwable) {
                        "{\"error\":\"" + t.javaClass.simpleName + ": " + (t.message ?: "") + "\"}"
                    }
                    android.os.Handler(mainLooper).post { result.success(r) }
                }, "yqk-tvbox-call").start()
                else -> result.notImplemented()
            }
        }

        // 字幕编码转换：GBK/GB18030 转 UTF-8（05 §A5 要求先转码再 sub-add）
        // Dart 只内嵌 utf8/latin1/ascii，GBK 靠 7000+ 字符映射表；
        // 用 Android 自带的 Charset 一行就够，比往包里塞表省事也准
        MethodChannel(messenger, "top.yiqikan/charset").setMethodCallHandler { call, result ->
            when (call.method) {
                "decodeGbk" -> {
                    val bytes = call.arguments as? ByteArray
                    if (bytes == null) {
                        result.error("BAD_ARGS", "bytes 参数不能为空", null)
                    } else {
                        val text = try {
                            String(bytes, java.nio.charset.Charset.forName("GB18030"))
                        } catch (e: Exception) {
                            try {
                                String(bytes, java.nio.charset.Charset.forName("GBK"))
                            } catch (e2: Exception) {
                                null
                            }
                        }
                        if (text == null) {
                            result.error("DECODE_FAILED", "这段字幕不是 GBK/GB18030 编码", null)
                        } else {
                            result.success(text)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        // 设备能力：给 Dart 侧的画质档位分发用（04 §12.6.1 替代方案表）。
        // 只读总内存，不读任何用户数据，也不上报。
        MethodChannel(messenger, "top.yiqikan/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "totalRamMb" -> {
                    try {
                        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        val mi = ActivityManager.MemoryInfo()
                        am.getMemoryInfo(mi)
                        result.success((mi.totalMem / (1024 * 1024)).toInt())
                    } catch (e: Exception) {
                        result.error("NO_MEMINFO", "读不到设备内存信息", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "yiqikan/audio_output").setMethodCallHandler { call, result ->            when (call.method) {
                "setRoute" -> {
                    val route = call.argument<String>("route") ?: "speaker"
                    val am = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
                    @Suppress("DEPRECATION")
                    am.mode = android.media.AudioManager.MODE_IN_COMMUNICATION
                    @Suppress("DEPRECATION")
                    am.isSpeakerphoneOn = route == "speaker"
                    result.success(null)
                }
                "currentRoute" -> {
                    val am = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
                    @Suppress("DEPRECATION")
                    result.success(if (am.isSpeakerphoneOn) "speaker" else "earpiece")
                }
                else -> result.notImplemented()
            }
        }

        val media = MediaSessionHelper(this, MethodChannel(messenger, "yiqikan/media"))
        MethodChannel(messenger, "yiqikan/media").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    media.start()
                    result.success(true)
                }
                "stop" -> {
                    media.stop()
                    result.success(true)
                }
                "metadata" -> {
                    media.setMetadata(
                        call.argument<String>("title") ?: "",
                        call.argument<String>("artist") ?: "",
                        (call.argument<Int>("duration") ?: 0).toLong()
                    )
                    result.success(true)
                }
                "state" -> {
                    media.setState(
                        call.argument<Boolean>("playing") ?: false,
                        (call.argument<Int>("position") ?: 0).toLong()
                    )
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "yiqikan/foreground").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val t = call.argument<String>("title") ?: "正在播放"
                    val x = call.argument<String>("text") ?: ""
                    PlaybackService.start(this, t, x)
                    result.success(true)
                }
                "stop" -> {
                    PlaybackService.stop(this)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "yiqikan/screen").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        val i = Intent(this, top.yiqikan.app.server.ScreenShareService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(i)
                        } else {
                            startService(i)
                        }
                        result.success(true)
                    } catch (t: Throwable) {
                        Log.e("YQK-SCREEN", "[YQK-SCREEN] svc start fail " + t)
                        result.error("svc", t.toString(), null)
                    }
                }
                "stop" -> {
                    try {
                        stopService(Intent(this, top.yiqikan.app.server.ScreenShareService::class.java))
                        result.success(true)
                    } catch (t: Throwable) {
                        Log.e("YQK-SCREEN", "[YQK-SCREEN] svc stop fail " + t)
                        result.error("svc", t.toString(), null)
                    }
                }
                "fgState" -> result.success(
                    top.yiqikan.app.server.ScreenShareService.isFgOk()
                )
                else -> result.notImplemented()
            }
        }

        // A1（批 E10）：把备份 JSON 落到系统「下载」目录，文件管理器里能直接看到。
        // 只写自己 insert 的那一条，不申请 MANAGE_EXTERNAL_STORAGE；API < 29 直接报 unsupported，
        // Dart 侧会回落到 file_picker.saveFile（SAF 让用户选位置）。
        MethodChannel(messenger, "yiqikan/save").setMethodCallHandler { call, result ->
            if (call.method == "saveDownloads") {
                val name = call.argument<String>("fileName") ?: "yiqikan_backup.json"
                val content = call.argument<String>("content") ?: ""
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                    result.error("unsupported", "MediaStore.Downloads needs API 29+", null)
                } else {
                    try {
                        val bytes = content.toByteArray(Charsets.UTF_8)
                        val values = android.content.ContentValues()
                        values.put(android.provider.MediaStore.Downloads.DISPLAY_NAME, name)
                        values.put(
                            android.provider.MediaStore.Downloads.MIME_TYPE,
                            "application/json"
                        )
                        values.put(
                            android.provider.MediaStore.Downloads.RELATIVE_PATH,
                            android.os.Environment.DIRECTORY_DOWNLOADS
                        )
                        values.put(android.provider.MediaStore.Downloads.IS_PENDING, 1)
                        val uri = contentResolver.insert(
                            android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI, values
                        )
                        if (uri == null) {
                            result.error("insert", "MediaStore insert returned null", null)
                        } else {
                            contentResolver.openOutputStream(uri)?.use { out ->
                                out.write(bytes)
                                out.flush()
                            }
                            val done = android.content.ContentValues()
                            done.put(android.provider.MediaStore.Downloads.IS_PENDING, 0)
                            contentResolver.update(uri, done, null, null)
                            val path = "/storage/emulated/0/" +
                                android.os.Environment.DIRECTORY_DOWNLOADS + "/" + name
                            Log.i("YQK-SAVE", "[YQK-SAVE] saved path=$path bytes=${bytes.size}")
                            // A2（批 E11）：写完顺手删掉旧的同前缀备份，下载目录只留这一份。
                            val keepId = android.content.ContentUris.parseId(uri)
                            val pruned = pruneBackups(keepId)
                            Log.i("YQK-SAVE", "[YQK-SAVE] prune removed=$pruned")
                            result.success(path)
                        }
                    } catch (t: Throwable) {
                        Log.e("YQK-SAVE", "[YQK-SAVE] fail " + t)
                        result.error("save", t.toString(), null)
                    }
                }
            } else if (call.method == "prune") {
                // A2：Dart 侧显式清理（导出失败重试、用户手动点「清理旧备份」时用）。
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                    result.error("unsupported", "MediaStore.Downloads needs API 29+", null)
                } else {
                    try {
                        val removed = pruneBackups(-1L)
                        Log.i("YQK-SAVE", "[YQK-SAVE] prune removed=$removed")
                        result.success(removed)
                    } catch (t: Throwable) {
                        Log.e("YQK-SAVE", "[YQK-SAVE] prune fail " + t)
                        result.error("prune", t.toString(), null)
                    }
                }
            } else if (call.method == "readLatestDownload") {
                // 读「下载」目录里最近一份 yiqikan_backup*.json（系统文件选择器在这台 ROM 上
                // 只会把 json 交给「打开方式」，拿不回路径，所以给导入留一条 MediaStore 直读）。
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                    result.error("unsupported", "MediaStore.Downloads needs API 29+", null)
                } else {
                    try {
                        val proj = arrayOf(
                            android.provider.MediaStore.Downloads._ID,
                            android.provider.MediaStore.Downloads.DISPLAY_NAME,
                            android.provider.MediaStore.Downloads.SIZE
                        )
                        val sel = android.provider.MediaStore.Downloads.DISPLAY_NAME + " LIKE ?"
                        val args = arrayOf("yiqikan_backup%")
                        // A3（批 E11）：同一秒写两份时 DATE_ADDED 相同，再按名字排（名字带时分）。
                        val order = android.provider.MediaStore.Downloads.DATE_ADDED +
                            " DESC, " + android.provider.MediaStore.Downloads.DISPLAY_NAME + " DESC"
                        var name = ""
                        var body = ""
                        contentResolver.query(
                            android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                            proj, sel, args, order
                        )?.use { c ->
                            if (c.moveToFirst()) {
                                name = c.getString(1) ?: ""
                                val uri = android.content.ContentUris.withAppendedId(
                                    android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                                    c.getLong(0)
                                )
                                body = contentResolver.openInputStream(uri)
                                    ?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: ""
                            }
                        }
                        if (name.isEmpty() || body.isEmpty()) {
                            Log.i("YQK-SAVE", "[YQK-SAVE] readLatest empty")
                            result.error("not_found", "下载目录里没有备份文件", null)
                        } else {
                            Log.i(
                                "YQK-SAVE",
                                "[YQK-SAVE] readLatest name=$name chars=${body.length}"
                            )
                            result.success(mapOf("name" to name, "content" to body))
                        }
                    } catch (t: Throwable) {
                        Log.e("YQK-SAVE", "[YQK-SAVE] readLatest fail " + t)
                        result.error("read", t.toString(), null)
                    }
                }
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(messenger, "yiqikan/install").setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstall" -> {
                    val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        packageManager.canRequestPackageInstalls()
                    } else true
                    result.success(ok)
                }
                "openSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val i = Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                            .setData(android.net.Uri.parse("package:$packageName"))
                        startActivity(i)
                    }
                    result.success(null)
                }
                "install" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.success(false)
                    } else {
                        result.success(installApk(path))
                    }
                }
                else -> result.notImplemented()
            }
        }

        // G13 省电：只读白名单状态 + 用户主动点「去设置」时才拉起系统页。
        // 不用 QUERY_ALL_PACKAGES，也不需要任何新权限。
        MethodChannel(messenger, "yiqikan/power").setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBattery" -> {
                    val pm = getSystemService(POWER_SERVICE) as android.os.PowerManager
                    val ok = pm.isIgnoringBatteryOptimizations(packageName)
                    Log.i("YQK-POWER", "[YQK-POWER] isIgnoringBattery=$ok pkg=$packageName")
                    result.success(ok)
                }
                "requestIgnoreBattery" -> {
                    val i = Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                        .setData(android.net.Uri.parse("package:$packageName"))
                    try {
                        startActivity(i)
                        Log.i("YQK-POWER", "[YQK-POWER] requestIgnoreBattery opened")
                        // 部分 ROM（实测 vivo API36）对这个 intent 静默忽略：不跳页也不报错。
                        // 600ms 后如果窗口焦点还在本应用，就退一步打开「电池优化」列表页，
                        // 用户自己在里面找到「一起看」加白名单。
                        android.os.Handler(mainLooper).postDelayed({
                            if (hasWindowFocus()) {
                                try {
                                    startActivity(Intent(
                                        android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                                    Log.i("YQK-POWER", "[YQK-POWER] fallback list page opened")
                                } catch (e: Exception) {
                                    Log.w("YQK-POWER", "[YQK-POWER] fallback fail: $e")
                                }
                            }
                        }, 600)
                    } catch (e: Exception) {
                        Log.w("YQK-POWER", "[YQK-POWER] requestIgnoreBattery fail: $e")
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // 用系统浏览器打开 http(s) 链接：播放失败时让用户自己看真实报错
        MethodChannel(messenger, "yiqikan/open_external").setMethodCallHandler { call, result ->
            when (call.method) {
                "openUrl" -> {
                    val url = call.argument<String>("url")
                    if (url == null) {
                        result.success(false)
                    } else {
                        result.success(openExternal(url))
                    }
                }
                else -> result.notImplemented()
            }
        }

        val filter = IntentFilter().apply {
            addAction(ACTION_PLAY_PAUSE)
            addAction(ACTION_FORWARD)
            addAction(ACTION_REWIND)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(pipReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(pipReceiver, filter)
        }

    }

    /// 删掉「下载」目录里除 [keepId] 之外的 yiqikan_backup*.json，返回删了几条。
    ///
    /// [keepId] 传 -1 表示「保留最新那份」（readLatest 的排序口径），
    /// 传刚写入的 _ID 表示「保留我刚写的那份」。
    private fun pruneBackups(keepId: Long): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return 0
        val uriBase = android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val proj = arrayOf(
            android.provider.MediaStore.Downloads._ID,
            android.provider.MediaStore.Downloads.DISPLAY_NAME
        )
        val sel = android.provider.MediaStore.Downloads.DISPLAY_NAME + " LIKE ?"
        val args = arrayOf("yiqikan_backup%")
        val order = android.provider.MediaStore.Downloads.DATE_ADDED + " DESC, " +
            android.provider.MediaStore.Downloads.DISPLAY_NAME + " DESC"
        var keep = keepId
        val victims = ArrayList<Long>()
        contentResolver.query(uriBase, proj, sel, args, order)?.use { c ->
            while (c.moveToNext()) {
                val id = c.getLong(0)
                if (keep == -1L) {
                    keep = id
                    continue
                }
                if (id != keep) victims.add(id)
            }
        }
        var removed = 0
        for (id in victims) {
            try {
                val u = android.content.ContentUris.withAppendedId(uriBase, id)
                if (contentResolver.delete(u, null, null) > 0) removed++
            } catch (t: Throwable) {
                Log.w("YQK-SAVE", "[YQK-SAVE] prune skip id=$id " + t)
            }
        }
        return removed
    }

    /// 用系统安装器装 APK；没有安装器时返回 false
    private fun installApk(path: String): Boolean {
        return try {
            val file = File(path)
            val uri = FileProvider.getUriForFile(
                this, "$packageName.fileprovider", file
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    /// 交给系统浏览器打开；没有可用浏览器时返回 false
    private fun openExternal(url: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (autoEnter && inPlayerPage) enterPip()
    }

    private fun enterPip(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            enterPictureInPictureMode(buildParams())
        } catch (e: Exception) {
            false
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun buildParams(): PictureInPictureParams {
        val ratio = Rational(width, height)
        val builder = PictureInPictureParams.Builder().setAspectRatio(ratio)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && isPipActionsSupported()) {
            builder.setActions(
                listOf(
                    action(ACTION_REWIND, "Rewind", android.R.drawable.ic_media_rew),
                    action(
                        ACTION_PLAY_PAUSE,
                        if (playing) "Pause" else "Play",
                        if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
                    ),
                    action(ACTION_FORWARD, "Forward", android.R.drawable.ic_media_ff)
                )
            )
        }
        return builder.build()
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun updatePipParams() {
        try {
            setPictureInPictureParams(buildParams())
        } catch (_: Exception) {
        }
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun isPipActionsSupported(): Boolean =
        packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    @RequiresApi(Build.VERSION_CODES.O)
    private fun action(action: String, title: String, iconRes: Int): RemoteAction {
        val intent = Intent(action).setPackage(packageName)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        val pi = PendingIntent.getBroadcast(this, action.hashCode(), intent, flags)
        return RemoteAction(Icon.createWithResource(this, iconRes), title, title, pi)
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(pipReceiver)
        } catch (_: Exception) {
        }
        super.onDestroy()
    }

    companion object {
        private const val ACTION_PLAY_PAUSE = "top.yiqikan.pip.PLAY_PAUSE"
        private const val ACTION_FORWARD = "top.yiqikan.pip.FORWARD"
        private const val ACTION_REWIND = "top.yiqikan.pip.REWIND"

        /** 深链进房通道（Dart 侧 DeepLinkBridge 同名）。 */
        private const val TAG_LINK = "YQK-LINK"
        private const val TAG_QJS = "YQK-QJS"
        private const val CHANNEL_LINK = "top.yiqikan.app/deeplink"
    }
}
