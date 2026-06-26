# fuckssj

随手记曾经是界面美观、功能完备的记账软件，而现在是一个臃肿、卡顿、内购、关闭5秒开屏广告的按钮每次位置都不一样的记账软件。更令人难以接受的是，它把用户自己的账本数据锁在会员付费墙后。正常导出账本到结构化文件应当是基础能力，而不是拿来迫使用户开会员的筹码。用户理应有完全的权力，取得自己的记账数据，并选用其它记账软件。本项目提供随手记备份迁移脚本，以及一个轻量化的记账软件demo。

## 1. 从随手记备份中提取数据

**导出 `.kbf` 备份文件**

本项目不依赖随手记会员导出的 XLSX，而是使用随手记自己的备份文件。流程：
1. 在随手记 App 中进入账本主页右下角的设置。
2. 高级功能-备份与同步-本地备份与恢复-立即手动备份，得到一个 `.kbf` 文件，正常情况下位于 `Download/SsjBackup/ManualBackup` ，注意备份成功时给出的路径 `/storage/emulated/0/` 就视为本机文件根目录。
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

最终需要保存并提交给 App 以初始化账本的文件是 `recovered/mymoney.sqlite`

**验证账本记录**

提取完成后，可以验证 `recovered/mymoney.sqlite` 中最近/最早的收入或支出记录：

```powershell
python .\test\verify_record.py recovered\mymoney.sqlite
python .\test\verify_record.py recovered\mymoney.sqlite --order earliest
# 输出 JSON 格式
python .\test\verify_record.py recovered\mymoney.sqlite --order earliest --json
```

## 2. 导出的 SQLite 如何存储记账数据

恢复后的数据库中，普通记账流水主要存储在 `t_transaction`，分类信息存储在
`t_category`。

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
- `depth`：分类层级。当前样本中，普通一级分类为 `depth = 1`，普通二级分类
  为 `depth = 2`。
- `path`：分类路径，例如 `/-1/<一级分类ID>/<二级分类ID>/`。
- `type`：分类方向。当前样本中，`0` 表示支出分类，`1` 表示收入分类。

查询收入或支出流水时：

1. 从 `t_transaction` 中筛选 `type in (0, 1)` 的记录。
2. 查询最近一条时按 `tradeTime desc, transactionPOID desc` 排序。
3. 查询最早一条时按 `tradeTime asc, transactionPOID asc` 排序。
4. 如果 `type = 0`，分类 ID 取 `sellerCategoryPOID`，金额取 `sellerMoney`。
5. 如果 `type = 1`，分类 ID 取 `buyerCategoryPOID`，金额取 `buyerMoney`。
6. 将分类 ID 关联到 `t_category.categoryPOID`，得到当前分类。
7. 如果当前分类是二级分类，再将 `t_category.parentCategoryPOID` 关联回
   `t_category.categoryPOID`，得到一级分类。

## 轻量级记账软件

包含的功能（我暂时用得到的功能）：
1. 导入和导出账本，多账本命名、管理、备注。一个账本是一个 `.sqlite` 文件。
2. 主设置界面调节浅色/深色/跟随系统。
3. 记账，每条记账涉及：一级二级分类，收入和支出（金额默认人民币，可以修改成外币，可以在记账界面选择外币列表时跳转，或在主设置编辑常用外币以显示在列表，后续可以现场查询汇率，==注意：原版随手记不支持外币记录，可能需要增补数据库格式，即在导入外部数据库文件后可能需要修改==），记账时间，账目备注（文字和图片），金额计算器，一级二级所属账户（现金、信用卡、金融账户（银行卡/股票/基金）、虚拟账户（支付宝/微信/白条/公交卡/饭卡）、负债账户（应付款项）、债券账户（应收款项）
4. 查询和编辑账目，编辑和新建是同一个界面，查询时每个账户一个列表。可以筛选日期（几种方式：全部/自定义x年x月x日~y年y月y日/某年/某月/某星期），筛选分类，筛选支出或收入（或者都有）。可以搜索关键字（匹配分类和备注，严格匹配，字段可以留空但不能全空）
5. 自定义一级二级分类、一级二级所属账户、显示外币种类（设置时加上搜索）。分类用JSON文件维护（key-value+列表的模式很方便）。删除分类前要提示：删除分类也会删除其下流水，等待3秒，确认两遍。分类不可重名。修改分类名称后，涉及条目也自动修改。可以从记账/编辑界面跳转，也可以从主设置访问。
6. 安全性约束。账本默认明文存储在本地，但如果用户在设置中要求添加保护，可以添加密码/人脸/指纹，每次关闭后台都要重新验证，否则本地存储的所有账本文件将会加密——但是已经导出的文件不会加密（这点需要在加密设置界面提醒用户）。加密的密码学方式暂时不确定，要防止密钥明文存储在本地。

