# flux-panel转发面板 哆啦A梦转发面板

# 赞助商
<p align="center">
  <a href="https://vps.town" style="margin: 0 20px; text-align:center;">
    <img src="./doc/vpstown.png" width="300">
  </a>

  <a href="https://whmcs.as211392.com" style="margin: 0 20px; text-align:center;">
    <img src="./doc/as211392.png" width="300">
  </a>
</p>


本项目基于 [go-gost/gost](https://github.com/go-gost/gost) 和 [go-gost/x](https://github.com/go-gost/x) 两个开源库，实现了转发面板。
---
## 特性

- 支持按 **隧道账号级别** 管理流量转发数量，可用于用户/隧道配额控制
- 支持 **TCP** 和 **UDP** 协议的转发
- 支持两种转发模式：**端口转发** 与 **隧道转发**
- 可针对 **指定用户的指定隧道进行限速** 设置
- 支持配置 **单向或双向流量计费方式**，灵活适配不同计费模型
- 提供灵活的转发策略配置，适用于多种网络场景


## 部署流程
---
### Systemd 部署（二开版，无 Docker）

> 本二开版本已移除 Docker 相关文件（docker-compose、Dockerfile、Docker CI）与移动端
> （android-app / ios-app / flux.ipa）。
> 面板端使用 systemd 管理服务；数据库使用 **PostgreSQL**（无需 MySQL/MariaDB/SQLite）；
> 转发内核为 **go-gost v3.2.6 定制版**（见仓库 go-gost/ 目录，含 panel 扩展包：
> WebSocket 实时监控、流量上报、服务热重载）。

#### 一键安装（面板 + 节点内核）

```bash
curl -L https://raw.githubusercontent.com/bqlpfy/flux-panel/beta/install_panel_systemd.sh -o install_panel_systemd.sh
chmod +x install_panel_systemd.sh
./install_panel_systemd.sh
```

脚本自动完成：安装 JDK21 / Node20 / Maven / PostgreSQL → 构建后端与前端 →
初始化数据库（建库建用户，自动执行 schema.sql/data.sql）→ 部署 systemd 服务
`flux-backend`（Spring Boot + PG）→ 构建并部署节点内核 `flux_agent`
（go-gost v3.2.6 定制版，systemd 服务 `flux-agent`）。

常用参数：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `WITH_NGINX` | `0` | 设为 `1` 时代装并配置 nginx（反代 127.0.0.1:6365） |
| `WITH_NODE` | `1` | 是否安装节点内核 flux_agent（设为 `0` 仅装面板） |
| `NODE_PANEL_ADDR` | 本机 IP:6365 | 节点连接的面板地址 |
| `NODE_SECRET` | 空 | 节点密钥（在面板创建节点后填入） |
| `DB_NAME` / `DB_USER` / `DB_PASSWORD` | flux_panel / fluxuser / 随机 | PostgreSQL 配置 |
| `JWT_SECRET` | 随机 | JWT 密钥 |

示例（仅装面板，不装节点、代装 nginx）：

```bash
WITH_NODE=0 WITH_NGINX=1 ./install_panel_systemd.sh
```

#### 节点单独部署（已有一台面板时）

在节点机器上执行：

```bash
git clone -b beta https://github.com/bqlpfy/flux-panel /opt/flux-panel
cd /opt/flux-panel/go-gost
# 安装 Go 1.24+ 后：
CGO_ENABLED=0 go build -ldflags="-s -w" -o /opt/flux-agent/flux_agent ./cmd/gost
```

然后在面板中创建节点获取 secret，写入 `/opt/flux-agent/config.json`：

```json
{
  "addr": "面板IP:6365",
  "secret": "面板中创建的节点密钥",
  "http": 1,
  "tls": 0,
  "socks": 1
}
```

创建 systemd 服务 `flux-agent`（WorkingDirectory=/opt/flux-agent，ExecStart=无参启动
`/opt/flux-agent/flux_agent`），节点即自动连接面板并接收配置下发。

#### 手动部署（可选）

```bash
# 1. 构建后端（需 JDK 21 + Maven）
cd springboot-backend && mvn clean package -DskipTests

# 2. 构建前端（需 Node 20）
cd vite-frontend && npm install --legacy-peer-deps && npm run build

# 3. 初始化 PostgreSQL（首次）
#    CREATE USER fluxuser WITH PASSWORD '<密码>';
#    CREATE DATABASE flux_panel OWNER fluxuser;
#    后端启动时自动执行 schema.sql/data.sql（spring.sql.init.mode=always）

# 4. 部署后端
#    java -jar springboot-backend/target/admin.jar
#    环境变量: DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD JWT_SECRET LOG_DIR

# 5. 前端: nginx 托管 vite-frontend/dist，反代 127.0.0.1:6365
```

#### 默认管理员账号

- **账号**: admin_user
- **密码**: admin_user

> ⚠️ 首次登录后请立即修改默认密码！

## 免责声明

本项目仅供个人学习与研究使用，基于开源项目进行二次开发。  

使用本项目所带来的任何风险均由使用者自行承担，包括但不限于：  

- 配置不当或使用错误导致的服务异常或不可用；  
- 使用本项目引发的网络攻击、封禁、滥用等行为；  
- 服务器因使用本项目被入侵、渗透、滥用导致的数据泄露、资源消耗或损失；  
- 因违反当地法律法规所产生的任何法律责任。  

本项目为开源的流量转发工具，仅限合法、合规用途。  
使用者必须确保其使用行为符合所在国家或地区的法律法规。  

**作者不对因使用本项目导致的任何法律责任、经济损失或其他后果承担责任。**  
**禁止将本项目用于任何违法或未经授权的行为，包括但不限于网络攻击、数据窃取、非法访问等。**  

如不同意上述条款，请立即停止使用本项目。  

作者对因使用本项目所造成的任何直接或间接损失概不负责，亦不提供任何形式的担保、承诺或技术支持。  


请务必在合法、合规、安全的前提下使用本项目。  

---
## ⭐ 喝杯咖啡！（USDT）

| 网络       | 地址                                                                 |
|------------|----------------------------------------------------------------------|
| BNB(BEP20) | `0x755492c03728851bbf855daa28a1e089f9aca4d1`                          |
| TRC20      | `TYh2L3xxXpuJhAcBWnt3yiiADiCSJLgUm7`                                  |
| Aptos      | `0xf2f9fb14749457748506a8281628d556e8540d1eb586d202cd8b02b99d369ef8`  |
