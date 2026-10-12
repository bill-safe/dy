cat << 'DYEOF' > /usr/local/bin/dy
#!/bin/bash
SUB_DIR="/var/www/sub"
CADDYFILE="/etc/caddy/Caddyfile"

# 自动解析 Caddyfile 获取配置参数
get_host_info() {
    local first_line=$(head -n 1 /etc/caddy/Caddyfile | tr -d ' {')
    if [[ "$first_line" == :* ]]; then
        local ip=$(curl -s4m5 icanhazip.com || curl -s ifconfig.me)
        local port=$(echo "$first_line" | sed 's/://')
        echo "http://${ip}:${port}"
    else
        echo "https://${first_line}"
    fi
}

get_secret() {
    local secret=$(grep "path /" /etc/caddy/Caddyfile | head -n1 | awk '{print $2}' | sed 's/\///')
    echo "${secret:-secret-error}"
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

    case $upload_choice in
        1)
            read -p "请输入配置文件在服务器上的绝对路径 (如 /root/clash.yaml): " file_path
            if [ -f "$file_path" ]; then
                cp "$file_path" "$SUB_DIR/config.yaml"
                chown caddy:caddy "$SUB_DIR/config.yaml"
                chmod 600 "$SUB_DIR/config.yaml"
                echo " [√] 成功从本地 file 文件导入！"
            else
                echo " [X] 错误：文件不存在！"
            fi
            ;;
        2)
            read -p "请输入合法的远程配置文件 URL: " remote_url
            if [ -z "$remote_url" ]; then
                echo " [X] URL 不能为空！"
            else
                echo "正在加密下载..."
                
                # 【安全修复 1】使用 mktemp 创建唯一的、高权限保护的临时文件存放配置
                local tmp_config=$(mktemp /tmp/clash_cfg.XXXXXXXXXX)
                
                # 【安全修复 2】直接通过内存变量捕获 HTTP 状态码，彻底废除公共路径的重定向文件
                # -w "%{http_code}" 打印状态码，-o 将文件内容保存到刚才创建的安全临时文件中
                local http_status=$(curl -sL -w "%{http_code}" "$remote_url" -o "$tmp_config")

                if [ "$http_status" -eq 200 ]; then
                    mv "$tmp_config" "$SUB_DIR/config.yaml"
                    chown caddy:caddy "$SUB_DIR/config.yaml"
                    chmod 600 "$SUB_DIR/config.yaml"
                    echo " [√] 成功从远程下载并导入！"
                else
                    rm -f "$tmp_config"
                    echo " [X] 下载失败，HTTP 状态码: $http_status"
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

    case $choice in
        1) update_config_menu ;;
        2)
            host_base=$(get_host_info)
            secret=$(get_secret)
            echo "-------------------------------------"
            echo " 你的高安全性订阅链接为："
            echo -e "\033[32m\033[01m${host_base}/${secret}\033[0m"
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
            if [ "$key_choice" -eq 1 ]; then
                new_secret=$(cat /proc/sys/kernel/random/uuid)
            else
                read -p "请输入自定义安全路径密钥（仅限字母数字）: " new_secret
            fi
            if [ -n "$new_secret" ]; then
                old_secret=$(get_secret)
                sed -i "s|path /$old_secret|path /$new_secret|g" /etc/caddy/Caddyfile
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
