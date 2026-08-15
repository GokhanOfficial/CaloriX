allprojects {
    repositories {
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
    // camera_android_camerax (CameraX 1.5.3) jspecify derleme hatası için
    // eksik transitif bağımlılığı plugin sonrası ekle.
    // Bkz: https://github.com/flutter/flutter/issues/ — camera_android_camerax known issue
    plugins.withId("com.android.library") {
        if (project.name == "camera_android_camerax") {
            project.dependencies.add(
                "implementation",
                "androidx.concurrent:concurrent-futures:1.2.0",
            )
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
