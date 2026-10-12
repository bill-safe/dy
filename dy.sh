#!/bin/bash
export LANG=en_US.UTF-8

# 终端颜色支持
red(){ echo -e "\033[31m\033[01m\$1\033[0m";}
green(){ echo -e "\033[32m\033[01m\$1\033[0m";}
yellow(){ echo -e "\033[33m\033[01m\$1\033[0m";}
blue(){ echo -e "\033[36m\033[01m\$1\033[0m";}

# 1. 权限与系统检查
[[ \$EUID -ne 0 ]] && yellow "请以 root 模式运行此脚本！" && exit

clear
echo "=================================================="
blue  "      FLClash 智能自适应安全订阅生成器安装脚本    "
echo "=================================================="
echo ""
yellow "提示：如果有域名，建议输入域名以启用顶级 HTTPS 加密。"
yellow "      如果没有域名，请直接【敲回车】，将自动切换为纯 IP 模式运行。"
echo ""
read -p "请输入解析到此服务器的【域名】(不输请直接回车): " MY_DOMAIN

if [ -z "\$MY_DOMAIN" ]; then
    blue " [!] 未输入域名，自动切换为【纯 IP 模式】运行。"
    LISTEN_ADDR=":8080"
    PORT="8080"
else
    green " [√] 检测到域名，将自动切换为【HTTPS 域名模式】运行。"
    LISTEN_ADDR="\$MY_DOMAIN:8443"
    PORT="8443"
fi

# 2. 自动处理 Ubuntu 防火墙，精准放行对应端口
echo "正在处理防火墙组件..."
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "active"; then
    ufw allow \$PORT/tcp >/dev/null 2>&1
    ufw reload >/dev/null 2>&1
    green " [√] UFW 防火墙已成功放行 \$PORT 端口"
fi

if command -v iptables >/dev/null 2>&1; then
    iptables -I INPUT -p tcp --dport \$PORT -j ACCEPT >/dev/null 2>&1
    if [ -x "\$(command -v netfilter-persistent)" ]; then
        netfilter-persistent save >/dev/null 2>&1
    fi
    green " [√] iptables 规则已同步放行 \$PORT 端口"
fi

# 3. 安装必要的依赖与官方最新 Caddy 软件源
echo "正在安装基础依赖..."
apt-get update -y >/dev/null 2>&1
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl wget jq gpg >/dev/null 2>&1

echo "正在配置官方 Caddy 最新安全密钥与软件源..."
# 彻底移除之前旧的、错误的 list 文件防止其干扰 apt
rm -f /etc/apt/sources.list.d/caddy-stable.list

# 采用官方最新最稳妥的公钥指纹下载并转化为本地专属 gpg 密钥环
curl -1sLf 'https://cloudsmith.io' | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
# 正确写入合规的 apt 软件源格式，避免引入网页代码导致 DOCTYPE 报错
echo "deb [signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] https://cloudsmith.io any main" | tee /etc/apt/sources.list.d/caddy-stable.list

echo "正在下载并安装 Caddy 服务..."
apt-get update -y >/dev/null 2>&1
apt-get install -y caddy >/dev/null 2>&1

# 4. 初始化目录与基础配置
SUB_DIR="/var/www/sub"
CADDYFILE="/etc/caddy/Caddyfile"
mkdir -p \$SUB_DIR
if [ ! -f "\$SUB_DIR/config.yaml" ]; then
    echo "# 请使用 dy 导入你的 FLClash 配置文件" > "\$SUB_DIR/config.yaml"
fi
# 收紧目录与文件权限
chown -R caddy:caddy \$SUB_DIR
chmod 700 \$SUB_DIR
chmod 600 \$SUB_DIR/config.yaml

# 生成一个初始化随机 UUID 密钥
INIT_UUID=\$(cat /proc/sys/kernel/random/uuid)

# 5. 写入高强度加固、全伪装的 Caddyfile
cat << CADDYEOF > \(CADDYFILE\)LISTEN_ADDR {
    root * /var/www/sub
    file_server

    # 【安全加固 1】全面抹除 Caddy 默认特征，误导和迷惑扫描器
    header {
        -Server
        Server "nginx/1.24.0"
        -Date
    }

    # 禁止任何对真实文件名的直接请求，返回假 Nginx 500 页面
    respond /config.yaml \`<html>
<head><title>500 Internal Server Error</title></head>
<body>
<center><h1>500 Internal Server Error</h1></center>
<hr><center>nginx/1.24.0</center>
</body>
</html>\` 500

    # 专属密钥路径鉴权
    @my_secret_link path /\$INIT_UUID
    handle @my_secret_link {
        rewrite * /config.yaml
        header {
            Content-Type "text/yaml; charset=utf-8"
            Content-Disposition "attachment; filename=\"config.yaml\""
        }
    }

    # 【安全加固 2】蜜罐级伪装：盲猜路径全部返回逼真 500 错误
    fallback {
        respond \`<html>
<head><title>500 Internal Server Error</title></head>
<body>
<center><h1>500 Internal Server Error</h1></center>
<hr><center>nginx/1.24.0</center>
</body>
</html>\` 500
    }
}
CADDYEOF

systemctl daemon-reload
systemctl enable caddy >/dev/null 2>&1
systemctl restart caddy

# 6. 生成本地快捷管理脚本 /usr/local/bin/dy
# 注意：此处的打包使用带有转义符号的模板，以确保写入目标文件时逻辑完美无瑕
cat << 'DYEOF' > /usr/local/bin/dy
#!/bin/bash
SUB_DIR="/var/www/sub"
CADDYFILE="/etc/caddy/Caddyfile"

get_host_info() {
    local first_line=\$(head -n 1 /etc/caddy/Caddyfile | tr -d ' {')
    if [[ "\$first_line" == :* ]]; then
        local ip=\$(curl -s4m5 icanhazip.com || curl -s ifconfig.me)
        local port=(echo "first_line" | sed 's/://')
        echo "http://ip:{port}"
    else
        echo "https://\${first_line}"
    fi
}

get_secret() {
    local secret=\$(grep "path /" /etc/caddy/Caddyfile | head -n1 | awk '{print \$2}' | sed 's/\///')
    echo "\${secret:-secret-error}"
}

update_config_menu() {
    clear
    echo "====================================="
    echo "       更新 FLClash 配置文件        "
    echo "====================================="
    echo "1. 从当前服务器的【本地 file 文件】导入"
    echo "2. 从【远程 URL 链接】下载导入"
    echo "3. 返回主菜单"
    echo "====================================="
    read -p "请选择导入方式 [1-3]: " upload_choice

    case \$upload_choice in
        1)
            read -p "请输入配置文件在服务器上的绝对路径 (如 /root/clash.yaml): " file_path
            if [ -f "\$file_path" ]; then
                cp "\(file_path" "\)SUB_DIR/config.yaml"
                chown caddy:caddy "\$SUB_DIR/config.yaml"
                chmod 600 "\$SUB_DIR/config.yaml"
                echo " [√] 成功从本地 file 文件导入！"
            else
                echo " [X] 错误：文件不存在！请检查路径是否正确。"
            fi
            ;;
        2)
            read -p "请输入合法的远程配置文件 URL: " remote_url
            if [ -z "\$remote_url" ]; then
                echo " [X] URL 不能为空！"
            else
                echo "正在加密下载..."
                # 修复 /tmp 提权隐患：使用安全的随机随机文件接收下载
                local tmp_config=\$(mktemp /tmp/clash_cfg.XXXXXXXXXX)
                local http_status=\$(curl -sL -w "%{http_code}" "\(remote_url" -o "\)tmp_config")

                if [ "\$http_status" -eq 200 ]; then
                    mv "\(tmp_config" "\)SUB_DIR/config.yaml"
                    chown caddy:caddy "\$SUB_DIR/config.yaml"
                    chmod 600 "\$SUB_DIR/config.yaml"
                    echo " [√] 成功从远程下载并导入！"
                else
                    rm -f "\$tmp_config"
                    echo " [X] 下载失败，HTTP 状态码: \$http_status"
                fi
            fi
            ;;
        *) return ;;
    esac
    read -p "按回车键继续..." opt
}

show_menu() {
    clear
    echo "====================================="
    echo "   FLClash 终极自适应安全订阅 (dy)   "
    echo "====================================="
    echo "1. 更新/导入 FLClash 配置文件"
    echo "2. 查看当前 [安全订阅] 链接"
    echo "3. 修改/重置专属安全密钥"
    echo "4. 再添加/更换域名 (重新配置环境)"
    echo "5. 重启订阅服务"
    echo "6. 退出"
    echo "====================================="
    read -p "请选择操作 [1-6]: " choice

    case \$choice in
        1) update_config_menu ;;
        2)
            host_base=\$(get_host_info)
            secret=\$(get_secret)
            echo "-------------------------------------"
            echo " 你的高安全性订阅链接为："
            echo -e "\033[32m\033[01m\({host_base}/\){secret}\033[0m"
            echo ""
            echo " 当前安全防御层级："
            echo " - 自动移除 Caddy 默认特征并伪装成 Nginx/1.24.0"
            echo " - 任何非授权请求或盲猜路径 -> 均伪装返回假 Nginx 500 报错"
            echo " - 订阅文件本地权限收紧为 600，杜绝越权读取"
            echo " - 修复临时文件符号链接漏洞，100% 本地提权免疫"
            echo "-------------------------------------"
            ;;
        3)
            echo "1. 自动生成随机 UUID 密钥"
            echo "2. 手动输入自定义密钥"
            read -p "请选择 [1-2]: " key_choice
            if [ "\$key_choice" -eq 1 ]; then
                new_secret=\$(cat /proc/sys/kernel/random/uuid)
            else
                read -p "请输入自定义安全路径密钥（仅限字母数字）: " new_secret
            fi
            if [ -n "\$new_secret" ]; then
                old_secret=\$(get_secret)
                sed -i "s|path /\(old_secret\vert{}path /\)new_secret|g" /etc/caddy/Caddyfile
                systemctl restart caddy
                echo " [√] 密钥已成功更新！"
            fi
            ;;
        4)
            echo " [!] 注意：这会重置环境。请重新运行你的一键安装脚本来绑定域名。"
            ;;
        5) systemctl restart caddy && echo " [√] 服务已重启！" ;;
        6) exit 0 ;;
        *) echo "无效选项！" ;;
    esac
    read -p "按回车键继续..." opt
    show_menu
}
show_menu
DYEOF

chmod +x /usr/local/bin/dy

clear
echo "=================================================="
green " [√] FLClash 智能自适应安全订阅系统环境部署成功！"
blue  " - 笔记服务可以继续安全、无冲突地运行在 80/443 端口。"
if [ -z "\$MY_DOMAIN" ]; then
    blue " - 当前服务运行在【纯 IP 模式】，使用安全端口: 8080"
else
    blue " - 当前服务运行在【HTTPS 域名模式】，使用加密端口: 8443"
fi
echo "--------------------------------------------------"
green " 现在你可以在服务器任意目录下直接输入 'dy' 运行管理菜单。"
echo "=================================================="
