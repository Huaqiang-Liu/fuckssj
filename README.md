# fuckssj

fuckssj 是一个本地优先的 Flutter 记账 App，目标是让用户能够继续使用自己已有的随手记备份数据，并在一个轻量、直接、可控的应用里管理账本。

项目当前重点支持 Android。iOS 工程保留在仓库中，但发布和适配会在后续处理。

## 功能

- 多账本管理：创建空白账本、导入账本、打开已有账本。
- 随手记备份导入：支持从随手记本地备份导出的 `.kbf` 文件创建账本。
- SQLite 导入：支持导入 `.sqlite`、`.sqlite3`、`.db`、`.db3` 文件。
- 账本管理：重命名、备注、导出、删除。
- 流水查询：按日期、账户、币种、分类、收入/支出、金额范围和备注关键词筛选。
- 流水编辑：新建、编辑、删除收入和支出记录。
- 分类管理：当前账本内维护收入/支出分类，支持一级分类和二级分类。
- 账户管理：当前账本内维护账户分组和账户词条。
- 外币管理：维护当前账本常用币种，显示本地缓存汇率。
- 主题设置：浅色、深色、跟随系统。
- 字号设置：在默认字号基础上提供加大选项。

## 安装 Android APK

项目不计划发布到 Google Play 或其它应用商店。正式 APK 通过 GitHub Releases 分发。

1. 打开本仓库的 GitHub Releases 页面。
2. 下载最新版本的 `apk` 文件，例如 `fuckssj-v1.0.0+1-android-release.apk`。
3. 在 Android 手机上打开该文件并安装。
4. 如果系统提示禁止安装未知来源应用，需要先为当前文件管理器或浏览器允许“安装未知应用”。

升级安装时，Android 会校验应用签名。后续版本必须使用同一套 release 签名，才能覆盖安装并保留已有 App 数据。

## 数据与隐私

- 账本文件保存在本机，App 不提供云同步。
- 一个账本对应一个由 App 管理的 SQLite 文件。
- 从外部导入账本时，App 会复制文件到自己的管理目录；后续不依赖原始文件路径。
- 导出账本会得到明文 SQLite 文件，请自行妥善保存。
- 当前版本不包含密码、生物识别、数据库加密或远程备份能力。
- 删除账本会删除 App 管理目录中的账本文件、配置文件和索引记录，请在删除前确认已经备份。

## 从随手记迁移

推荐直接在 App 首页使用“从随手记本地备份导出的 KBF 文件创建”。

随手记本地备份通常可以通过以下路径生成：

1. 在随手记 App 中进入账本主页右下角设置。
2. 进入高级功能、备份与同步、本地备份与恢复。
3. 执行立即手动备份，得到 `.kbf` 文件。
4. 在 fuckssj 中选择该 `.kbf` 文件导入。

`.kbf` 文件本质上是压缩包，里面包含账本数据库。fuckssj 会在 App 内完成解包、恢复 SQLite 文件头、校验数据库和导入账本的流程。

仓库中仍保留桌面端手动恢复脚本，主要用于调试、排查或高级用户自行检查数据：

```powershell
python .\scripts\process_backup_kbf.py <导出的kbf文件>.kbf -o recovered\mymoney.sqlite
```

恢复出的 `recovered/mymoney.sqlite` 是真实账本数据，已被 `.gitignore` 忽略，不应提交到 Git。

## 开发环境

主要工程在 `app/` 目录下。

```powershell
cd D:\softwares\fuckssj\app
flutter pub get
flutter test
flutter run
```

常用目录：

```text
app/
  lib/
    main.dart
    src/
      app/          # App 入口、主题和顶层配置
      data/         # 账本、配置、流水等本地数据访问
      features/     # 账本首页、查询、设置和管理界面
      importer/     # 随手记 KBF/SQLite 兼容导入逻辑
  test/             # Flutter 和 Dart 测试
docs/
  app_ui_flow.md    # 界面、跳转和交互说明
scripts/
  process_backup_kbf.py
test/
  verify_record.py  # 桌面端 SQLite 验证脚本
```

当前版本号在 [app/pubspec.yaml](app/pubspec.yaml) 中维护：

```yaml
version: 1.0.0+1
```

## Android Release 构建

### 1. 准备签名文件

在 `app/android/` 下生成 release keystore：

```powershell
cd D:\softwares\fuckssj\app\android
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

然后创建 `app/android/key.properties`：

```properties
storePassword=<keystore密码>
keyPassword=<key密码>
keyAlias=upload
storeFile=upload-keystore.jks
```

`key.properties` 和 keystore 文件都已被 `.gitignore` 忽略，不要提交到仓库。请备份 keystore；丢失后将无法用同一签名升级已安装用户的 APK。

### 2. 检查包名

发布第一个正式版本前，建议把 Android `applicationId` 从模板值改成自己的唯一包名。当前位置是 [app/android/app/build.gradle.kts](app/android/app/build.gradle.kts)：

```kotlin
applicationId = "com.example.fuckssj"
```

一旦公开发布并有用户安装，后续再改 `applicationId` 会被 Android 视为另一个应用，不能作为原应用升级安装。

### 3. 构建 APK

```powershell
cd D:\softwares\fuckssj\app
flutter build apk --release
```

构建成功后的默认输出路径：

```text
app/build/app/outputs/flutter-apk/app-release.apk
```

发布到 GitHub Releases 前，建议重命名为包含版本号的平台文件名：

```text
fuckssj-v1.0.0+1-android-release.apk
```

## 发布到 GitHub Releases

本项目的发布方式是把 release APK 作为 GitHub Release 附件上传。

推荐流程：

1. 确认 `app/pubspec.yaml` 中的 `version` 已更新。
2. 确认 README、LICENSE 和必要文档已经同步。
3. 本地构建 release APK。
4. 在 GitHub 上创建 tag，例如 `v1.0.0+1`。
5. 创建 GitHub Release。
6. 上传 `fuckssj-v1.0.0+1-android-release.apk`。
7. 在 Release notes 中说明安装方式、主要变化和已知限制。

如果已经安装过旧版本，测试升级包时应使用同一个 release keystore 构建，直接覆盖安装验证数据是否保留。

## 设计文档

界面结构、页面跳转和交互细节见 [docs/app_ui_flow.md](docs/app_ui_flow.md)。

该文档用于开发协作和功能验收，README 只保留用户与开发者最常用的信息。

## License

本项目使用 MIT License，详见 [LICENSE](LICENSE)。
