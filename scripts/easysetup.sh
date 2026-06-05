#!/usr/bin/env bash
set -eu

# ==========================================
# Linux 易用性配置一键安装脚本
# 用法: curl -fsSL <url> | bash
# ==========================================

SCRIPT_NAME="$(basename "$0")"
BACKUP_DIR="$HOME/.config/dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()  { printf "${BLUE}[INFO]${NC}  %s\n" "$*"; }
ok()    { printf "${GREEN}[OK]${NC}    %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
err()   { printf "${RED}[ERR]${NC}   %s\n" "$*" >&2; }

# 备份文件（如果不存在备份则创建）
backup_if_exists() {
    local file="$1"
    if [[ -f "$file" ]]; then
        mkdir -p "$BACKUP_DIR"
        cp "$file" "$BACKUP_DIR/"
        ok "已备份: $file -> $BACKUP_DIR/$(basename "$file")"
    fi
}

# 检查依赖
check_deps() {
    local missing=()
    for cmd in bash vim tmux; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "以下命令未检测到: ${missing[*]}"
        warn "这是配置脚本，只会写入配置文件，但对应工具可能不可用。"
    fi
}

# ==========================================
# 1. 安装 .bashrc 配置（追加）
# ==========================================
install_bashrc() {
    local bashrc="$HOME/.bashrc"
    local marker_start="# >>> my-dotfiles bashrc config"
    local marker_end="# <<< my-dotfiles bashrc config"

    backup_if_exists "$bashrc"

    # 如果已经存在标记，先移除旧配置（支持重复执行）
    if [[ -f "$bashrc" ]] && grep -qF "$marker_start" "$bashrc"; then
        info "检测到旧的 bashrc 配置，先移除..."
        local tmpfile
        tmpfile=$(mktemp)
        awk -v start="$marker_start" -v end="$marker_end" '
            $0 == start { skip=1; next }
            $0 == end   { skip=0; next }
            skip==0     { print }
        ' "$bashrc" > "$tmpfile"
        mv "$tmpfile" "$bashrc"
    fi

    info "正在追加 bashrc 配置..."
    {
        echo ""
        echo "$marker_start"
        cat <<'BASHRC_EOF'
alias dsh='docker exec -it'
alias dlg='docker logs -n 100 -f'
BASHRC_EOF
        echo "$marker_end"
    } >> "$bashrc"

    ok ".bashrc 配置已追加"
}

# ==========================================
# 2. 安装 .tmux.conf（覆盖/创建）
# ==========================================
install_tmuxconf() {
    local tmuxconf="$HOME/.tmux.conf"
    backup_if_exists "$tmuxconf"

    info "正在写入 tmux 配置..."
    cat > "$tmuxconf" <<'TMUX_EOF'
# --- 基础设置 ---
set -s set-clipboard on
set -as terminal-overrides ',xterm*:Ms=\E]52;%p1%s;%p2%s\007'

# 设置历史滚动行数
set -g history-limit 20000

# 开启鼠标支持 (点击切换窗口、调整面板大小、滚动)
set -g mouse on

# 解决 vim/nvim 颜色显示和延迟问题
set -g default-terminal "screen-256color"
set -s escape-time 0

# --- 热键绑定 ---

# 快捷重载配置文件
bind r source-file ~/.tmux.conf \; display "Config Reloaded!"

# 更直观的面板拆分键
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"

# 使用 Alt-方向键 直接切换面板 (无需先按前缀键)
bind -n M-Left select-pane -L
bind -n M-Right select-pane -R
bind -n M-Up select-pane -U
bind -n M-Down select-pane -D

# --- 界面美化 ---

# 状态栏样式
set -g status-bg black
set -g status-fg white
set -g status-left-length 20
set -g status-right "%Y-%m-%d %H:%M"

# 窗口标签居中
set -g status-justify centre

# 突出显示当前激活的窗口
setw -g window-status-current-style fg=black,bg=green
TMUX_EOF

    ok ".tmux.conf 已写入"
}

# ==========================================
# 3. 安装 .vimrc（覆盖/创建）
# ==========================================
install_vimrc() {
    local vimrc="$HOME/.vimrc"
    backup_if_exists "$vimrc"

    info "正在写入 vim 配置..."
    cat > "$vimrc" <<'VIM_EOF'
" ==========================================
" 1. 基础显示与外观设置
" ==========================================
syntax on                   " 开启语法高亮
"set number                  " 显示行号
set cursorline              " 高亮显示当前行
set showmode                " 在底部显示当前模式（Insert、Visual等）
set showcmd                 " 在状态栏显示正在输入的命令
set ruler                   " 在右下角显示光标位置（行列信息）
set laststatus=2            " 总是显示状态栏

" ==========================================
" 2. 缩进与排版设置（推荐使用空格代替 Tab）
" ==========================================
set autoindent              " 继承前一行的缩进方式
set smartindent             " 智能缩进（例如在 if/for 之后自动缩进）
set tabstop=4               " Tab 键显示的空格数
set softtabstop=4           " 编辑模式下按退格键时退回的缩进长度
set shiftwidth=4            " 每一级自动缩进的空格数
set expandtab               " 将输入的 Tab 键自动转换为空格

" ==========================================
" 3. 搜索设置
" ==========================================
set hlsearch                " 高亮显示搜索匹配结果
set incsearch               " 边输入边高亮（增量搜索）
set ignorecase              " 搜索时忽略大小写
set smartcase               " 如果搜索词包含大写字母，则不忽略大小写

" ==========================================
" 4. 鼠标与常规操作优化
" ==========================================
set mouse=a                 " 开启鼠标支持（支持鼠标滚轮滚动、点击定位、拖动选择等）
set backspace=indent,eol,start " 允许在 Insert 模式下使用退格键删除任意字符
set wildmenu                " 开启命令行补全菜单（按 Tab 键时在底部显示可选列表）
set showmatch               " 高亮显示匹配的括号（如 (), [], {}）

" ==========================================
" 5. 文件编码设置（防止中文乱码）
" ==========================================
set encoding=utf-8          " Vim 内部使用的编码
set fileencodings=utf-8,ucs-bom,gb18030,gbk,gb2312,cp936 " 打开文件时自动尝试的编码列表
set termencoding=utf-8      " 终端显示的编码

" ==========================================
" 6. 备份与临时文件设置
" ==========================================
set nobackup                " 不生成备份文件（以免污染目录）
set noswapfile              " 不生成 swap 交换文件（防止异常退出时的提示烦人）

" ==========================================
" 7. 实用快捷键映射
" ==========================================
" 按 Ctrl + L 可以快速清除搜索高亮（非常实用！）
nnoremap <silent> <C-l> :nohlsearch<CR><C-l>
VIM_EOF

    ok ".vimrc 已写入"
}

# ==========================================
# 主流程
# ==========================================
main() {
    echo "=========================================="
    echo "  Linux 易用性配置一键安装"
    echo "=========================================="
    echo ""

    check_deps

    install_bashrc
    install_tmuxconf
    install_vimrc

    echo ""
    echo "=========================================="
    ok "全部配置安装完成！"
    echo ""
    info "备份目录: $BACKUP_DIR"
    echo ""
    echo "提示:"
    echo "  1. 运行 source ~/.bashrc 使 bash 配置生效"
    echo "  2. 运行 tmux source-file ~/.tmux.conf 使 tmux 配置生效（或在 tmux 内按 '前缀键 + r'）"
    echo "  3. 下次启动 vim 时新配置自动生效"
    echo "=========================================="
}

main "$@"

