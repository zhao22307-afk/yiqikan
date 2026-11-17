/// Android 上唯一「安全」的缩放核。
///
/// 2026-11-05 真机实测（04 §12.6.2）：
/// - `vo_gpu` 的内核在运行时编译 GLSL，本机 GLES 只有 `bilinear` / `spline36`
///   能编过，`lanczos` / `ewa_lanczos*` / `bicubic` / `catmull_rom` / `mitchell`
///   / `gaussian` 作 `scale` 时一律静默黑屏（fc 在涨、有声音、日志无报错）。
/// - media_kit 的 `Video` 是 Texture：mpv 按**源分辨率**输出，Flutter 再拉伸，
///   所以 `scale` / `dscale` 改不出任何像素差（实测 MAD = 0.0000）。
///
/// 结论：不向用户暴露任何档位，也不把缩放核写进 mpv（写了既没用又有黑屏风险）。
/// 这里只留一个常量给需要「显式指定」的地方用，纯内部常量，永不下发。
///
/// 将来若「画质增强」复活，必须挂在 `--vf=scale=w:h:flags=...` 上（真正改帧尺寸），
/// 而不是 `scale` 属性。
const String kAndroidScale = 'bilinear';
