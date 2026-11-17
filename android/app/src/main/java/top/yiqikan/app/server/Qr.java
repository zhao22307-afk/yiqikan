package top.yiqikan.app.server;

/**
 * 极简 QR 码生成器（Byte 模式 / 纠错等级 L / 版本 1–5，单块，无需交织）。
 * <p>
 * 为什么不引第三方库：内置服务要在 APK 里跑，多一个依赖就多一份体积和冲突风险；
 * 而且这里只需要把「一个 http 地址 + 房间号」变成二维码，容量上限 108 字节足够。
 * <p>
 * 输出 SVG（Android WebView 与浏览器都能直接渲染，不依赖 android.graphics）。
 */
public final class Qr {

    private static final int[] EXP = new int[512];
    private static final int[] LOG = new int[256];

    static {
        int x = 1;
        for (int i = 0; i < 255; i++) {
            EXP[i] = x;
            LOG[x] = i;
            x <<= 1;
            if (x >= 256) x ^= 0x11D;
        }
        for (int i = 255; i < 512; i++) EXP[i] = EXP[i - 255];
    }

    /** 版本 1–5 的总码字数（数据 + EC） */
    private static final int[] TOTAL_CODEWORDS = {0, 26, 44, 70, 100, 134};
    /** 纠错等级 L 的 EC 码字数（单块） */
    private static final int[] EC_CODEWORDS_L = {0, 7, 10, 15, 20, 26};
    /** 对齐图案中心坐标 */
    private static final int[][] ALIGN = {
            {},
            {},
            {6, 18},
            {6, 22},
            {6, 26},
            {6, 30}
    };

    private Qr() {
    }

    public static int versionFor(int bytes) {
        for (int v = 1; v <= 5; v++) {
            int dataBits = (TOTAL_CODEWORDS[v] - EC_CODEWORDS_L[v]) * 8;
            int need = 4 + 8 + bytes * 8;
            if (need <= dataBits) return v;
        }
        return -1;
    }

    /** 生成模块矩阵，true = 黑 */
    public static boolean[][] matrix(String text) {
        return matrix(text, -1);
    }

    /** mask < 0 表示自动选最优掩码 */
    public static boolean[][] matrix(String text, int forceMask) {
        byte[] raw = text.getBytes(java.nio.charset.Charset.forName("UTF-8"));
        int v = versionFor(raw.length);
        if (v < 0) throw new IllegalArgumentException("内容过长：" + raw.length + " 字节（上限 108）");

        int size = 17 + v * 4;
        int dataCodewords = TOTAL_CODEWORDS[v] - EC_CODEWORDS_L[v];
        byte[] data = buildData(raw, dataCodewords, v);
        byte[] ec = rsEncode(data, EC_CODEWORDS_L[v]);

        byte[] all = new byte[data.length + ec.length];
        System.arraycopy(data, 0, all, 0, data.length);
        System.arraycopy(ec, 0, all, data.length, ec.length);

        if (forceMask >= 0) return place(v, size, all, forceMask);
        boolean[][] best = null;
        int bestPenalty = Integer.MAX_VALUE;
        for (int mask = 0; mask < 8; mask++) {
            boolean[][] m = place(v, size, all, mask);
            int p = penalty(m);
            if (p < bestPenalty) {
                bestPenalty = p;
                best = m;
            }
        }
        return best;
    }

    // ---------------------------------------------------------------- 数据编码

    private static byte[] buildData(byte[] raw, int capacity, int version) {
        java.io.ByteArrayOutputStream bits = new java.io.ByteArrayOutputStream();
        int bitBuf = 0;
        int bitCnt = 0;

        bitBuf = (bitBuf << 4) | 0x4; // Byte mode
        bitCnt += 4;
        int countBits = version <= 9 ? 8 : 16;
        bitBuf = (bitBuf << countBits) | raw.length;
        bitCnt += countBits;
        for (byte b : raw) {
            bitBuf = (bitBuf << 8) | (b & 0xff);
            bitCnt += 8;
            while (bitCnt >= 8) {
                bitCnt -= 8;
                bits.write((bitBuf >>> bitCnt) & 0xff);
            }
        }
        if (bitCnt > 0) {
            bitBuf = (bitBuf << (8 - bitCnt));
            bits.write(bitBuf & 0xff);
        }
        byte[] out = new byte[capacity];
        byte[] cur = bits.toByteArray();
        System.arraycopy(cur, 0, out, 0, Math.min(cur.length, capacity));
        boolean pad = true;
        for (int i = cur.length; i < capacity; i++) {
            out[i] = (byte) (pad ? 0xEC : 0x11);
            pad = !pad;
        }
        return out;
    }

    /** Reed-Solomon 纠错码字 */
    static byte[] rsEncode(byte[] data, int ecLen) {
        int[] gen = new int[ecLen];
        gen[ecLen - 1] = 1;
        for (int i = 0; i < ecLen; i++) {
            for (int j = 0; j < ecLen; j++) {
                gen[j] = mul(gen[j], EXP[i]);
                if (j + 1 < ecLen) gen[j] ^= gen[j + 1];
            }
        }
        int[] res = new int[ecLen];
        for (byte b : data) {
            int factor = (b & 0xff) ^ res[0];
            System.arraycopy(res, 1, res, 0, ecLen - 1);
            res[ecLen - 1] = 0;
            for (int i = 0; i < ecLen; i++) {
                res[i] ^= mul(gen[i], factor);
            }
        }
        byte[] out = new byte[ecLen];
        for (int i = 0; i < ecLen; i++) out[i] = (byte) res[i];
        return out;
    }

    private static int mul(int a, int b) {
        if (a == 0 || b == 0) return 0;
        return EXP[LOG[a] + LOG[b]];
    }

    // ---------------------------------------------------------------- 矩阵

    private static boolean[][] place(int version, int size, byte[] codewords, int mask) {
        boolean[][] m = new boolean[size][size];
        boolean[][] fn = new boolean[size][size]; // 功能区标记

        // 定位图案 + 分隔符
        for (int[] c : new int[][]{{0, 0}, {size - 7, 0}, {0, size - 7}}) {
            int cx = c[0], cy = c[1];
            for (int y = -1; y <= 7; y++) {
                for (int x = -1; x <= 7; x++) {
                    int px = cx + x, py = cy + y;
                    if (px < 0 || py < 0 || px >= size || py >= size) continue;
                    boolean black = (x >= 0 && x <= 6 && (y == 0 || y == 6))
                            || (y >= 0 && y <= 6 && (x == 0 || x == 6))
                            || (x >= 2 && x <= 4 && y >= 2 && y <= 4);
                    m[py][px] = black;
                    fn[py][px] = true;
                }
            }
        }

        // 时序图案
        for (int i = 8; i < size - 8; i++) {
            if (!fn[6][i]) {
                m[6][i] = (i % 2 == 0);
                fn[6][i] = true;
            }
            if (!fn[i][6]) {
                m[i][6] = (i % 2 == 0);
                fn[i][6] = true;
            }
        }

        // 对齐图案
        int[] ps = ALIGN[version];
        for (int i = 0; i < ps.length; i++) {
            for (int j = 0; j < ps.length; j++) {
                if ((i == 0 && j == 0) || (i == 0 && j == ps.length - 1) || (i == ps.length - 1 && j == 0)) {
                    continue; // 与定位图案重叠
                }
                int cx = ps[i], cy = ps[j];
                for (int y = -2; y <= 2; y++) {
                    for (int x = -2; x <= 2; x++) {
                        boolean black = Math.max(Math.abs(x), Math.abs(y)) != 1;
                        m[cy + y][cx + x] = black;
                        fn[cy + y][cx + x] = true;
                    }
                }
            }
        }

        // 暗模块
        m[size - 8][8] = true;
        fn[size - 8][8] = true;

        // 预留格式信息区：左上 (0..8, 8) 与 (8, 0..8)；
        // 右下副本分别为列/行 size-8..size-1（共 8 个，与左上 7+1 个错开）
        for (int i = 0; i < 9; i++) {
            if (!fn[8][i]) {
                fn[8][i] = true;
                m[8][i] = false;
            }
            if (!fn[i][8]) {
                fn[i][8] = true;
                m[i][8] = false;
            }
        }
        for (int i = 0; i < 8; i++) {
            if (!fn[8][size - 1 - i]) {
                fn[8][size - 1 - i] = true;
                m[8][size - 1 - i] = false;
            }
            if (!fn[size - 1 - i][8]) {
                fn[size - 1 - i][8] = true;
                m[size - 1 - i][8] = false;
            }
        }

        // 数据区（右到左，双列蛇形）
        int totalBits = codewords.length * 8;
        int bitIdx = 0;
        int col = size - 1;
        boolean upward = true;
        while (col > 0) {
            if (col == 6) col--; // 跳过时序列
            for (int k = 0; k < size; k++) {
                int row = upward ? size - 1 - k : k;
                for (int c = 0; c < 2; c++) {
                    int x = col - c;
                    if (fn[row][x]) continue;
                    boolean bit = false;
                    if (bitIdx < totalBits) {
                        int byteIdx = bitIdx >> 3;
                        int bitInByte = 7 - (bitIdx & 7);
                        bit = ((codewords[byteIdx] >>> bitInByte) & 1) == 1;
                        bitIdx++;
                    }
                    m[row][x] = bit;
                }
            }
            upward = !upward;
            col -= 2;
        }

        // 掩码
        for (int y = 0; y < size; y++) {
            for (int x = 0; x < size; x++) {
                if (fn[y][x]) continue;
                if (maskBit(mask, x, y)) m[y][x] = !m[y][x];
            }
        }

        // 格式信息（纠错等级 L = 01）
        writeFormat(m, size, mask);
        return m;
    }

    private static boolean maskBit(int mask, int x, int y) {
        switch (mask) {
            case 0: return (x + y) % 2 == 0;
            case 1: return y % 2 == 0;
            case 2: return x % 3 == 0;
            case 3: return (x + y) % 3 == 0;
            case 4: return (y / 2 + x / 3) % 2 == 0;
            case 5: return (x * y) % 2 + (x * y) % 3 == 0;
            case 6: return ((x * y) % 2 + (x * y) % 3) % 2 == 0;
            case 7: return ((x + y) % 2 + (x * y) % 3) % 2 == 0;
            default: return false;
        }
    }

    private static void writeFormat(boolean[][] m, int size, int mask) {
        int ecc = 1; // L
        int data = (ecc << 3) | mask;
        // BCH(15,5)：生成多项式 0x537
        int d = data << 10;
        for (int i = 14; i >= 10; i--) {
            if (((d >>> i) & 1) == 1) d ^= 0x537 << (i - 10);
        }
        int bits = ((data << 10) | d) ^ 0x5412;

        for (int i = 0; i < 15; i++) {
            boolean mod = getBit(bits, i);
            // 垂直方向：列 8
            if (i < 6) {
                m[i][8] = mod;
            } else if (i < 8) {
                m[i + 1][8] = mod;
            } else {
                m[size - 15 + i][8] = mod;
            }
            // 水平方向：行 8
            if (i < 8) {
                m[8][size - i - 1] = mod;
            } else if (i < 9) {
                m[8][15 - i] = mod;
            } else {
                m[8][15 - i - 1] = mod;
            }
        }
        m[size - 8][8] = true;
    }

    private static boolean getBit(int v, int i) {
        return ((v >>> i) & 1) == 1;
    }

    // ---------------------------------------------------------------- 惩罚评分

    private static int penalty(boolean[][] m) {
        int size = m.length;
        int score = 0;

        // 规则 1：连续同色
        for (int i = 0; i < size; i++) {
            int runH = 1, runV = 1;
            for (int j = 1; j < size; j++) {
                if (m[i][j] == m[i][j - 1]) {
                    runH++;
                } else {
                    if (runH >= 5) score += 3 + (runH - 5);
                    runH = 1;
                }
                if (m[j][i] == m[j - 1][i]) {
                    runV++;
                } else {
                    if (runV >= 5) score += 3 + (runV - 5);
                    runV = 1;
                }
            }
            if (runH >= 5) score += 3 + (runH - 5);
            if (runV >= 5) score += 3 + (runV - 5);
        }

        // 规则 2：2x2 同色块
        for (int y = 0; y < size - 1; y++) {
            for (int x = 0; x < size - 1; x++) {
                boolean c = m[y][x];
                if (c == m[y][x + 1] && c == m[y + 1][x] && c == m[y + 1][x + 1]) score += 3;
            }
        }

        // 规则 3：类定位图案
        int[] pat1 = {1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0};
        int[] pat2 = {0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1};
        for (int y = 0; y < size; y++) {
            for (int x = 0; x <= size - 11; x++) {
                if (matchRow(m, y, x, pat1) || matchRow(m, y, x, pat2)) score += 40;
            }
        }
        for (int x = 0; x < size; x++) {
            for (int y = 0; y <= size - 11; y++) {
                if (matchCol(m, x, y, pat1) || matchCol(m, x, y, pat2)) score += 40;
            }
        }

        // 规则 4：黑白比例
        int dark = 0;
        for (boolean[] row : m) for (boolean b : row) if (b) dark++;
        int total = size * size;
        int pct = dark * 100 / total;
        score += Math.abs(pct - 50) / 5 * 10;
        return score;
    }

    private static boolean matchRow(boolean[][] m, int y, int x, int[] pat) {
        for (int i = 0; i < pat.length; i++) {
            if ((m[y][x + i] ? 1 : 0) != pat[i]) return false;
        }
        return true;
    }

    private static boolean matchCol(boolean[][] m, int x, int y, int[] pat) {
        for (int i = 0; i < pat.length; i++) {
            if ((m[y + i][x] ? 1 : 0) != pat[i]) return false;
        }
        return true;
    }

    // ---------------------------------------------------------------- 输出

    /** 生成 SVG（scale = 每模块像素，border = 静区模块数） */
    public static String svg(String text, int scale, int border, String dark, String light) {
        boolean[][] m = matrix(text);
        int n = m.length;
        int dim = (n + border * 2) * scale;
        StringBuilder sb = new StringBuilder();
        sb.append("<svg xmlns='http://www.w3.org/2000/svg' width='").append(dim)
                .append("' height='").append(dim).append("' viewBox='0 0 ").append(dim)
                .append(" ").append(dim).append("' shape-rendering='crispEdges'>")
                .append("<rect width='").append(dim).append("' height='").append(dim)
                .append("' fill='").append(light).append("'/>");
        for (int y = 0; y < n; y++) {
            int runStart = -1;
            for (int x = 0; x <= n; x++) {
                boolean on = x < n && m[y][x];
                if (on && runStart < 0) runStart = x;
                if (!on && runStart >= 0) {
                    sb.append("<rect x='").append((runStart + border) * scale)
                            .append("' y='").append((y + border) * scale)
                            .append("' width='").append((x - runStart) * scale)
                            .append("' height='").append(scale)
                            .append("' fill='").append(dark).append("'/>");
                    runStart = -1;
                }
            }
        }
        sb.append("</svg>");
        return sb.toString();
    }

    /** 调试：输出最终码字（数据 + EC）的十六进制 */
    public static String codewordsHex(String text) {
        byte[] raw = text.getBytes(java.nio.charset.Charset.forName("UTF-8"));
        int v = versionFor(raw.length);
        int dataCodewords = TOTAL_CODEWORDS[v] - EC_CODEWORDS_L[v];
        byte[] data = buildData(raw, dataCodewords, v);
        byte[] ec = rsEncode(data, EC_CODEWORDS_L[v]);
        StringBuilder sb = new StringBuilder();
        sb.append("v=").append(v).append(" data=");
        for (byte b : data) sb.append(String.format("%02x", b & 0xff));
        sb.append(" ec=");
        for (byte b : ec) sb.append(String.format("%02x", b & 0xff));
        return sb.toString();
    }

    /** 调试：把矩阵打成 0/1 文本 */
    public static String text(String text) {
        return text(text, -1);
    }

    public static String text(String text, int forceMask) {
        boolean[][] m = matrix(text, forceMask);
        StringBuilder sb = new StringBuilder();
        for (boolean[] row : m) {
            for (boolean b : row) sb.append(b ? '1' : '0');
            sb.append('\n');
        }
        return sb.toString();
    }
}
