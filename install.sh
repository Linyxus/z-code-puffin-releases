#!/bin/sh
# ZCode Puffin TUI：预览版的一行安装脚本（spec docs/puffin-tui.md §3「发布」）。
#
#   curl -fsSL https://raw.githubusercontent.com/Linyxus/z-code-puffin-releases/main/install.sh | sh
#
# 环境变量：
#   PUFFIN_VERSION       装指定版本（默认读 latest）
#   PUFFIN_INSTALL_DIR   安装目录（默认 ~/.local/bin）
#   PUFFIN_TARGET        覆盖平台探测（darwin-arm64 | darwin-x64 | linux-arm64 | linux-x64）
#   PUFFIN_RELEASES_URL  版本指针与校验和所在的 raw 地址（测试用）
#   PUFFIN_PACKAGES_URL  二进制所在的 Release 下载地址，其下是 v<version>/<文件>（测试用）
set -eu

releases_url="${PUFFIN_RELEASES_URL:-https://raw.githubusercontent.com/Linyxus/z-code-puffin-releases/main}"
packages_url="${PUFFIN_PACKAGES_URL:-https://github.com/Linyxus/z-code-puffin-releases/releases/download}"
install_dir="${PUFFIN_INSTALL_DIR:-$HOME/.local/bin}"

say() { printf '%s\n' "$*" >&2; }
fail() { say "install.sh: $*"; exit 1; }

command -v curl >/dev/null 2>&1 || fail "curl is required"

# 平台：uname 的说法换成 SEA 的目标名；Windows 没有安装脚本，手动下载 zcode-windows-<arch>.exe。
detect_target() {
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os" in
    Darwin) os=darwin ;;
    Linux) os=linux ;;
    *) fail "unsupported OS: $os (Windows: download zcode-windows-<arch>.exe from $packages_url/v<version>/)" ;;
  esac
  case "$arch" in
    arm64 | aarch64) arch=arm64 ;;
    x86_64 | amd64) arch=x64 ;;
    *) fail "unsupported architecture: $arch" ;;
  esac
  printf '%s-%s' "$os" "$arch"
}
target="${PUFFIN_TARGET:-$(detect_target)}"
case "$target" in
  darwin-arm64 | darwin-x64 | linux-arm64 | linux-x64) ;;
  *) fail "unsupported target: $target" ;;
esac
file="zcode-$target"

fetch() { curl -fsSL --retry 3 --retry-all-errors --connect-timeout 15 "$@"; }

# 下载二进制：终端里显示 curl 的进度条，不是终端时与 fetch 一样安静。
# 修复原因：下载原来是 `fetch --progress-bar`，而 fetch 的 -s 连进度条一起关掉，终端里从来没有进度。
# 这里不加 -s，加 -S：出错时仍说原因。
download() {
  if [ -t 2 ]; then
    curl -fSL --retry 3 --retry-all-errors --connect-timeout 15 --progress-bar "$@"
  else
    fetch "$@"
  fi
}

# 版本：显式给的，或 latest 指针（发布脚本最后才改它，所以指到的版本的二进制一定已经在了）。
version="${PUFFIN_VERSION:-}"
if [ -z "$version" ]; then
  version="$(fetch "$releases_url/latest" | tr -d '[:space:]')" || fail "could not read the latest version from $releases_url/latest"
  [ -n "$version" ] || fail "the latest version pointer is empty"
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/puffin-install.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT INT TERM

# 修复原因：这一行原来是 `$target…`。macOS 的 sh 是 bash 3.2，在非 UTF-8 locale 下把省略号的字节当成
# 变量名的一部分，`set -u` 于是报 unbound variable。脚本里的代码行只用 ASCII。
fetch -o "$tmp/SHA256SUMS" "$releases_url/releases/$version/SHA256SUMS" || fail "no checksums for version $version"

# 校验：SHA256SUMS 每行是「<hex>  <文件名>」；缺这个文件的行时拒绝安装，而不是跳过校验。
sum_of() { awk -v f="$1" '$2 == f { print $1 }' "$tmp/SHA256SUMS"; }
expected="$(sum_of "$file")"
[ -n "$expected" ] || fail "SHA256SUMS of $version has no entry for $file"

# 有 .gz 的行（0.8.0 以后的版本）且有 gzip 时下载压缩版，约为原来的 30%；解压后的二进制照样对 $file 那一行校验。
# 用时从这里算到装好，交给收尾（见文件末尾）。date 失败时按 0 秒算，不中断安装。
started="$(date +%s 2>/dev/null || echo 0)"
say "Downloading ZCode Puffin TUI $version for $target..."
if [ -n "$(sum_of "$file.gz")" ] && command -v gzip >/dev/null 2>&1; then
  download -o "$tmp/$file.gz" "$packages_url/v$version/$file.gz" || fail "download failed: $packages_url/v$version/$file.gz"
  gzip -dc "$tmp/$file.gz" >"$tmp/$file" || fail "could not unpack $file.gz"
else
  download -o "$tmp/$file" "$packages_url/v$version/$file" || fail "download failed: $packages_url/v$version/$file"
fi
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$tmp/$file" | awk '{ print $1 }')"
elif command -v shasum >/dev/null 2>&1; then
  actual="$(shasum -a 256 "$tmp/$file" | awk '{ print $1 }')"
else
  fail "sha256sum or shasum is required"
fi
[ "$actual" = "$expected" ] || fail "checksum mismatch for $file: expected $expected, got $actual"

# 安装：先复制再 rename。macOS 上原地覆盖正在运行或已缓存签名的二进制会被系统杀掉；新 inode 没有这个问题。
mkdir -p "$install_dir"
chmod +x "$tmp/$file"
cp "$tmp/$file" "$install_dir/zcode.tmp"
mv -f "$install_dir/zcode.tmp" "$install_dir/zcode"

# 收尾：stderr 是终端时，让刚装好的 zcode 画 `zcode update` 的结尾（spec §3 update「安装脚本的收尾」），
# 它画好了就不再说下面三行；它失败时照旧说。只有比 0.11.0 新的 zcode 有这个旗标。
# stdin 给 /dev/tty：`curl | sh` 时 sh 的 stdin 是脚本本身，zcode 读它会吃掉脚本，也收不到终端对探测的回答。
has_ending() {
  printf '%s\n' "$1" | awk -F '[.-]' '{ exit !($1 + 0 > 0 || $2 + 0 > 11 || ($2 + 0 == 11 && $3 + 0 > 0)) }'
}
if [ -t 2 ] && has_ending "$version"; then
  seconds=$(($(date +%s 2>/dev/null || echo "$started") - started))
  tty=/dev/null
  # 子 shell 里试：特殊内建命令的重定向失败会让整个 sh 退出。
  if (: </dev/tty) 2>/dev/null; then tty=/dev/tty; fi
  if "$install_dir/zcode" update --installed "$seconds" <"$tty"; then
    exit 0
  fi
fi

say "Installed $install_dir/zcode ($version)"
case ":$PATH:" in
  *":$install_dir:"*) ;;
  *) say "Add it to your PATH, for example:  export PATH=\"$install_dir:\$PATH\"" ;;
esac
say "Run \`zcode\` to start."
