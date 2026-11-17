package com.github.catvod.js;

import java.lang.reflect.Method;

/**
 * STUB：按 dexdump 签名补，方法体未实现。
 *
 * 签名来源（spider.jar 的引用，已核对 invoke 指令种类）：
 *   .bindFunctions:()V                                             invoke-direct（实例）
 *   .pd:(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;        invoke-virtual
 *   .pdfh:(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;                        invoke-virtual
 *   .pdfa:(Ljava/lang/String;Ljava/lang/String;)[Ljava/lang/Object;                       invoke-virtual
 *   .pdfl:(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)[Ljava/lang/Object;  invoke-virtual/range
 *   .a:(Lcom/github/catvod/js/Function;[Ljava/lang/Object;)Ljava/lang/Object;             invoke-static
 *   .b / .c / .d 同上                                                                    invoke-static
 *   .a:(Lcom/github/catvod/js/Function;Ljava/lang/reflect/Method;[Ljava/lang/Object;)Ljava/lang/Object;  invoke-static
 *   .lambda$bindFunctions$0..3:([Ljava/lang/Object;)Ljava/lang/Object;                     invoke-static
 *
 * 原版的 ctx（com.fongmi.quickjs.QuickJSContext）与 parser（merge/js）字段是私有字段，
 * 外部字节码不可见，这里不声明。
 *
 * 空方法：pd/pdfh 恒返回 ""，pdfa/pdfl 恒返回空数组，a/b/c/d 与 lambda 恒返回 null。
 */
public class Function {

    /** STUB：按 dexdump 签名补，方法体未实现。 */
    public void bindFunctions() {
    }

    /** STUB：按 dexdump 签名补，方法体未实现。 */
    public String pd(String html, String rule, String url) {
        return "";
    }

    /** STUB：按 dexdump 签名补，方法体未实现。 */
    public String pdfh(String html, String rule) {
        return "";
    }

    /** STUB：按 dexdump 签名补，方法体未实现。 */
    public Object[] pdfa(String html, String rule) {
        return new Object[0];
    }

    /** STUB：按 dexdump 签名补，方法体未实现。 */
    public Object[] pdfl(String html, String rule, String url, String st, String loop) {
        return new Object[0];
    }

    /** STUB：按 dexdump 签名补，方法体未实现。 */
    public static Object a(Function self, Object[] args) {
        return null;
    }

    /** STUB：按 dexdump 签名补，方法体未实现。 */
    public static Object b(Function self, Object[] args) {
        return null;
    }

    /** STUB：按 dexdump 签名补，方法体未实现。 */
    public static Object c(Function self, Object[] args) {
        return null;
    }

    /** STUB：按 dexdump 签名补，方法体未实现。 */
    public static Object d(Function self, Object[] args) {
        return null;
    }

    /** STUB：按 dexdump 签名补，方法体未实现。 */
    public static Object a(Function self, Method method, Object[] args) {
        return null;
    }

    /** STUB：按 dexdump 签名补，方法体未实现。 */
    public static Object lambda$bindFunctions$0(Object[] args) {
        return null;
    }

    /** STUB：按 dexdump 签名补，方法体未实现。 */
    public static Object lambda$bindFunctions$1(Object[] args) {
        return null;
    }

    /** STUB：按 dexdump 签名补，方法体未实现。 */
    public static Object lambda$bindFunctions$2(Object[] args) {
        return null;
    }

    /** STUB：按 dexdump 签名补，方法体未实现。 */
    public static Object lambda$bindFunctions$3(Object[] args) {
        return null;
    }
}
