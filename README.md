# fuckssj

随手记曾经是界面美观、功能完备的记账软件，而现在是一个臃肿、卡顿、内购、关闭5秒开屏广告的按钮每次位置都不一样的记账软件。更令人难以接受的是，它把用户自己的账本数据锁在会员付费墙后。正常导出账本到结构化文件应当是基础能力，而不是拿来迫使用户开会员的筹码。用户理应有完全的权力，取得自己的记账数据，并选用其它记账软件。本项目提供随手记备份迁移脚本，以及一个轻量化的 Flutter 记账 App 原型。

## 从随手记备份中提取数据

**导出 `.kbf` 备份文件**

本项目不依赖随手记会员导出的 XLSX，而是使用随手记自己的备份文件。流程：

1. 在随手记 App 中进入账本主页右下角的设置。
2. 高级功能-备份与同步-本地备份与恢复-立即手动备份，得到一个 `.kbf` 文件，正常情况下位于 `Download/SsjBackup/ManualBackup`，注意备份成功时给出的路径 `/storage/emulated/0/` 就视为本机文件根目录。
3. 把这个 `.kbf` 文件传到电脑，放在本项目根目录下。

**还原数据库文件**

随手记导出的 `.kbf` 文件本质上是 ZIP 压缩包。解压后主要包含：

- `mymoney.sqlite`：账本数据所在文件。
- `backup_info`：账户头像、昵称等备份元信息。

但是该 `.sqlite` 文件被随手记官方魔改，以一种“防君子”的方式。参照[博客](https://www.52pojie.cn/thread-1833243-1-1.html)，截至2026年6月，版本号 `Android 13.2.48.0`，该文件只是前 16 个字节被替换，导致普通 SQLite 工具无法直接打开。

标准 SQLite 文件头是：`SQLite format 3\0`，对应 16 字节：`53 51 4C 69 74 65 20 66 6F 72 6D 61 74 20 33 00`，而随手记样本中的 `mymoney.sqlite` 前 16 字节被替换为：`00 00 00 00 00 00 00 00 00 00 00 00 00 46 FF 00`。因此恢复方式是把 `mymoney.sqlite` 的前 16 字节改回标准 SQLite 文件头：

```powershell
python .\scripts\process_backup_kbf.py <导出的kbf文件>.kbf -o recovered\mymoney.sqlite
```

脚本会：

1. 判断输入是否为 ZIP 格式的 `.kbf`。
2. 从 `.kbf` 中读取 `mymoney.sqlite`。
3. 恢复前 16 字节 SQLite 文件头。
4. 使用 Python 标准库 `sqlite3` 打开数据库。
5. 执行完整性检查和表结构探测。
6. 如果成功，将恢复后的数据库写到 `-o` 指定路径。

最终需要保存并提交给 App 以初始化账本的文件是 `recovered/mymoney.sqlite`。这个文件是真实账本数据，已被 `.gitignore` 忽略，绝对不要提交。

**验证账本记录**

提取完成后，可以验证 `recovered/mymoney.sqlite` 中最近或最早的收入/支出记录：

```powershell
python .\test\verify_record.py recovered\mymoney.sqlite
python .\test\verify_record.py recovered\mymoney.sqlite --order earliest
python .\test\verify_record.py recovered\mymoney.sqlite --order earliest --json
```

## 导出的 SQLite 如何存储记账数据

恢复后的数据库中，普通记账流水主要存储在 `t_transaction`，分类信息存储在 `t_category`。

`t_transaction` 是流水表。验证脚本使用到的字段如下：

- `transactionPOID`：流水主键。
- `type`：流水方向。当前样本中，`0` 表示支出，`1` 表示收入。
- `tradeTime`：记账时间，Unix 毫秒时间戳。
- `sellerCategoryPOID`：支出分类 ID，适用于 `type = 0` 的记录。
- `sellerMoney`：支出金额，适用于 `type = 0` 的记录。
- `buyerCategoryPOID`：收入分类 ID，适用于 `type = 1` 的记录。
- `buyerMoney`：收入金额，适用于 `type = 1` 的记录。
- `createdTime`：记录创建时间，Unix 毫秒时间戳。
- `modifiedTime`：记录修改时间，Unix 毫秒时间戳。

`t_category` 是分类表。验证脚本使用到的字段如下：

- `categoryPOID`：分类主键。
- `name`：分类名称。
- `parentCategoryPOID`：父分类 ID，用于从二级分类找到一级分类。
- `depth`：分类层级。当前样本中，普通一级分类为 `depth = 1`，普通二级分类为 `depth = 2`。
- `path`：分类路径，例如 `/-1/<一级分类ID>/<二级分类ID>/`。
- `type`：分类方向。当前样本中，`0` 表示支出分类，`1` 表示收入分类。

查询收入或支出流水时：

1. 从 `t_transaction` 中筛选 `type in (0, 1)` 的记录。
2. 查询最近一条时按 `tradeTime desc, transactionPOID desc` 排序。
3. 查询最早一条时按 `tradeTime asc, transactionPOID asc` 排序。
4. 如果 `type = 0`，分类 ID 取 `sellerCategoryPOID`，金额取 `sellerMoney`。
5. 如果 `type = 1`，分类 ID 取 `buyerCategoryPOID`，金额取 `buyerMoney`。
6. 将分类 ID 关联到 `t_category.categoryPOID`，得到当前分类。
7. 如果当前分类是二级分类，再将 `t_category.parentCategoryPOID` 关联回 `t_category.categoryPOID`，得到一级分类。

## Flutter App 当前进度

Flutter 记账 App 代码放在 `app/`。当前阶段目标不是一次性做完完整记账软件，而是先跑通最小闭环：选择恢复后的 SQLite 文件，复制为 App 管理的账本文件，执行 App 自己的 schema 增广迁移，通过独立 importer 层读取随手记流水和分类，并在列表中展示最近流水。

工程已经在 `app/` 下生成，平台包含 Android 和 iOS。生成命令是：

```powershell
cd app
flutter create . --platforms=android,ios --project-name fuckssj
```

当前目录结构按下列职责划分：

```text
app/
  lib/
    main.dart
    src/
      app/          # Flutter App 入口、路由、主题
      core/         # 通用错误、时间、金额、文件工具，当前暂未展开
      data/         # App 管理的账本数据库，可基于导入的 SQLite 做兼容迁移和增广
      features/     # 记账、账本、分类、账户、设置等功能模块
      importer/     # 随手记读取与兼容处理逻辑
  test/
```

当前已接入的关键依赖包括 `file_picker`、`sqlite3`、`sqlite3_flutter_libs`、`path_provider`、`path`、`flutter_secure_storage`、`local_auth`、`flutter_riverpod` 和 `intl`。目前 UI 很薄，只做导入 SQLite、新建空白账本、展示流水列表；安全存储和生物识别依赖已经接入，但实际保护流程还没有实现。

当前已实现：

- `LedgerRepository`：负责把用户选择的 SQLite 复制到 App 文档目录下的 `ledgers/` 子目录，创建空白账本，并执行 App 自己的 schema 迁移。
- App 自有增广表：`app_schema_migrations`、`app_ledger_metadata`、`app_transaction_extensions`、`app_attachment_metadata`，并把 `pragma user_version` 设置为 `1`。
- `SuiShouJiImporter`：只在 importer 层读取随手记原始表 `t_transaction` 和 `t_category`，查询最近 200 条收入/支出流水，并处理一级/二级分类名称。
- `LedgerHomePage`：支持选择 `.sqlite`、`.sqlite3`、`.db`、`.db3` 文件，导入后展示最近流水；也支持新建空白账本。
- importer 单元测试：覆盖收入流水、支出流水、二级分类回溯和空白账本识别。
- Android `MainActivity` 已改为 `FlutterFragmentActivity`，为后续 `local_auth` 做准备。

这个设计的核心边界是：随手记原始表结构只由 importer 层直接读取，App 账本层可以复用导入得到的 SQLite 文件，但必须管理自己的兼容迁移和必要增广；后续不要把随手记当前版本的原始表结构当成长期不变的业务契约。

## Android 构建配置

当前网络环境不走 tun，因此生成 Flutter 工程后已经把 Android 侧 Gradle 仓库替换为国内镜像。新 Flutter 模板使用 Kotlin DSL，相关位置是 `app/android/settings.gradle.kts` 和 `app/android/build.gradle.kts`，其中 `google()`、`mavenCentral()` 和 `gradlePluginPortal()` 不应保留，当前使用：

```kotlin
maven { url = uri("https://maven.aliyun.com/repository/google") }
maven { url = uri("https://maven.aliyun.com/repository/central") }
maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
```

Gradle Wrapper 下载 Gradle 发行包时不走 Maven 仓库，因此还需要单独修改 `app/android/gradle/wrapper/gradle-wrapper.properties`。当前已经把官方 `services.gradle.org` 替换为腾讯 Gradle 镜像：

```properties
distributionUrl=https\://mirrors.cloud.tencent.com/gradle/gradle-9.1.0-bin.zip
```

项目使用 JDK 21 构建 Android。不要使用 JDK 26 跑当前 Gradle 9.1.0 / Android Gradle Plugin 9.0.1 / Kotlin 2.3.20 这套构建链；JDK 26 会触发 `Unsupported class file major version 70`。当前本机可用配置是 `JAVA_HOME=D:\environments\jdk-21.0.1`、Android SDK 是 `D:\environments\Android`、Flutter 是 `D:\environments\flutter`。

Windows 下 Flutter 插件源码在 Pub Cache（例如 `C:\Users\...\Pub\Cache`）而项目在 `D:\softwares\fuckssj` 时，Kotlin 增量编译可能因为跨盘符路径报 `this and base files have different roots`。当前已在 `app/android/gradle.properties` 中加入：

```properties
kotlin.incremental=false
```

`file_picker` 当前会触发 Flutter 的 Built-in Kotlin 迁移提示：`Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): file_picker`。这只是未来兼容性警告，不影响当前构建；后续如果 `file_picker` 发布支持 Built-in Kotlin 的版本，再升级处理。

## 构建与运行

第一次构建前建议确认环境变量：

```powershell
$env:JAVA_HOME="D:\environments\jdk-21.0.1"
$env:ANDROID_HOME="D:\environments\Android"
$env:PUB_HOSTED_URL="https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
```

安装依赖：

```powershell
cd D:\softwares\fuckssj\app
flutter pub get
```

短验证命令：

```powershell
flutter analyze
flutter test
```

当前这两项均已通过。真机调试命令如下，当前 Android USB 设备序列号是 `2FD0221319026163`：

```powershell
flutter run -d 2FD0221319026163
```

首次成功构建过程中，Gradle 自动下载并安装了 Android SDK 里的 CMake 3.22.1，这是 `sqlite3_flutter_libs` 等 native 依赖构建需要的工具。当前已经成功生成、安装并启动 debug APK，输出中出现过：

```text
√ Built build\app\outputs\flutter-apk\app-debug.apk
Installing build\app\outputs\flutter-apk\app-debug.apk...
Syncing files to device NOH AN01...
```

如果 `flutter run` 再次遇到看似已经修复的 JDK 错误，优先执行：

```powershell
cd D:\softwares\fuckssj\app\android
.\gradlew.bat --stop
```

如果遇到 Kotlin 编译缓存、跨盘符或缓存损坏类错误，优先执行：

```powershell
cd D:\softwares\fuckssj\app
flutter clean
flutter pub get
```

## VS Code 环境注意事项

Windows Terminal 中环境正常，不代表已打开的 VS Code 集成终端也会立刻拿到新的环境变量。VS Code 主进程会继承启动时的环境；在系统环境变量、JDK、Android SDK 或 Flutter 路径调整后，仅在 VS Code 里新建终端可能仍然不够，必须关闭所有 VS Code 窗口并重启 VS Code。

`flutter doctor --verbose` 的 `Network resources` 检查会直接访问 `https://maven.google.com/`，它不读取本项目的 Gradle 镜像配置；因此在不开 tun 时 doctor 的网络资源检查失败，不等于本项目 Gradle 构建一定失败。真正需要看的是 `flutter run` 日志里是否还访问 `services.gradle.org`、`maven.google.com`、`repo.maven.apache.org` 或 `plugins.gradle.org`。

## 后续功能方向

1. 完善多账本管理：账本名称、备注、列表、打开最近账本和导出。
2. 建立 App 自有业务表或稳定视图，逐步把随手记 importer 输出迁移为 App 内部长期模型。
3. 实现基础记账、编辑、删除、分类选择、账户选择和金额输入。
4. 实现查询列表的日期筛选、分类筛选、收入/支出筛选和关键字搜索。
5. 设计分类、账户、币种、附件和加密保护的数据结构。
6. 接入安全设置：密码、系统生物识别、密钥管理和账本文件加密；注意已经导出的文件不应被误认为仍受 App 内加密保护。
