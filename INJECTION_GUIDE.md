# AutoClicker.dylib 注入指南

## 功能说明

dylib注入后会在屏幕上显示一个悬浮按钮，具有以下功能：

- **点击按钮**：开始/停止自动点击（1秒间隔）
- **长按按钮**：拖动移动按钮位置
- **自动点击位置**：以按钮所在位置为点击目标

按钮状态：
- 🔵 **蓝色**：停止状态（显示 ▶ 图标）
- 🔴 **红色**：运行状态（显示 ■ 图标）

---

## 编译dylib

### 方案一：有Mac环境（推荐）

在macOS上使用Xcode命令行工具编译：

```bash
cd AutoClicker
make
```

编译成功后会生成 `AutoClicker.dylib`。

### 方案二：无Mac环境（GitHub Actions）

项目已配置GitHub Actions自动编译，无需Mac：

1. **创建GitHub仓库**：将项目上传到GitHub
2. **触发编译**：
   - 推送代码到main分支，自动触发编译
   - 或在GitHub仓库的Actions页面手动触发
3. **下载产物**：编译完成后在Actions页面下载 `AutoClicker.dylib`

**GitHub Actions配置文件**：`.github/workflows/build.yml`

### 方案三：无Mac环境（WSL2 + Theos）

在Windows的WSL2中使用Theos构建系统：

```bash
# 安装依赖
sudo apt update && sudo apt install build-essential git ruby

# 安装Theos
git clone --recursive https://github.com/theos/theos.git ~/theos
echo "export THEOS=~/theos" >> ~/.bashrc
source ~/.bashrc

# 下载iOS SDK（需要自行获取）
# 将SDK放入 ~/theos/sdks/

# 创建Theos项目并编译
# 参考Theos官方文档
```

---

## 方法一：使用insert_dylib注入（推荐）

### 1. 安装insert_dylib

```bash
brew install insert_dylib
```

### 2. 准备目标APP

从设备导出APP：

```bash
# 使用frida-ps查看已安装的APP
frida-ps -U

# 使用ipatool导出IPA（需越狱）
ipatool download --bundle-identifier com.example.app
```

或从TrollStore安装的APP中提取：

```bash
cp -r /var/containers/Bundle/Application/XXX/YourApp.app ~/Desktop/
```

### 3. 使用注入脚本

```bash
chmod +x inject.sh
./inject.sh ./AutoClicker.dylib ~/Desktop/YourApp.app/YourApp
```

### 4. 重签名APP

```bash
codesign -f -s - --entitlements entitlements.plist ~/Desktop/YourApp.app
```

---

## 方法二：IPA内嵌dylib

### 1. 解压IPA

```bash
unzip YourApp.ipa -d YourApp_temp
```

### 2. 复制dylib到Frameworks目录

```bash
cp AutoClicker.dylib YourApp_temp/Payload/YourApp.app/Frameworks/
```

### 3. 修改Mach-O文件

使用insert_dylib或optool：

```bash
insert_dylib --weak @rpath/AutoClicker.dylib \
    YourApp_temp/Payload/YourApp.app/YourApp \
    YourApp_temp/Payload/YourApp.app/YourApp.new
mv YourApp_temp/Payload/YourApp.app/YourApp.new \
    YourApp_temp/Payload/YourApp.app/YourApp
chmod +x YourApp_temp/Payload/YourApp.app/YourApp
```

### 4. 重签名

```bash
cd YourApp_temp/Payload
codesign -f -s - YourApp.app/Frameworks/AutoClicker.dylib
codesign -f -s - --entitlements entitlements.plist YourApp.app
```

### 5. 重新打包IPA

```bash
cd YourApp_temp
zip -r ../YourApp_modified.ipa *
```

---

## 部署到设备

### 使用TrollStore安装

1. 将修改后的IPA发送到设备
2. 在TrollStore中打开IPA进行安装

### 使用filza直接替换

1. 将dylib上传到设备的 `/var/containers/Bundle/Application/XXX/YourApp.app/Frameworks/`
2. 使用insert_dylib在设备上修改Mach-O
3. 重启APP

---

## 使用方法

1. 启动注入了dylib的APP
2. 屏幕右侧会出现一个蓝色的悬浮按钮
3. **长按按钮** 并拖动到想要自动点击的位置
4. **点击按钮** 开始自动点击（按钮变为红色）
5. **再次点击按钮** 停止自动点击（按钮恢复蓝色）

---

## 注意事项

1. **需要越狱设备**：TrollStore支持iOS 14.0-16.4.1
2. **需要macOS环境编译**（iOS交叉编译）
3. **自动点击间隔固定为1秒**
4. **点击位置为按钮中心点**
5. **性能影响**：1秒间隔的点击对性能影响很小
6. **安全风险**：自动点击可能违反APP使用条款，请谨慎使用

---

## 常见问题

### Q: 编译失败
A: 确保安装了Xcode命令行工具：`xcode-select --install`

### Q: 注入后APP闪退
A: 检查dylib架构是否匹配，确保使用arm64编译

### Q: 悬浮按钮不显示
A: 确认APP已正确注入dylib，检查代码签名是否正确

### Q: 点击不生效
A: 某些APP可能有防作弊机制，自动点击可能被检测到

---

## 技术说明

- 使用IOKit的IOHIDEvent系统模拟真实触摸事件
- 使用独立UIWindow（windowLevel = UIWindowLevelAlert + 1）确保浮在所有内容之上
- 使用Method Swizzling hook UIApplication的didFinishLaunchingWithOptions确保正确时机初始化
- 长按拖动使用UILongPressGestureRecognizer实现
- 点击切换使用UIControlEventTouchUpInside实现