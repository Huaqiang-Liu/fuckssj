# App 目录

这里预留给 Flutter 记账 App。

建议下一步在本目录生成 Flutter 工程：

```powershell
flutter create . --platforms=android,ios
```

生成后需要立即检查 Android 侧 Gradle 仓库配置。由于当前网络环境不走 tun，不要直接依赖 `google()` 和 `mavenCentral()` 拉取依赖；需要改为阿里云 Maven 镜像。不同 Flutter/Gradle 模板位置可能不同：

- 新模板通常在 `android/settings.gradle` 的 `pluginManagement.repositories` 和 `dependencyResolutionManagement.repositories` 中配置仓库。
- 旧模板可能在 `android/build.gradle` 的 `buildscript.repositories` 和 `allprojects.repositories` 中配置仓库。

核心原则：看到 `google()` 和 `mavenCentral()` 时，替换为阿里云镜像源，至少包含：

```gradle
maven { url = uri("https://maven.aliyun.com/repository/google") }
maven { url = uri("https://maven.aliyun.com/repository/central") }
maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
```

## 计划结构

```text
app/
  lib/
    main.dart
    src/
      app/          # Flutter App 入口、路由、主题
      core/         # 通用错误、时间、金额、文件工具
      data/         # App 管理的账本数据库，可基于导入的 SQLite 做兼容迁移和增广
      features/     # 记账、账本、分类、账户、设置等功能模块
      importer/     # 从 recovered/mymoney.sqlite 读取随手记数据并做兼容处理
  assets/
  test/
```
