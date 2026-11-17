package com.github.catvod.parser;

/**
 * STUB：按 dexdump 签名补，方法体未实现。
 *
 * 在 spider.jar 的 dex 里，JsonSequence 只以 new-instance / 字段类型出现，
 * 没有抓到任何方法或字段引用，因此这里只留一个空类占位，
 * 让 `new JsonSequence()` 之类的字节码在类加载时不会 NoClassDefFoundError。
 */
public class JsonSequence {
}
