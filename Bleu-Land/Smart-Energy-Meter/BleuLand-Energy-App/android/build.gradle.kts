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
// Some plugins still build against an old Android SDK (esp_provisioning_ble
// uses 33), but the AndroidX libraries they pull in need 34 or newer.
// Raise every plugin library to at least 36 before its settings are locked.
// (Must stay above the evaluationDependsOn block below.)
subprojects {
    val minCompileSdk = 36
    fun raiseCompileSdk() {
        if (!plugins.hasPlugin("com.android.library")) return
        extensions.getByName("android").withGroovyBuilder {
            val current = getProperty("compileSdk") as Int?
            if (current == null || current < minCompileSdk) setProperty("compileSdk", minCompileSdk)
        }
    }
    if (state.executed) raiseCompileSdk() else afterEvaluate { raiseCompileSdk() }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
