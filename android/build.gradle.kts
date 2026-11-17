// 与 Flutter 3.44.6 官方 android-Kotlin 模板保持一致，只额外加了阿里云镜像。
// 关键点（模板里的两条 subprojects 不能删）：
//  1. 把构建目录重定向到工程根的 build/，flutter 工具按 <工程>/build/app/outputs/flutter-apk 找产物；
//  2. subprojects { evaluationDependsOn(":app") } 保证插件工程在 :app 之后求值 ——
//     Flutter 的 Gradle 插件是在 :app 求值过程中才给插件工程创建 `flutter` 扩展的，
//     顺序反了插件脚本里 extensions.getByName("flutter") 就会报 “Extension with name 'flutter' does not exist”。
allprojects {
    repositories {
        // 阿里云镜像优先（与 ferry-bot-android 保持一致）
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/public")
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
