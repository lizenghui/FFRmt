# FFRmt

ffmpeg remote - 远程任务处理系统

## 系统概述

FFRmt 是一个基于 systemd 的远程任务处理系统，使用 rclone 进行远程存储同步，支持定时任务获取和处理。

## 部署文档

### 1. 系统要求

- Linux 系统（支持 systemd）
- rclone（配置好远程存储）
- ffmpeg
- bash

### 2. 安装步骤

#### 2.1 克隆项目

```bash
git clone <repository-url>
cd FFRmt
```

#### 2.2 配置 rclone

确保 rclone 已正确配置远程存储，远程存储名称为 `jdcloud`，包含以下目录：
- `jdcloud:tasks/pending` - 待处理任务
- `jdcloud:tasks/running` - 正在运行的任务

#### 2.3 配置 systemd 服务文件

项目提供了三个示例服务文件，使用前需要根据您的实际环境进行修改：

**示例文件说明：**
- `FFRmt.service.example` - 主服务文件（任务获取服务）
- `FFRmt@.service.example` - 模板服务文件（任务处理服务）
- `FFRmt.timer.example` - 定时器配置文件

**使用方法：**
```bash
# 复制示例文件
cp FFRmt.service.example FFRmt.service
cp FFRmt@.service.example FFRmt@.service
cp FFRmt.timer.example FFRmt.timer

# 编辑服务文件，修改以下配置：
# 1. WorkingDirectory 路径
# 2. ExecStart 路径
# 3. 如需自定义基础目录，取消 Environment 行注释并设置路径
```

#### 2.4 配置基础目录

FFRmt 支持通过环境变量配置基础工作目录：

- **环境变量**: `FFRMT_BASE_DIR`
- **默认值**: `$HOME/FFRmt` (通常是 `/root/FFRmt`)

在 systemd 服务中配置基础目录：

**方法 1: 修改服务文件（推荐）**

只需编辑 `/etc/systemd/system/FFRmt.service`，在 `[Service]` 部分添加环境变量配置：

```ini
[Service]
Type=oneshot
WorkingDirectory=/root/FFRmt
# 重要：在此配置基础目录，FFRmt@.service 会自动继承
Environment="FFRMT_BASE_DIR=/your/custom/path"
ExecStart=/bin/bash /root/FFRmt/fetch-task.sh
```
#### 3.2 重新加载 systemd

```bash
sudo systemctl daemon-reload
```

#### 3.3 启用定时器

```bash
sudo systemctl enable FFRmt.timer
sudo systemctl start FFRmt.timer
```

### 4. 服务说明

#### 4.1 FFRmt.service
- **类型**: oneshot
- **功能**: 获取待处理任务并启动处理服务
- **触发**: 由定时器每 10 秒触发一次

#### 4.2 FFRmt@.service
- **类型**: simple
- **功能**: 处理指定任务
- **参数**: 任务 ID
- **触发**: 由 FFRmt.service 动态启动

#### 4.3 FFRmt.timer
- **触发间隔**: 每 10 秒
- **启动延迟**: 系统启动后 10 秒开始
- **精度**: 1 秒

### 5. 管理服务

#### 5.1 查看服务状态
```bash
sudo systemctl status FFRmt.timer
sudo systemctl status FFRmt.service
```

#### 5.2 查看日志
```bash
sudo journalctl -u FFRmt.timer -f
sudo journalctl -u FFRmt.service -f
sudo journalctl -u FFRmt@*.service -f
```

#### 5.3 重启服务
```bash
sudo systemctl restart FFRmt.timer
```

### 6. 任务格式

任务文件应为 `.task` 扩展名，包含任务处理所需的配置信息。

### 7. 工作目录结构

基础目录下会自动创建 `tasks` 子目录用于存储本地任务文件：
```
$FFRMT_BASE_DIR/
└── tasks/
    └── *.task
```

### 8. 故障排查

#### 8.1 检查环境变量
```bash
sudo systemctl show-environment | grep FFRMT
```



#### 8.3 权限问题
确保运行用户对基础目录有读写权限：
```bash
sudo chown -R $USER:$USER $FFRMT_BASE_DIR