#!/bin/bash
# ============================================================
# flux-panel (哆啦A梦面板) 2.0.7-beta 一键 systemd 安装脚本（v2）
# 适用：Debian 12 / Ubuntu 22.04+ (x86_64 / arm64)
#
# 组件：
#   面板    ：Spring Boot 后端 (java -jar + PostgreSQL) + 前端静态文件
#   节点(可选)：go-gost v3.2.6 定制内核（flux_agent，WITH_NODE=1 时安装）
#
# 数据库：PostgreSQL（无 MariaDB/MySQL）
# Web 服务器：默认不安装（WITH_NGINX=0），由用户自行配置；
#             WITH_NGINX=1 时代装并配置 nginx（反代 127.0.0.1:6365）
#
# 二开说明（本项目相对上游的改动）：
#   1. 后端数据库 SQLite → PostgreSQL（pom/application.yml/schema.sql 全面改造）
#   2. 转发内核升级为 go-gost v3.2.6 定制版（仓库 go-gost/ 目录，
#      含 panel 扩展包：WebSocket 实时监控 + 流量上报 + 服务热重载）
#   3. 前端 nginx.conf 反代地址 backend:6365 → 127.0.0.1:6365
#   4. 界面去除 Powered by flux-panel / 版本标签及跳转链接
# ============================================================
set -euo pipefail

# ---------- 配置 ----------
REPO_BRANCH="${REPO_BRANCH:-beta}"                     # 2.0.7-beta 开发版分支
REPO_URL="${REPO_URL:-https://github.com/bqlpfy/flux-panel.git}"
INSTALL_DIR="${INSTALL_DIR:-/opt/flux-panel}"          # 源码目录
DEPLOY_DIR="${INSTALL_DIR}/deploy"                     # 部署目录(jar/日志)
WWW_DIR="${WWW_DIR:-/var/www/flux}"                    # 前端静态文件
FRONTEND_PORT="${FRONTEND_PORT:-6366}"
BACKEND_PORT="${BACKEND_PORT:-6365}"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-flux_panel}"
DB_USER="${DB_USER:-fluxuser}"
DB_PASSWORD="${DB_PASSWORD:-$(openssl rand -hex 12)}"
JWT_SECRET="${JWT_SECRET:-$(openssl rand -hex 16)}"
JAVA_HOME_DIR="${JAVA_HOME_DIR:-/opt/jdk-21}"
NODE_HOME_DIR="${NODE_HOME_DIR:-/opt/node20}"
NODE_VERSION="${NODE_VERSION:-v20.19.0}"
JDK_VERSION="${JDK_VERSION:-21.0.6}"
WITH_NGINX="${WITH_NGINX:-0}"                          # 默认不装 Web 服务器；设 1 代装 nginx
WITH_NODE="${WITH_NODE:-1}"                            # 是否安装节点内核(flux_agent)
NODE_DIR="${NODE_DIR:-/opt/flux-agent}"                # 节点部署目录
NODE_PANEL_ADDR="${NODE_PANEL_ADDR:-}"                 # 面板地址 IP:端口（缺省用本机 IP）
NODE_SECRET="${NODE_SECRET:-}"                         # 节点密钥（面板创建节点后填入）
GO_VERSION="${GO_VERSION:-1.24.5}"
GO_HOME_DIR="${GO_HOME_DIR:-/opt/go}"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
ok()  { echo -e "${GREEN}[OK] $1${NC}"; }
err() { echo -e "${RED}[FAIL] $1${NC}"; exit 1; }

# ---------- 1. 系统依赖 ----------
echo "==> [1/6] 安装系统依赖 (maven / postgresql ...)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
if [ "$WITH_NGINX" = "1" ]; then
  apt-get install -y -qq git curl wget unzip maven nginx openssl postgresql
else
  apt-get install -y -qq git curl wget unzip maven openssl postgresql
fi

# ---------- 2. JDK 21 (Debian 12 源无 JDK21，用 Adoptium) ----------
echo "==> [2/6] 安装 JDK $JDK_VERSION"
if [ ! -x "$JAVA_HOME_DIR/bin/java" ]; then
  ARCH=$(uname -m | sed "s/x86_64/x64/; s/aarch64/aarch64/")
  curl -sL -o /tmp/jdk.tar.gz "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-${JDK_VERSION}%2B7/OpenJDK21U-jdk_${ARCH}_linux_hotspot_${JDK_VERSION}_7.tar.gz"
  mkdir -p "$JAVA_HOME_DIR" && tar xzf /tmp/jdk.tar.gz -C /tmp
  mv /tmp/jdk-${JDK_VERSION}+7/* "$JAVA_HOME_DIR" && rm -f /tmp/jdk.tar.gz
  rm -rf /tmp/jdk-${JDK_VERSION}+7
fi
ok "JDK: $($JAVA_HOME_DIR/bin/java -version 2>&1 | head -1)"

# ---------- 3. Node 20 ----------
echo "==> [3/6] 安装 Node $NODE_VERSION"
if [ ! -x "$NODE_HOME_DIR/bin/node" ]; then
  ARCH=$(uname -m | sed "s/x86_64/x64/; s/aarch64/arm64/")
  curl -sL -o /tmp/node.tar.xz "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-${ARCH}.tar.xz"
  mkdir -p "$NODE_HOME_DIR" && tar xJf /tmp/node.tar.xz -C /tmp
  mv /tmp/node-${NODE_VERSION}-linux-${ARCH}/* "$NODE_HOME_DIR" && rm -f /tmp/node.tar.xz
  rm -rf /tmp/node-${NODE_VERSION}-linux-${ARCH}
fi
ok "Node: $($NODE_HOME_DIR/bin/node -v)"

# ---------- 4. 拉源码 + 构建 ----------
echo "==> [4/6] 构建后端 + 前端"
if [ ! -d "$INSTALL_DIR/.git" ]; then
  git clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR"
fi
export JAVA_HOME="$JAVA_HOME_DIR"
export PATH="$JAVA_HOME/bin:$NODE_HOME_DIR/bin:$PATH"
(cd "$INSTALL_DIR/springboot-backend" && mvn clean package -DskipTests -q) || err "后端构建失败"
(cd "$INSTALL_DIR/vite-frontend" && npm install --no-audit --no-fund --legacy-peer-deps && npm run build) || err "前端构建失败"
ok "后端 jar: $(ls -lh "$INSTALL_DIR/springboot-backend/target/"*.jar | awk '{print $5}')"

# ---------- 5. 部署 + systemd ----------
echo "==> [5/6] 部署文件与 systemd 服务"
mkdir -p "$DEPLOY_DIR/logs" "$WWW_DIR"

# 初始化 PostgreSQL（启动 + 建库建用户，幂等）
systemctl enable --now postgresql >/dev/null 2>&1 || systemctl start postgresql
for i in $(seq 1 30); do pg_isready -q -h "$DB_HOST" -p "$DB_PORT" && break; sleep 1; done
echo "CREATE USER \"$DB_USER\" WITH PASSWORD '$DB_PASSWORD';" | su - postgres -c psql 2>/dev/null || true
echo "ALTER USER \"$DB_USER\" WITH PASSWORD '$DB_PASSWORD';" | su - postgres -c psql 2>/dev/null || true
echo "CREATE DATABASE \"$DB_NAME\" OWNER \"$DB_USER\";" | su - postgres -c psql 2>/dev/null || true
ok "PostgreSQL 就绪: $DB_HOST:$DB_PORT/$DB_NAME (用户 $DB_USER)"

systemctl stop flux-backend 2>/dev/null || true
cp "$INSTALL_DIR/springboot-backend/target/"*.jar "$DEPLOY_DIR/admin.jar.new"
mv "$DEPLOY_DIR/admin.jar.new" "$DEPLOY_DIR/admin.jar"   # 原子替换，避免读到半截 jar
rm -rf "$WWW_DIR"/*                                  # 清空旧静态文件（防旧 bundle 残留）
cp -r "$INSTALL_DIR/vite-frontend/dist/"* "$WWW_DIR/"

if [ "$WITH_NGINX" = "1" ]; then
  # nginx 站点配置（反代 127.0.0.1:BACKEND_PORT）
  cat > /etc/nginx/conf.d/flux.conf <<NGINX
server {
    listen $FRONTEND_PORT;
    server_name _;
    root $WWW_DIR;
    index index.html;
    location ~* \\.(js|css|png|jpg|jpeg|gif|ico|svg)\$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    location / { try_files \$uri \$uri/ /index.html; }
    location ^~ /api/v1/ {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://127.0.0.1:$BACKEND_PORT/api/v1/;
    }
    location /flow/upload {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://127.0.0.1:$BACKEND_PORT/flow/upload;
    }
    location /flow/config {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://127.0.0.1:$BACKEND_PORT/flow/config;
    }
    location /system-info {
        proxy_pass http://127.0.0.1:$BACKEND_PORT/system-info;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINX
  nginx -t >/dev/null && systemctl reload nginx
else
  # 用户自配模式：不安装/配置 nginx，仅生成配置模板供参考
  ok "已跳过 nginx 安装与配置 (WITH_NGINX=0)"
  cat > "$DEPLOY_DIR/nginx-flux.conf.example" <<NGINX
server {
    listen $FRONTEND_PORT;
    server_name _;
    root $WWW_DIR;
    index index.html;
    location / { try_files \$uri \$uri/ /index.html; }
    location ^~ /api/v1/ {
        proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://127.0.0.1:$BACKEND_PORT/api/v1/;
    }
    location /flow/upload { proxy_pass http://127.0.0.1:$BACKEND_PORT/flow/upload; proxy_set_header Host \$host; }
    location /flow/config { proxy_pass http://127.0.0.1:$BACKEND_PORT/flow/config; proxy_set_header Host \$host; }
    location /system-info {
        proxy_pass http://127.0.0.1:$BACKEND_PORT/system-info;
        proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINX
  echo "[提示] 配置模板: $DEPLOY_DIR/nginx-flux.conf.example（改好反代目标后放入你的 Web 服务器配置目录）"
fi

# 后端 systemd 服务
cat > /etc/systemd/system/flux-backend.service <<SVC
[Unit]
Description=Flux Panel Backend (Spring Boot + PostgreSQL)
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
WorkingDirectory=$DEPLOY_DIR
Environment=DB_HOST=$DB_HOST
Environment=DB_PORT=$DB_PORT
Environment=DB_NAME=$DB_NAME
Environment=DB_USER=$DB_USER
Environment=DB_PASSWORD=$DB_PASSWORD
Environment=JWT_SECRET=$JWT_SECRET
Environment=LOG_DIR=$DEPLOY_DIR/logs
Environment=JAVA_OPTS=-Xms256m -Xmx512m -Dfile.encoding=UTF-8 -Duser.timezone=Asia/Shanghai
ExecStart=$JAVA_HOME_DIR/bin/java \$JAVA_OPTS -jar $DEPLOY_DIR/admin.jar
Restart=on-failure
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SVC
systemctl daemon-reload
systemctl enable --now flux-backend

sleep 15
curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$BACKEND_PORT/flow/test" | grep -q 200 || err "后端启动失败，查看: journalctl -u flux-backend -f"

# ---------- 6. 节点内核（可选 WITH_NODE=1） ----------
if [ "$WITH_NODE" = "1" ]; then
  echo "==> [6/6] 安装节点内核 (go-gost v3.2.6 定制版 -> flux_agent)"
  if [ ! -x "$GO_HOME_DIR/bin/go" ]; then
    ARCH=$(uname -m | sed "s/x86_64/amd64/; s/aarch64/arm64/")
    curl -sL -o /tmp/go.tar.gz "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz"
    tar xzf /tmp/go.tar.gz -C /opt
    mv /opt/go "$GO_HOME_DIR"
    rm -f /tmp/go.tar.gz
  fi
  export PATH="$GO_HOME_DIR/bin:$PATH"
  export GOPROXY=https://proxy.golang.org,direct
  mkdir -p "$NODE_DIR"
  (cd "$INSTALL_DIR/go-gost" && CGO_ENABLED=0 go build -ldflags="-s -w" -o "$NODE_DIR/flux_agent" ./cmd/gost) || err "节点内核构建失败"
  ok "flux_agent: $($NODE_DIR/flux_agent -V 2>&1 | head -1)"

  # config.json（面板地址缺省用本机 IP）
  if [ -z "$NODE_PANEL_ADDR" ]; then
    LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    NODE_PANEL_ADDR="${LOCAL_IP:-127.0.0.1}:$BACKEND_PORT"
  fi
  cat > "$NODE_DIR/config.json" <<CFG
{
  "addr": "$NODE_PANEL_ADDR",
  "secret": "$NODE_SECRET",
  "http": 1,
  "tls": 0,
  "socks": 1
}
CFG

  cat > /etc/systemd/system/flux-agent.service <<SVC
[Unit]
Description=Flux Agent (go-gost v3.2.6 panel kernel)
After=network.target

[Service]
Type=simple
WorkingDirectory=$NODE_DIR
ExecStart=$NODE_DIR/flux_agent
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SVC
  systemctl daemon-reload
  systemctl enable --now flux-agent || true
  echo "[提示] 节点配置: $NODE_DIR/config.json（面板创建节点后填入 secret 并重启 flux-agent）"
fi

echo ""
echo "=============================================="
echo " flux-panel 2.0.7-beta 面板安装完成 (systemd)"
echo "----------------------------------------------"
echo " 访问: http://服务器IP:$FRONTEND_PORT"
echo " 账号: admin_user / admin_user (登录后请修改)"
echo " 源码: $INSTALL_DIR  部署: $DEPLOY_DIR"
if [ "$WITH_NGINX" = "1" ]; then
  echo " 服务: flux-backend / nginx (WITH_NGINX=1)"
else
  echo " 服务: flux-backend（未安装 Web 服务器，请自行配置，模板: $DEPLOY_DIR/nginx-flux.conf.example）"
fi
if [ "$WITH_NODE" = "1" ]; then
  echo " 节点: flux-agent ($NODE_DIR/flux_agent)"
fi
echo " 数据库: PostgreSQL $DB_HOST:$DB_PORT/$DB_NAME (用户 $DB_USER)"
echo " 文档: https://tes.cc/guide.html"
echo "=============================================="
