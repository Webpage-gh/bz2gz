#!/bin/bash

# 捕获到 Ctrl+C 时删除未转换的 gz 文件
clean() {
    [ -e /proc/$! ] && kill %1
    rm "$OUTPUT_FILE"
    exit 1
}

# 打印剩余时间
print_time() {
    (($1 >= 3600)) && printf "%s 时 " $(($1/3600))
    (($1 >= 60)) && printf "%s 分 " $(($1%3600/60))
    (($1 >= 0)) && printf "%s 秒" $(($1%60)) || printf 0
}

# 计算剩余时间
remaining_time() {
    # 获取当前时间戳（秒）
    now=$(date +%s)  
    # 计算从文件创建到当前的秒数
    elapsed_seconds=$((now - create_time))
    if [ "$elapsed_seconds" -eq 0 ]; then return; fi
    # 计算平均速度和所需时间
    average_speed=$(echo "scale=2; $target_size / $elapsed_seconds" | bc -l)
    time_required=$(echo "scale=2; $SIZE / $average_speed" | bc -l)
    # 计算剩余时间（秒），计算几乎不消耗时间
    rtime="$((create_time + "$(printf %0.0f "$time_required")" - now))"
    print_time "$rtime"
}

# 检查参数
if [ "$#" != 1 ]; then
    cat <<-EOF
		使用多线程和管道快速转换xz文件到gz文件。
		用法：$0 文件名称.xz
	EOF
    exit 1
fi

# 检查命令是否存在
if ! command -v xz > /dev/null; then
    echo "命令 xz 不存在，请先安装它。"
    exit 1
fi

INPUT_FILE="$1" # 获取源文件路径
OUTPUT_FILE="${INPUT_FILE%.xz}.gz" # 设置目标文件名称
SIZE="$(bc <<< "$(xz -l "$INPUT_FILE" | awk 'NR==2{print $5}') * 524288")" # 估算gz文件大小，x/1024^2(Byte)*0.5(压缩率)
# 检查源文件是否存在
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: 找不到文件 $INPUT_FILE。"
    exit 1
fi

# 检查目标文件是否存在
if [ -f "$OUTPUT_FILE" ]; then
  printf "是否覆盖 %s？[y/n]" "$OUTPUT_FILE"
    while true; do
      read -r -n1 answer
      case $answer in
        Y|y)
          rm "$OUTPUT_FILE"
          echo
          break;;
        N|n)
          echo
          exit;;
        *)
          printf "\b \b";;
      esac
    done
fi

# 转换 xz 到 gz
trap clean SIGINT
xz -d -c "$INPUT_FILE" | gzip -1 > "$OUTPUT_FILE" &

# 获取开始时刻（秒）
create_time="$(date +%s)"
# 显示进度
while [ -e /proc/$! ]; do
    # 获取写入磁盘的gz文件大小
    target_size="$(stat -c %s "$OUTPUT_FILE")"
    # 计算进度
    schedule="$(bc <<< "scale=3; $target_size * 100 / $SIZE")"
    # 防止估算进度超过100%
    (( "$(bc <<< "$schedule > 99.99")" )) && break
    printf "\r进度：%0.2f %% 剩余时间：$(remaining_time)\033[K" "$schedule"
    sleep 1
done

# 确保已经完成压缩
wait
# 获取结束时刻
done_time="$(date +%s)"
# 打印耗时
printf "\r\033[K耗时：%s\n" "$(print_time "$((done_time - create_time))")"
# 测试压缩文件
echo "测试压缩是否完整…按Ctrl+C可取消"
trap exit SIGINT
if gzip -t "$OUTPUT_FILE"; then
    echo "转换完成：$INPUT_FILE 到 $OUTPUT_FILE"
else
    echo "转换失败"
    clean
fi
