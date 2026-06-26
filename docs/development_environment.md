# 开发环境记录

当前策略：使用 Flutter 开发跨平台记账 App，Android 调试优先使用 USB 真机和
`adb`，不依赖 Android Studio 作为主工作台。

## 已验证环境

当前 Codex 会话已验证：

- `JAVA_HOME=D:\environments\jdk-26.0.1`
- `java -version`：OpenJDK `26.0.1`
- `javac -version`：`26.0.1`
- `ANDROID_HOME=D:\environments\Android`
- `sdkmanager` 位于 `D:\environments\Android\cmdline-tools\latest\bin`
- `adb` 位于 `D:\environments\Android\platform-tools`
- `adb devices` 可看到真机：`2FD0221319026163 device`
- Android SDK licenses 已接受
- `PUB_HOSTED_URL=https://pub.flutter-io.cn`
- `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`

当前已安装的 Android SDK 组件至少包括：

- `platform-tools`
- `build-tools;35.0.0`
- `build-tools;36.0.0`
- `platforms;android-35`
- `platforms;android-36`

`ANDROID_SDK_ROOT` 当前未设置；已有 `ANDROID_HOME`，Flutter/Android CLI 可以识别。

## 注意事项

`sdkmanager` 在 JDK 26 下会打印 JNA/native-access 相关 warning。当前表现是警告，
不是阻断错误。如果之后 Gradle 或 Android 工具链出现 JDK 兼容问题，再考虑切换到
JDK 21 LTS 作为构建 JDK。

Flutter 依赖下载已配置国内镜像：

```powershell
setx PUB_HOSTED_URL https://pub.flutter-io.cn
setx FLUTTER_STORAGE_BASE_URL https://storage.flutter-io.cn
```

但是 Flutter Android 首次构建仍可能通过 Gradle 拉取 Maven 依赖。因此 Flutter
项目生成后，需要检查 Android 侧 Gradle 仓库配置，将 `google()` 和
`mavenCentral()` 替换为阿里云 Maven 镜像。

建议镜像：

```gradle
maven { url = uri("https://maven.aliyun.com/repository/google") }
maven { url = uri("https://maven.aliyun.com/repository/central") }
maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
```

新 Flutter 模板优先检查：

- `app/android/settings.gradle`

旧模板还需要检查：

- `app/android/build.gradle`

## 常用命令

```powershell
adb devices
adb install app\build\app\outputs\flutter-apk\app-debug.apk
adb logcat
flutter create app --platforms=android,ios
flutter pub get
flutter run -d 2FD0221319026163
```
