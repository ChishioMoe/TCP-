cat << 'EOF' > tune_tcp.sh
#!/bin/bash

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then 
  echo "请使用 sudo 运行此脚本"
  exit 1
fi

# --- 环境准备：安装 bc 计算器 ---
echo "正在检查并安装必要的依赖 (bc)..."
apt-get update && apt-get install -y bc

echo "--- TCP 缓冲区 BDP 自动优化脚本 ---"

# --- 获取用户输入 ---
read -p "请输入本地下载带宽 (Mbps): " local_bw
read -p "请输入服务器带宽 (Mbps): " server_bw
read -p "请输入到服务器的延迟 (ms): " latency

# --- 核心计算 ---
# 找出最小带宽
min_bw=$(( local_bw < server_bw ? local_bw : server_bw ))
# 计算公式: x = min_bw * 1000 * latency / 8
bdp_x=$(echo "($min_bw * 1000 * $latency) / 8" | bc)

# 设置合理的最小值，防止计算结果过小
if [ "$bdp_x" -lt 131072 ]; then
    bdp_x=131072
fi

echo "--------------------------------"
echo "计算得出的最大缓冲区 (x): $bdp_x 字节"
echo "--------------------------------"

# --- 备份与配置 ---
cp /etc/sysctl.conf /etc/sysctl.conf.bak_$(date +%Y%m%d_%H%M%S)

# 写入配置 (这里整合了你之前的内核优化，并动态插入了计算出的 x 值)
cat << EOL > /etc/sysctl.conf
# 基础内核优化
kernel.pid_max = 65535
kernel.panic = 1
kernel.sysrq = 1
kernel.core_pattern = core_%e
kernel.printk = 3 4 1 3
kernel.numa_balancing = 0
kernel.sched_autogroup_enabled = 0

# 内存优化
vm.swappiness = 10
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.panic_on_oom = 1
vm.overcommit_memory = 1
vm.min_free_kbytes = 54326

# 网络核心参数
net.core.default_qdisc = cake
net.core.netdev_max_backlog = 2000
net.core.rmem_max = $bdp_x
net.core.wmem_max = $bdp_x
net.core.rmem_default = 87380
net.core.wmem_default = 65536
net.core.somaxconn = 1024

# TCP 动态缓冲区设置 (基于 BDP 计算)
net.ipv4.tcp_rmem = 4096 87380 $bdp_x
net.ipv4.tcp_wmem = 4096 16384 $bdp_x

# TCP 加速与拥塞控制
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1

# 基础安全防护
net.ipv4.tcp_syncookies = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
EOL

# 生效配置
sysctl -p

echo "--------------------------------"
echo "优化完成！BBR 拥塞控制和 BDP 动态缓存已生效。"
echo "备份文件已存至: /etc/sysctl.conf.bak_$(date +%Y%m%d_%H%M%S)"
EOF

# 赋予权限并运行
chmod +x tune_tcp.sh
sudo ./tune_tcp.sh
