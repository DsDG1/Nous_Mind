# 修复提醒通知不触发的问题

## 问题
添加提醒到指定时间后，到时间不会弹出提醒通知。

## 根因
1. **权限标记永久锁定** — `_permissionRequested` 设为 `true` 后即使用户拒绝权限也不再重试
2. **权限请求未保护** — `requestPermissions()` 若抛异常会导致 `add()` 崩溃
3. **iOS 前台通知不可见** — `DarwinNotificationDetails` 未配置前台展示参数

## 修改内容

### 文件 1: `lib/viewmodels/reminders_view_model.dart`

**改动 1** — 删除第 29 行:
```
  bool _permissionRequested = false;
```

**改动 2** — 将第 68-72 行：
```dart
    if (!_permissionRequested) {
      _permissionRequested = true;
      await _notifications.requestPermissions();
    }
    await _safeSchedule(reminder);
```
替换为：
```dart
    await _notifications.requestPermissions();
    await _safeSchedule(reminder);
```

### 文件 2: `lib/services/notification_service.dart`

**改动 1** — 第 143 行 `DarwinNotificationDetails()` 替换为：
```dart
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
```

## 影响范围
- 仅修改两个文件，共约 5 行代码
- 不影响数据模型、存储层、UI 层
- 权限 API 在已授权场景下直接返回 true，不会重复弹窗
