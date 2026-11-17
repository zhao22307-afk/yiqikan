package top.yiqikan.app.server;

import android.app.Activity;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.StateListDrawable;
import android.os.Build;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.Window;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

/**
 * 建房方式选择器。
 *
 * 触发方式有三条：
 *   1) App 点「开房间」→ 内置服务收到 POST /rooms/ 且用户还没选过方式 → 直接拉起本页
 *   2) 通知栏「房间 xxx 已建好」→ 点进本页
 *   3) 桌面图标「建房方式」/ 浏览器打开 http://127.0.0.1:8080/local/choose
 *
 * 选完之后：defaultMode 落到 misc.json，本机所有「待定」房间按该方式重算 join_url。
 */
public class ChooseActivity extends Activity {

    public static final String EXTRA_CODE = "code";
    private static final String CHANNEL = "yiqikan_choose";

    // 深色主题
    private static final int C_BG = 0xFF0B0E14;
    private static final int C_TITLE = 0xFFE9EDF5;
    private static final int C_SUB = 0xFF8B94A6;
    private static final int C_ACCENT = 0xFF4DA3FF;
    private static final int C_STROKE = 0xFF242B39;
    private static final int C_STROKE_ON = 0xFF3A6CFF;
    private static final int BADGE_A = 0xFF2A6BFF;
    private static final int BADGE_B = 0xFF7B5CFF;

    private Store st;
    private String code = "";
    private float d;
    private final List<View> cards = new ArrayList<View>();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        st = Store.get(this);
        Intent it = getIntent();
        if (it != null && it.getStringExtra(EXTRA_CODE) != null) {
            code = it.getStringExtra(EXTRA_CODE);
        }
        d = getResources().getDisplayMetrics().density;
        setTitle("选择建房方式");
        paintChrome();
        setContentView(build());
    }

    private void paintChrome() {
        try {
            getWindow().setStatusBarColor(C_BG);
            getWindow().setNavigationBarColor(C_BG);
        } catch (Throwable ignored) {
        }
    }

    // ------------------------------------------------------------ UI

    private View build() {
        int pad = px(20);

        ScrollView sc = new ScrollView(this);
        sc.setBackgroundColor(C_BG);
        sc.setFillViewport(true);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(pad, px(28), pad, px(32));
        sc.addView(root, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));

        // 顶部品牌行
        TextView kicker = text("一起看 · 本机服务", 11, C_ACCENT);
        kicker.setTypeface(Typeface.DEFAULT_BOLD);
        kicker.setLetterSpacing(0.18f);
        root.addView(kicker);

        // 主标题
        TextView h1 = text("朋友怎么连进来？", 25, C_TITLE);
        h1.setTypeface(Typeface.DEFAULT_BOLD);
        LinearLayout.LayoutParams h1p = wrap();
        h1p.topMargin = px(10);
        root.addView(h1, h1p);

        // 副标题
        TextView lead = text("选一种通道。选定后本机所有房间的「客人要填的地址」按它计算，以后建房默认用它。",
                13, C_SUB);
        lead.setLineSpacing(px(4), 1f);
        LinearLayout.LayoutParams lp = wrap();
        lp.topMargin = px(8);
        lp.bottomMargin = px(18);
        root.addView(lead, lp);

        // 房间号 chip
        if (!code.isEmpty()) {
            root.addView(chip("房间 " + code), chipParams());
        }

        // 七种方式
        String cur = st.defaultMode == null ? "" : st.defaultMode;
        for (int i = 0; i < Rooms.MODES.length; i++) {
            String mode = Rooms.MODES[i];
            boolean active = mode.equals(cur);
            View c = card(i + 1, mode, stripLabel(Rooms.LABELS[i]), Rooms.HINTS[i], active);
            cards.add(c);
            LinearLayout.LayoutParams cp = wrap();
            cp.bottomMargin = px(10);
            root.addView(c, cp);
        }

        // 分隔
        View line = new View(this);
        line.setBackgroundColor(0xFF1B212C);
        LinearLayout.LayoutParams lnp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, Math.max(1, px(1)));
        lnp.topMargin = px(14);
        lnp.bottomMargin = px(14);
        root.addView(line, lnp);

        TextView qrBtn = text("扫码加房 · 让对方扫这个码  ›", 13, C_ACCENT);
        qrBtn.setTypeface(Typeface.DEFAULT_BOLD);
        qrBtn.setGravity(Gravity.CENTER);
        qrBtn.setPadding(px(14), px(15), px(14), px(15));
        GradientDrawable qb = new GradientDrawable();
        qb.setColor(0x1A4DA3FF);
        qb.setCornerRadius(px(13));
        qb.setStroke(Math.max(1, px(1)), 0x554DA3FF);
        qrBtn.setBackground(qb);
        qrBtn.setClickable(true);
        qrBtn.setFocusable(true);
        qrBtn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                openQr();
            }
        });
        LinearLayout.LayoutParams qp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        qp.topMargin = px(4);
        root.addView(qrBtn, qp);

        TextView foot = text("随时可以在浏览器打开  http://127.0.0.1:8080/local/choose  重新选择", 11, 0xFF6B7486);
        root.addView(foot);

        return sc;
    }

    private View card(int no, final String mode, String label, String hint, boolean active) {
        int pad = px(16);

        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.HORIZONTAL);
        box.setGravity(Gravity.CENTER_VERTICAL);
        box.setPadding(pad, px(15), px(13), px(15));
        box.setBackground(cardBg(active));
        box.setClickable(true);
        box.setFocusable(true);

        // 序号徽标
        TextView badge = text(String.valueOf(no), 13, 0xFFFFFFFF);
        badge.setTypeface(Typeface.DEFAULT_BOLD);
        badge.setGravity(Gravity.CENTER);
        GradientDrawable bd = new GradientDrawable(
                GradientDrawable.Orientation.TL_BR, new int[]{BADGE_A, BADGE_B});
        bd.setShape(GradientDrawable.OVAL);
        badge.setBackground(bd);
        int bs = px(30);
        LinearLayout.LayoutParams blp = new LinearLayout.LayoutParams(bs, bs);
        blp.rightMargin = px(14);
        box.addView(badge, blp);

        // 中间文字
        LinearLayout mid = new LinearLayout(this);
        mid.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams mlp = new LinearLayout.LayoutParams(
                0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f);
        box.addView(mid, mlp);

        LinearLayout titleRow = new LinearLayout(this);
        titleRow.setOrientation(LinearLayout.HORIZONTAL);
        titleRow.setGravity(Gravity.CENTER_VERTICAL);
        mid.addView(titleRow);

        TextView t = text(label, 15, C_TITLE);
        t.setTypeface(Typeface.DEFAULT_BOLD);
        titleRow.addView(t);

        if (active) {
            TextView now = text("当前", 10, C_ACCENT);
            now.setTypeface(Typeface.DEFAULT_BOLD);
            GradientDrawable nd = new GradientDrawable();
            nd.setColor(0x1F4DA3FF);
            nd.setCornerRadius(px(5));
            nd.setStroke(Math.max(1, px(1)), 0x664DA3FF);
            now.setBackground(nd);
            now.setPadding(px(6), px(2), px(6), px(2));
            LinearLayout.LayoutParams np = new LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
            np.leftMargin = px(8);
            titleRow.addView(now, np);
        }

        TextView h = text(hint, 12, C_SUB);
        h.setLineSpacing(px(3), 1f);
        LinearLayout.LayoutParams hp = wrap();
        hp.topMargin = px(5);
        mid.addView(h, hp);

        // 右侧箭头
        TextView arrow = text("›", 24, active ? C_ACCENT : 0xFF5A6377);
        LinearLayout.LayoutParams ap = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        ap.leftMargin = px(8);
        box.addView(arrow, ap);

        box.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                pick(mode);
            }
        });
        return box;
    }

    private Drawable cardBg(boolean active) {
        StateListDrawable sl = new StateListDrawable();
        sl.addState(new int[]{android.R.attr.state_pressed}, bg(true, active));
        sl.addState(new int[]{}, bg(false, active));
        return sl;
    }

    private Drawable bg(boolean pressed, boolean active) {
        int[] colors = pressed
                ? new int[]{0xFF1F2634, 0xFF19202C}
                : new int[]{0xFF171C26, 0xFF131720};
        GradientDrawable g = new GradientDrawable(GradientDrawable.Orientation.TL_BR, colors);
        g.setCornerRadius(px(16));
        int stroke = active ? C_STROKE_ON : (pressed ? 0xFF323B4D : C_STROKE);
        g.setStroke(Math.max(1, px(active ? 1.4f : 1f)), stroke);
        return g;
    }

    private View chip(String s) {
        TextView tv = text(s, 12, C_ACCENT);
        tv.setTypeface(Typeface.DEFAULT_BOLD);
        GradientDrawable g = new GradientDrawable();
        g.setColor(0x1A4DA3FF);
        g.setCornerRadius(px(20));
        g.setStroke(Math.max(1, px(1)), 0x554DA3FF);
        tv.setBackground(g);
        tv.setPadding(px(12), px(6), px(12), px(6));
        tv.setGravity(Gravity.CENTER_VERTICAL);
        return tv;
    }

    private LinearLayout.LayoutParams chipParams() {
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        p.bottomMargin = px(16);
        return p;
    }

    private TextView text(String s, float sp, int color) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        t.setTextColor(color);
        return t;
    }

    private LinearLayout.LayoutParams wrap() {
        return new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
    }

    private int px(float v) {
        return (int) (v * d + 0.5f);
    }

    /** 去掉 LABELS 前缀的圈号（①②…），序号改由徽标显示 */
    private static String stripLabel(String s) {
        if (s == null) return "";
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (Character.isLetter(c) || Character.isDigit(c)) {
                return s.substring(i).trim();
            }
        }
        return s;
    }

    // ------------------------------------------------------------ 选择

    /** 打开内置服务渲染的二维码页（浏览器里能看到大图，也能直接转发地址） */
    private void openQr() {
        String url = "http://127.0.0.1:" + LocalServer.PORT + "/local/qr";
        String c = getIntent().getStringExtra(EXTRA_CODE);
        if (c != null && c.length() > 0) url += "?code=" + c;
        try {
            Intent i = new Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url));
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(i);
        } catch (Throwable t) {
            Toast.makeText(this, "没有可用浏览器，请在电脑上打开 " + url, Toast.LENGTH_LONG).show();
        }
    }

    private void pick(final String mode) {
        final Context app = getApplicationContext();
        st.defaultMode = mode;
        st.save();

        final List<String> pending = new ArrayList<String>();
        for (JSONObject r : st.allRooms()) {
            String m = r.optString("mode", "");
            if (m.isEmpty() || "pending".equals(m)) {
                pending.add(r.optString("code", ""));
            }
        }
        if (code != null && !code.isEmpty() && !pending.contains(code)) {
            pending.add(code);
        }

        Toast.makeText(this, "已选择：" + Rooms.label(mode), Toast.LENGTH_SHORT).show();
        finish();

        if (pending.isEmpty()) return;
        new Thread(new Runnable() {
            public void run() {
                for (int i = 0; i < pending.size(); i++) {
                    String c = pending.get(i);
                    JSONObject room = st.findRoom(c);
                    if (room == null) continue;
                    try {
                        JSONObject body = new JSONObject();
                        body.put("mode", mode);
                        Rooms.apply(app, st, c, body, room);
                    } catch (Throwable ignored) {
                    }
                }
                st.save();
            }
        }, "yiqikan-choose-apply").start();
    }

    // ------------------------------------------------------------ 唤起

    /**
     * 建房后拉起选择页；失败则退回通知栏。
     * 返回 true 表示 Activity 启动请求已发出。
     */
    public static boolean show(Context ctx, String code) {
        try {
            Intent i = new Intent(ctx, ChooseActivity.class);
            i.putExtra(EXTRA_CODE, code == null ? "" : code);
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            ctx.startActivity(i);
            return true;
        } catch (Throwable t) {
            notifyChoose(ctx, code);
            return false;
        }
    }

    /** 通知栏兜底入口 */
    public static void notifyChoose(Context ctx, String code) {
        try {
            NotificationManager nm = (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm == null) return;
            if (Build.VERSION.SDK_INT >= 26) {
                NotificationChannel ch = new NotificationChannel(
                        CHANNEL, "建房方式", NotificationManager.IMPORTANCE_HIGH);
                ch.setDescription("房间建好后提醒选择连接方式");
                nm.createNotificationChannel(ch);
            }
            int req = (code == null ? "yiqikan".hashCode() : code.hashCode()) & 0x7fffffff;

            Intent i = new Intent(ctx, ChooseActivity.class);
            i.putExtra(EXTRA_CODE, code == null ? "" : code);
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);

            int flags = PendingIntent.FLAG_UPDATE_CURRENT;
            if (Build.VERSION.SDK_INT >= 23) flags |= PendingIntent.FLAG_IMMUTABLE;
            PendingIntent pi = PendingIntent.getActivity(ctx, req, i, flags);

            Notification.Builder nb;
            if (Build.VERSION.SDK_INT >= 26) {
                nb = new Notification.Builder(ctx, CHANNEL);
            } else {
                nb = new Notification.Builder(ctx);
            }
            nb.setSmallIcon(android.R.drawable.ic_menu_share);
            nb.setContentTitle(code == null || code.isEmpty() ? "房间已建好" : "房间 " + code + " 已建好");
            nb.setContentText("点这里选择用哪种方式让朋友连进来");
            nb.setAutoCancel(true);
            nb.setContentIntent(pi);
            nm.notify(req, nb.build());
        } catch (Throwable ignored) {
        }
    }
}
