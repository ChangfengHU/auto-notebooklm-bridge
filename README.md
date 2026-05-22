# auto-notebooklm-bridge

让你的 AI Agent（Claude / Cursor / Codex 等）直接调用 NotebookLM 的能力——创建笔记本、添加内容源、深度研究、生成脑图/报告/音频——无需手动打开浏览器。

---

## 角色说明

| 角色 | 职责 |
|------|------|
| **生产者（Producer）** | 部署一台有 NotebookLM 登录态的机器，暴露公网 Bridge |
| **消费者（Consumer）** | 安装消费者 skill，直接让 agent 说话调用 NotebookLM |

消费者机器**不需要登录 NotebookLM**，也不需要部署任何服务。

---

## 生产者：部署 Bridge

### 第一步：安装 Producer Skill

在需要部署的机器上执行：

```bash
bash <(curl -fsSL "https://skill.vyibc.com/install-notebooklm-bridge-release.sh?v=$(date +%s)")
```

安装时选择你使用的 AI 工具（Cursor / Claude / Codex 等）。

### 第二步：让 Agent 执行部署

安装完成后，对你的 agent 说：

```
使用 notebooklm-bridge-release 部署 NotebookLM Bridge
```

部署流程自动完成：
1. 安装 notebooklm CLI
2. 引导登录 NotebookLM（首次需要浏览器授权，此后跨机器自动恢复）
3. 启动本地 HTTP Bridge（端口 18800）
4. 获取公网域名（auto-domain 自动分配）
5. 发布消费者 skill，输出安装命令

### 第三步：把消费者命令发给别人

部署成功后输出类似：

```bash
bash <(curl -fsSL "https://skill.vyibc.com/notebooklm-bridge/<machine-id>/release/install-notebooklm-bridge.sh?v=$(date +%s)")
```

把这条命令发给任何想用 NotebookLM 的人即可。

---

## 消费者：安装 Skill 并使用

### 第一步：安装 Consumer Skill

执行生产者给你的安装命令：

```bash
bash <(curl -fsSL "https://skill.vyibc.com/notebooklm-bridge/<machine-id>/release/install-notebooklm-bridge.sh?v=$(date +%s)")
```

安装到你的 AI 工具（Claude / Cursor 等）。

### 第二步：直接和 Agent 说话

安装后 skill 已内置公网地址和 token，无需任何配置，直接对 agent 发指令即可。

---

## 消费者使用示例

### 场景一：建立论文研究笔记本

```
帮我创建一个关于"LLM 微调技术"的 NotebookLM 笔记本，
添加以下论文作为内容源：
- https://arxiv.org/abs/2305.11206
- https://arxiv.org/abs/2106.09685
- https://arxiv.org/abs/2312.10997
添加完后告诉我处理状态。
```

---

### 场景二：深度研究 + 生成脑图

```
用 notebooklm-bridge，对"LLM 微调技术"笔记本做深度分析，
生成一张思维导图，完成后把结果保存到我的桌面。
```

---

### 场景三：生成研究报告

```
对"LLM 微调技术"笔记本生成一份中文研究报告，
内容聚焦在 LoRA、QLoRA、RLHF 这几个方向的对比，
完成后把报告内容输出给我。
```

---

### 场景四：Agent 协作专题研究

```
帮我创建一个关于"Multi-Agent 协作系统"的 NotebookLM 笔记本，
添加这些内容：
- https://arxiv.org/abs/2308.08155  （AutoGen 论文）
- https://arxiv.org/abs/2309.07864  （AgentVerse 论文）
- https://www.anthropic.com/research/claude-agent

然后让 NotebookLM 回答：这几个框架在任务分配机制上有什么核心差异？

最后生成一张对比脑图和一份闪卡，方便我复习。
```

---

### 场景五：生成播客音频

```
对"LLM 微调技术"笔记本生成一段 Audio Overview（播客风格的内容概览），
完成后给我下载链接。
```

---

### 场景六：查看和整理已有笔记本

```
列出我所有的 NotebookLM 笔记本，
找出关于"AI Agent"主题的，给我一个简要摘要。
```

---

## Skill 能力一览

消费者 skill 让 agent 具备以下能力，全部通过自然语言驱动：

| 能力 | 说明 |
|------|------|
| 笔记本管理 | 创建、列出、重命名、删除、获取摘要 |
| 添加内容源 | YouTube 视频、论文链接、网页、Google Drive |
| AI 对话 | 向笔记本提问、获取对话历史 |
| 生成产物 | 思维导图、研究报告、测验、闪卡、幻灯片、信息图、音频概览 |
| 下载产物 | 获取生成内容的下载链接或直接保存到本地 |
| 笔记管理 | 创建、列出笔记，保存对话为笔记 |

---

## 常见问题

**Q: 消费者需要 NotebookLM 账号吗？**
不需要。登录态在生产者机器上，消费者只调用公网 Bridge。

**Q: Bridge 断了怎么办？**
生产者机器会自动重连并保持公网域名不变。如果生产者重新部署，需要重新发消费者安装命令（因为 token 会更新）。

**Q: 支持多个消费者同时使用吗？**
支持。同一个 token 可以多人共用，任务队列自动管理。

**Q: 跨机器重新部署生产者，消费者需要重新安装吗？**
如果公网域名和 token 不变，不需要。否则需要重新安装消费者 skill。
