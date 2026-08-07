#!/bin/bash
# ============================================================
# flux-panel (哆啦A梦面板) 2.0.7-beta 一键 systemd 安装脚本
# 适用：Debian 12 / Ubuntu 22.04+ (x86_64 / arm64)
# 组件：Spring Boot 后端(java -jar + SQLite) + nginx 前端
# 无需 MariaDB/MySQL —— beta 版后端内置 SQLite，启动自动建表
# 二开说明：仅修改 vite-frontend/nginx.conf 的反代地址
#          (backend:6365 -> 127.0.0.1:6365)，其余为原版代码
# ============================================================
set -euo pipefail

# ---------- 配置 ----------
REPO_BRANCH="${REPO_BRANCH:-beta}"                     # 2.0.7-beta 开发版分支
REPO_URL="${REPO_URL:-https://github.com/bqlpfy/flux-panel.git}"
INSTALL_DIR="${INSTALL_DIR:-/opt/flux-panel}"          # 源码目录
DEPLOY_DIR="${INSTALL_DIR}/deploy"                     # 部署目录(jar/日志/SQLite)
WWW_DIR="${WWW_DIR:-/var/www/flux}"                    # 前端静态文件
FRONTEND_PORT="${FRONTEND_PORT:-6366}"
BACKEND_PORT="${BACKEND_PORT:-6365}"
DB_PATH="${DB_PATH:-${DEPLOY_DIR}/data/gost.db}"       # SQLite 数据库文件
JWT_SECRET="${JWT_SECRET:-$(openssl rand -hex 16)}"
JAVA_HOME_DIR="${JAVA_HOME_DIR:-/opt/jdk-21}"
NODE_HOME_DIR="${NODE_HOME_DIR:-/opt/node20}"
NODE_VERSION="${NODE_VERSION:-v20.19.0}"
JDK_VERSION="${JDK_VERSION:-21.0.6}"
WITH_NGINX="${WITH_NGINX:-1}"                     # 1=自动安装并配置 nginx（默认）；0=跳过，由用户自行配置 Web 服务器

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
ok()  { echo -e "${GREEN}[OK] $1${NC}"; }
err() { echo -e "${RED}[FAIL] $1${NC}"; exit 1; }

# ---------- 1. 系统依赖 ----------
echo "==> [1/5] 安装系统依赖 (maven / nginx ...)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
if [ "$WITH_NGINX" = "1" ]; then
  apt-get install -y -qq git curl wget unzip maven nginx openssl
else
  apt-get install -y -qq git curl wget unzip maven openssl
fi

# ---------- 2. JDK 21 (Debian 12 源无 JDK21，用 Adoptium) ----------
echo "==> [2/5] 安装 JDK $JDK_VERSION"
if [ ! -x "$JAVA_HOME_DIR/bin/java" ]; then
  ARCH=$(uname -m | sed "s/x86_64/x64/; s/aarch64/aarch64/")
  curl -sL -o /tmp/jdk.tar.gz "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-${JDK_VERSION}%2B7/OpenJDK21U-jdk_${ARCH}_linux_hotspot_${JDK_VERSION}_7.tar.gz"
  mkdir -p "$JAVA_HOME_DIR" && tar xzf /tmp/jdk.tar.gz -C /tmp
  mv /tmp/jdk-${JDK_VERSION}+7/* "$JAVA_HOME_DIR" && rm -f /tmp/jdk.tar.gz
  rm -rf /tmp/jdk-${JDK_VERSION}+7
fi
ok "JDK: $($JAVA_HOME_DIR/bin/java -version 2>&1 | head -1)"

# ---------- 3. Node 20 ----------
echo "==> [3/5] 安装 Node $NODE_VERSION"
if [ ! -x "$NODE_HOME_DIR/bin/node" ]; then
  ARCH=$(uname -m | sed "s/x86_64/x64/; s/aarch64/arm64/")
  curl -sL -o /tmp/node.tar.xz "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-${ARCH}.tar.xz"
  mkdir -p "$NODE_HOME_DIR" && tar xJf /tmp/node.tar.xz -C /tmp
  mv /tmp/node-${NODE_VERSION}-linux-${ARCH}/* "$NODE_HOME_DIR" && rm -f /tmp/node.tar.xz
  rm -rf /tmp/node-${NODE_VERSION}-linux-${ARCH}
fi
ok "Node: $($NODE_HOME_DIR/bin/node -v)"

# ---------- 4. 拉源码 + 构建 ----------
echo "==> [4/5] 构建后端 + 前端"
if [ ! -d "$INSTALL_DIR/.git" ]; then
  git clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR"
fi
export JAVA_HOME="$JAVA_HOME_DIR"
export PATH="$JAVA_HOME/bin:$NODE_HOME_DIR/bin:$PATH"
(cd "$INSTALL_DIR/springboot-backend" && mvn clean package -DskipTests -q) || err "后端构建失败"
(cd "$INSTALL_DIR/vite-frontend" && npm install --no-audit --no-fund --legacy-peer-deps && npm run build) || err "前端构建失败"
ok "后端 jar: $(ls -lh "$INSTALL_DIR/springboot-backend/target/"*.jar | awk '{print $5}')"

# ---------- 5. 部署 + systemd ----------
echo "==> [5/5] 部署文件与 systemd 服务"
mkdir -p "$(dirname "$DB_PATH")" "$DEPLOY_DIR/logs" "$WWW_DIR"
systemctl stop flux-backend 2>/dev/null || true
cp "$INSTALL_DIR/springboot-backend/target/"*.jar "$DEPLOY_DIR/admin.jar"
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
  echo "[提示] 已跳过 nginx 安装与配置 (WITH_NGINX=0)"
  echo "[提示] 前端静态文件目录: $WWW_DIR"
  cat > "$DEPLOY_DIR/nginx-flux.conf.example" <<NGINX
server {
    listen $FRONTEND_PORT;
    server_name _;
    root $WWW_DIR;
    index index.html;
    location / { try_files $uri $uri/ /index.html; }
    location ^~ /api/v1/ {
        proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass http://127.0.0.1:$BACKEND_PORT/api/v1/;
    }
    location /flow/upload { proxy_pass http://127.0.0.1:$BACKEND_PORT/flow/upload; proxy_set_header Host $host; }
    location /flow/config { proxy_pass http://127.0.0.1:$BACKEND_PORT/flow/config; proxy_set_header Host $host; }
    location /system-info {
        proxy_pass http://127.0.0.1:$BACKEND_PORT/system-info;
        proxy_http_version 1.1; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade";
        proxy_set_header Host $host; proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX
  echo "[提示] 配置模板: $DEPLOY_DIR/nginx-flux.conf.example（改好反代目标后放入你的 Web 服务器配置目录）"
fi

# 后端 systemd 服务
cat > /etc/systemd/system/flux-backend.service <<SVC
[Unit]
Description=Flux Panel Backend (Spring Boot + SQLite)
After=network.target

[Service]
Type=simple
WorkingDirectory=$DEPLOY_DIR
Environment=DB_PATH=$DB_PATH
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

echo ""
echo "=============================================="
echo " flux-panel 2.0.7-beta 面板安装完成 (systemd)"
echo "----------------------------------------------"
echo " 访问: http://服务器IP:$FRONTEND_PORT"
echo " 账号: admin_user / admin_user (登录后请修改)"
echo " 源码: $INSTALL_DIR  部署: $DEPLOY_DIR"
if [ "$WITH_NGINX" = "1" ]; then
  echo " 服务: flux-backend / nginx"
else
  echo " 服务: flux-backend（nginx 未安装，Web 服务器由你自行配置）"
fi
echo " 数据库: SQLite ($DB_PATH) 启动自动建表"
echo " 文档: https://tes.cc/guide.html"
echo "=============================================="
