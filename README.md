# Gadgets
Some scripts or components assist scientific research


## 1.task_montior_byPushplus.sh

🎯 SLURM / 进程监控 + PushPlus 推送脚本

该脚本用于定时监控当前用户的 SLURM 作业或特定后台进程，并在任务状态变更时通过 [PushPlus](https://www.pushplus.plus) 推送通知（支持 Markdown 格式美化显示）。适用于远程服务器自动化任务播报，特别适用于 HPC 作业监控。

### 🚀 使用方法

1. **配置参数（前几行）**
   ```bash
   APPKEY="你的 PushPlus token"
   CHECK_SLURM_ONLY=1             # 1 表示监控 SLURM 作业，0 表示监控后台进程
   SLURM_STATE_FILTER=("R")       # 可选过滤状态，如 "R"（运行中）
   KEYWORDS=("lammps")            # 要监控的关键词（用于筛选任务名或命令行）
   INTERVAL=7200                  # 每次检查间隔（单位：秒）
   ```

2. **启动脚本**
   ```bash
   bash task_monitor_push.sh
   ```

3. **查看日志**
   - `monitor.log`: 推送与变更检测记录
   - `last_tasks.txt`: 上次推送的任务列表快照

4. **强制退出**
   ```bash
   pkill -f task_monitor_push.sh
   ```

---

### ✨ 特性亮点

- ✅ 支持 SLURM 作业状态监控（基于 `squeue`）
- ✅ 支持关键词过滤的后台进程监控（基于 `ps`）
- ✅ 支持任务变更智能识别，避免重复推送
- ✅ 消息通过 PushPlus 推送，可用微信、邮件、企业微信等多端接收
- ✅ 使用 Markdown 模板美化推送内容

---

### 📦 示例推送内容

```
### 🎯 任务更新通知

- 📍 主机：`10.1.0.23`
- 👤 用户：`cgao`
- 📌 检测到 `3` 个匹配任务

#### 当前任务列表：

42012 [R] lmp_sim - 用时 00:23:01

42014 [PD] lmp_test - 用时 00:00:00

> 运行中：1，排队中：1
```

---

