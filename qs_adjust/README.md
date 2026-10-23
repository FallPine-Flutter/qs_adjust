# qs_adjust

基于官方 `adjust_sdk` 的 Flutter 归因封装，提供 ASA（Apple Search Ads）判断、Adjust 初始化、归因数据 AES 加密上报及失败重试。

本插件需要配合自有归因接收接口使用，初始化时必须提供上报配置。

## 安装

在 `pubspec.yaml` 中添加：

```yaml
dependencies:
  qs_adjust: ^1.0.0
```

然后执行：

```bash
flutter pub get
```

### 环境与平台

- Dart：`^3.11.5`。
- Flutter：`>=3.3.0`，同时需要满足上述 Dart 版本要求。
- iOS：本插件的最低部署版本为 iOS 13.0；宿主仍需满足实际解析的依赖要求。
- 官方 Adjust Flutter SDK 依赖约束：`adjust_sdk: ^5.8.0`。

包声明了 Android 和 iOS 平台，但当前归因流程包含 ASA 判断，且上传的 `platform` 固定为 `ios`。接入 Android 前需要单独适配，不能直接按跨平台归因方案使用。

## 快速接入

在 Flutter 绑定初始化后调用 `QsAdjust.initialize`。下面的配置值需要替换为实际 Adjust App Token、接口地址及服务端约定的加密参数。

```dart
import 'package:flutter/widgets.dart';
import 'package:qs_adjust/qs_adjust.dart';

void initializeAttribution() {
  WidgetsFlutterBinding.ensureInitialized();

  QsAdjust.initialize(
    appToken: 'YOUR_ADJUST_APP_TOKEN',
    skipAsaCheck: false,
    reportConfig: const QsAdjustReportConfig(
      apiUrl: 'https://your-domain.example/api/attribution',
      aesSecretKey: 'YOUR_AES_SECRET_KEY',
      aesIv: 'YOUR_AES_IV',
      aesSctToken: 'YOUR_SCT_TOKEN',
      packageName: 'com.example.app',
      iosAppId: 'YOUR_APP_STORE_ID',
      apiParameterNameModel: QsAdjustApiParameterNameModel(
        iosAppId: 'iosAppId',
        packageName: 'packageName',
        userId: 'userId',
        adjustAdid: 'adjustAdid',
        trackerToken: 'trackerToken',
        trackerName: 'trackerName',
        network: 'network',
        campaign: 'campaign',
        campaignId: 'campaignId',
        adgroup: 'adgroup',
        adgroupId: 'adgroupId',
        creative: 'creative',
        creativeId: 'creativeId',
        clickLabel: 'clickLabel',
        costType: 'costType',
        costAmount: 'costAmount',
        costCurrency: 'costCurrency',
        platform: 'platform',
        appVersion: 'appVersion',
        rawData: 'rawData',
      ),
    ),
  );
}
```

`initializeAttribution` 是示例中的宿主方法，应在应用启动流程中调用。`QsAdjust.initialize` 返回 `void`，初始化准备在后台执行，不能通过 `await` 等待完成；首次调用保存配置，后续调用不覆盖。

`QsAdjustApiParameterNameModel` 的 20 个参数全部必填，值代表加密内容中的接口字段名，请按服务端协议填写，并确保字段名互不重复。示例使用同名字段，仅用于展示配置方式。

### 初始化规则

1. 先读取持久化上报成功标记；已有成功记录时跳过 Adjust 初始化。
2. `skipAsaCheck: false` 时查询 ASA：`attribution == true` 时跳过 Adjust，`false` 时继续初始化；结果不明确或发生异常时后台重试。
3. `skipAsaCheck: true` 时跳过 ASA 查询，直接进入 Adjust 初始化，但仍检查上报成功标记。此选项可用于单独测试 Adjust。
4. Adjust 归因发生变化时，自动触发强制上报。

当前 SDK 配置如下，暂未提供外部配置入口：

| 配置 | 当前行为 |
| --- | --- |
| 环境 | Release 使用 production，其余模式使用 sandbox |
| 日志级别 | verbose |
| 设备标识 | 使用 `QsDeviceInfo.getUserId()` 设置 `externalDeviceId` 和全局回调参数 `external_device_id` |
| 成本数据 | 开启 |
| 后台发送 | 开启 |
| Adjust AdServices 处理 | 关闭 |
| ATT 等待时间 | 30 秒 |

ATT 等待配置不负责弹出授权提示；宿主需自行处理授权流程。代码中的“已初始化”仅表示 `Adjust.initSdk` 正常返回，不代表原生 SDK 联网或归因成功。

## 归因上报

除归因变化时自动上报外，也可以主动调用：

```dart
final success = await QsAdjust.reportAttributionInfo();
```

需要忽略已有成功缓存、重新上报时：

```dart
final success = await QsAdjust.reportAttributionInfo(forceReport: true);
```

可通过可选参数 `attribution` 传入官方 SDK 的 `AdjustAttribution` 对象；未传时，内部调用 `Adjust.getAttribution()` 获取。

### 返回值与重试

- `true`：本次上传成功，或 SDK 已初始化且普通调用命中了成功缓存。
- `false`：本次未成功，包括等待初始化、初始化被跳过、数据获取失败或上传失败。返回 `false` 时可能已安排后台补报。
- 上报不会主动初始化 SDK。尚未调用初始化或初始化仍在进行时，返回 `false` 并安排补报。
- 因成功记录或 ASA 判断而跳过初始化后，后续上报返回 `false`，`forceReport` 也不能绕过该状态。
- 数据获取失败时，补报会重新获取；上传失败时，补报复用已生成的密文。JSON 编码或 AES 加密失败时不重试。
- 初始化准备与上报各自按 2、5、10、20、40、60 秒的间隔重试，之后每 60 秒重试。
- 普通并发调用共用正在执行的结果；等待补报时再次主动调用会立即尝试。
- 上传期间的强制上报仅保留最新待执行归因，多个等待者共享该次结果。当前上传失败后继续执行待上报任务；当前上传成功时会清除待执行任务，等待者收到 `false`。

重试任务仅保存在内存中，进程退出后丢失；应用再次启动需要重新调用初始化及上报。计时器受应用运行状态影响，不保证系统挂起时执行。

成功标记的存储键为 `qs_adjust_attribution_info_report_success`，不区分用户或接口。成功记录会使后续进程跳过 SDK 初始化，因此这些进程不会接收 Adjust 归因变化回调。

### 服务端协议

插件将归因字段编码为 JSON，经 `qs_aes_encrypt` 加密后，通过 `qs_net_request` 发起 JSON POST 请求：

```http
POST <apiUrl>
sct: <aesSctToken>
Content-Type: application/json
```

```json
{
  "data": "<AES 加密后的内容>"
}
```

响应的 `code` 必须为数字 `0` 才判定成功，例如：

```json
{
  "code": 0,
  "message": "success"
}
```

`QsAdjustApiParameterNameModel` 只控制加密内容中的字段名，外层 `data`、请求头 `sct` 及响应字段 `code`、`message` 固定不变。加密参数必须与服务端解密配置一致。

### 加密内容

下表使用模型属性名表示字段，实际请求中的名称由调用方配置。

| 模型属性 | 数据来源或默认值 |
| --- | --- |
| `iosAppId`、`packageName` | 初始化配置 |
| `userId` | `QsDeviceInfo.getUserId()` |
| `adjustAdid` | `Adjust.getAdid()`，可能为 `null` |
| `trackerToken`、`trackerName`、`network`、`campaign` | Adjust 归因字段，缺失时为空字符串 |
| `adgroup`、`creative`、`clickLabel` | Adjust 归因字段，缺失时为空字符串 |
| `costType`、`costCurrency` | Adjust 归因字段，缺失时为空字符串 |
| `costAmount` | 转换为 `double`，缺失时为 `0.0` |
| `campaignId`、`adgroupId`、`creativeId` | 当前固定为空字符串 |
| `platform` | 当前固定为 `ios` |
| `appVersion` | `QsDeviceInfo.getAppVersion()`，可能为 `null` |
| `rawData` | 对 `AdjustAttribution.jsonResponse` 进行 JSON 解析，内容为空或解析失败时为 `null` |

## iOS Google ODM

当前 `ios/qs_adjust.podspec` 仅声明 Flutter 依赖，没有引入 `Adjust/AdjustGoogleOdm` 或 `GoogleAdsOnDeviceConversion`，因此安装本插件不会自动完成 Google 设备端转化衡量（ODM）集成。

如需 ODM，宿主项目需另行完成对应原生依赖与配置，并验证真机行为及后台结果。

## 许可证

[MIT License](LICENSE)
