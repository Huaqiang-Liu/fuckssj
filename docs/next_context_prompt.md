# 下一轮对话提示词

请在 `D:\softwares\fuckssj` 这个项目中继续开发。项目目标是做一个 Flutter
记账 App，以及随手记 `.kbf` 备份迁移脚本。

当前已完成：

- Python 脚本 `scripts/process_backup_kbf.py` 可以从随手记 `.kbf` 中提取并恢复
  `mymoney.sqlite`。
- Python 验证脚本 `test/verify_record.py` 可以读取恢复后的 SQLite，验证最近或
  最早一条收入/支出流水。
- README 已说明随手记 `.kbf` 的 ZIP 本质、`mymoney.sqlite` 前 16 字节魔改方式、
  恢复命令、以及 `t_transaction`/`t_category` 中记账数据的存储规则。
- 本地 `recovered/mymoney.sqlite` 是真实账本数据，已被 `.gitignore` 忽略，绝对
  不要提交。

开发方向：

- 使用 Flutter 开发 App，代码放在 `app/`。
- 后续需要支持 Android 和 iOS，因此不要使用只适合 Android 的业务架构。
- Android 调试优先使用 USB 真机和 `adb`，当前设备序列号是
  `2FD0221319026163`。
- App 需要支持从 `recovered/mymoney.sqlite` 导入随手记数据，也需要支持新建空白
  账本。
- App 内部应设计自己的干净数据库 schema，不要长期直接依赖随手记原始表结构。
- 随手记导入逻辑应隔离在 importer 层。

环境信息：

- `JAVA_HOME=D:\environments\jdk-26.0.1`
- Android SDK：`D:\environments\Android`
- Flutter：`D:\environments\flutter`
- 用户已手动运行 `flutter doctor -v`，结果无问题。
- `PUB_HOSTED_URL=https://pub.flutter-io.cn`
- `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`

重要网络要求：

由于当前环境不想开 tun，Flutter 的 pub 下载已配置国内镜像；但 Android 首次构建
仍可能因为 Gradle 访问 `maven.google.com`、Google Maven 或 Maven Central 卡住。
生成 Flutter 工程后必须检查 Android 侧 Gradle 仓库配置，把 `google()` 和
`mavenCentral()` 替换为阿里云 Maven 镜像。新 Flutter 模板通常在
`app/android/settings.gradle` 配置仓库，旧模板可能在 `app/android/build.gradle`
配置仓库。至少使用：

```gradle
maven { url = uri("https://maven.aliyun.com/repository/google") }
maven { url = uri("https://maven.aliyun.com/repository/central") }
maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
```

下一步建议：

1. 在 `app/` 下生成 Flutter 工程，平台包含 Android 和 iOS。
2. 立即修改 Android 侧 Gradle 仓库配置为阿里云 Maven 镜像。
3. 添加基础依赖，优先考虑文件选择、SQLite、状态管理、安全存储和生物识别：
   `file_picker`、`sqlite3`/`drift` 或等价方案、`flutter_secure_storage`、
   `local_auth`。
4. 先实现最小闭环：选择 SQLite 文件 -> 读取随手记流水和分类 -> 导入到 App 自有
   schema -> 展示流水列表。
