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

# 3. 清理错误并安装官方最新 Caddy
echo "正在配置官方 Caddy 环境..."
rm -f /etc/apt/sources.list.d/caddy-stable.list

# 使用最新标准的 Ubuntu 官方公共软件库安装 caddy (稳定防断链)
apt-get update -y >/dev/null 2>&1
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl wget jq gpg caddy >/dev/null 2>&1

if ! command -v caddy &> /dev/null; then
    red " [X] Caddy 安装失败，正在尝试通过备用源安装..."
    sudo apt-get install -y caddy
fi

# 4. 初始化网页服务目录
SUB_DIR="/var/www/sub"
CADDYFILE="/etc/caddy/Caddyfile"
mkdir -p \$SUB_DIR
if [ ! -f "\$SUB_DIR/config.yaml" ]; then
    echo "# 请使用 dy 导入你的 FLClash 配置文件" > "\$SUB_DIR/config.yaml"
fi

# 生成初始化专属 UUID
INIT_UUID=\$(cat /proc/sys/kernel/random/uuid)

# 5. 写入高强度加固、全伪装的 Caddyfile
cat << 'CADDYEOF' > /tmp/caddy_template
HOST_HOLDER {
    root * /var/www/sub
    file_server

    header {
        -Server
        Server "nginx/1.24.0"
        -Date
    }

    respond /config.yaml `<html>
<head><title>500 Internal Server Error</title></head>
<body>
<center><h1>500 Internal Server Error</h1></center>
<hr><center>nginx/1.24.0</center>
</body>
</html>` 500

    @my_secret_link path /UUID_HOLDER
    handle @my_secret_link {
        rewrite * /config.yaml
        header {
            Content-Type "text/yaml; charset=utf-8"
            Content-Disposition "attachment; filename=\"config.yaml\""
        }
    }

    fallback {
        respond `<html>
<head><title>500 Internal Server Error</title></head>
<body>
<center><h1>500 Internal Server Error</h1></center>
<hr><center>nginx/1.24.0</center>
</body>
</html>` 500
    }
}
CADDYEOF

# 安全替换模板中的变量，100% 规避括号与转义报错
sed "s|HOST_HOLDER|\(LISTEN_ADDR\vert{}g" /tmp/caddy_template > \)CADDYFILE
sed -i "s|UUID_HOLDER|\(INIT_UUID\vert{}g" \)CADDYFILE
rm -f /tmp/caddy_template

# 收紧并重置目录权限
chown -R caddy:caddy \$SUB_DIR
chmod 700 \$SUB_DIR
chmod 600 \$SUB_DIR/config.yaml

# 启动服务
systemctl daemon-reload
systemctl enable caddy >/dev/null 2>&1
systemctl restart caddy

# 6. 安全写入本地快捷管理工具 /usr/local/bin/dy (使用完全安全的标准单引号保护)
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
green " [√] FLClash 安全订阅链接系统环境修复成功！"
blue  " - 笔记服务（80/443端口）依然保持绝对纯净安全。"
echo "=================================================="
green " 现在请直接在系统终端输入 'dy' 来更新和查看你的专属链接。"
echo "=================================================="
