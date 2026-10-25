#!/bin/bash

usage() {
    echo "usage: $0 [-f] [-y] [--preview-high-res] [--rm <basename>] path/to/video"
    echo "  -f                  强制重新生成详情页 HTML（不重新生成截图）"
    echo "  -y                  跳过确认提示（与 --rm 合用）"
    echo "  --preview-high-res  index.html 默认缩略图使用第 3 张完整截图（screenshot_3.jpg）"
    echo "  --rm <basename>      删除视频、截图资源目录与详情页，并更新 index.html"
}

FORCE_HTML=0
ASSUME_YES=0
PREVIEW_HIGH_RES=0
RM_VIDEO_NAME=""
while [ $# -gt 0 ]; do
    case "$1" in
        -f) FORCE_HTML=1; shift ;;
        -y) ASSUME_YES=1; shift ;;
        --preview-high-res) PREVIEW_HIGH_RES=1; shift ;;
        --rm)
            if [ -z "$2" ]; then
                echo "error: --rm requires a video basename"
                usage
                exit 1
            fi
            RM_VIDEO_NAME="$2"
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "error: unknown option: $1"; usage; exit 1 ;;
        *) break ;;
    esac
done

VIDEO_DIR="$1"
if [ "$VIDEO_DIR" == "" ]; then
    usage
    exit 1
fi
if [ ! -d "$VIDEO_DIR" ]; then
    echo "error: not a directory: $VIDEO_DIR"
    exit 1
fi

LIST_DIR="$VIDEO_DIR/list"

# 按 basename 删除视频及其关联资源，成功后由主流程重建 index.html
remove_video_by_basename() {
    local name="$1"
    if [[ "$name" == */* ]] || [[ "$name" == *..* ]]; then
        echo "error: invalid basename: $name"
        exit 1
    fi

    local video_file="$VIDEO_DIR/$name"
    if [ ! -f "$video_file" ]; then
        echo "error: video not found: $video_file"
        exit 1
    fi

    local md5
    md5=$(echo "$video_file" | md5sum | awk '{print $1}')
    local video_dir="$LIST_DIR/video_$md5"
    local video_html="$LIST_DIR/video_$md5.html"

    echo "将删除以下内容:"
    echo "  视频:     $video_file"
    echo "  资源目录: $video_dir"
    echo "  详情页:   $video_html"
    if [ "$ASSUME_YES" -eq 0 ]; then
        printf "[y/N] "
        read -r ans
        case "$ans" in
            y|Y|yes|YES) ;;
            *) echo "已取消删除。"; exit 0 ;;
        esac
    fi

    rm -f "$video_file"
    if [ -d "$video_dir" ]; then
        rm -rf "$video_dir"
    fi
    if [ -f "$video_html" ]; then
        rm -f "$video_html"
    fi
    echo "已删除: $name"
}

# 创建列表目录
mkdir -p "$LIST_DIR"

if [ -n "$RM_VIDEO_NAME" ]; then
    remove_video_by_basename "$RM_VIDEO_NAME"
fi

# 进度输出（stderr + \r 同行刷新，宽度对齐终端）
get_term_cols() {
    local c
    c=$(tput cols 2>/dev/null) || c="${COLUMNS:-}"
    if [ -z "$c" ] || [ "$c" -lt 40 ]; then
        c=80
    fi
    echo "$c"
}

format_file_name() {
    local name="$1"
    if [ "${#name}" -le 30 ]; then
        printf '%-30s' "$name"
    else
        printf '%-30s' "${name:0:27}..."
    fi
}

PROGRESS_COL_W=7
PROGRESS_HEADER_PRINTED=0

# Total / Current 列宽 = max(表头长度, 数字位数)
progress_calc_col_width() {
    local w=${#VIDEO_TOTAL}
    if [ "$w" -lt 5 ]; then
        w=5
    fi
    if [ "$w" -lt 7 ]; then
        w=7
    fi
    echo "$w"
}

progress_print_header() {
    if [ "$PROGRESS_HEADER_PRINTED" -eq 1 ]; then
        return
    fi
    PROGRESS_HEADER_PRINTED=1
    printf "%-${PROGRESS_COL_W}s  %-${PROGRESS_COL_W}s  %-30s  %s\n" \
        "Total" "Current" "File Name" "Stage" >&2
}

progress_update() {
    local current="$1"
    local total="$2"
    local base_name="$3"
    local stage="$4"
    local cols fname line
    cols=$(get_term_cols)
    fname=$(format_file_name "$base_name")
    line=$(printf "%-${PROGRESS_COL_W}s  %-${PROGRESS_COL_W}s  %s  %s" \
        "$total" "$current" "$fname" "$stage")
    printf '\r%-'"${cols}"'s' "$line" >&2
}

progress_finish() {
    if [ "$VIDEO_TOTAL" -gt 0 ]; then
        echo "" >&2
    fi
}

# 内嵌样式（函数输出，避免 macOS Bash 3.2 在 $(...) 内误解析 CSS 中的括号）
emit_page_styles() {
cat << 'STYLES_EOF'
:root {
    --bg-deep: #0a0a0f;
    --bg-surface: rgba(18, 20, 32, 0.72);
    --bg-elevated: rgba(28, 32, 52, 0.85);
    --accent-blue: #8ab4f8;
    --accent-purple: #c58af9;
    --accent-cyan: #78d9ec;
    --accent-gradient: linear-gradient(135deg, #8ab4f8 0%, #c58af9 45%, #78d9ec 100%);
    --text-primary: #e8eaed;
    --text-secondary: #9aa0a6;
    --text-muted: #5f6368;
    --border-subtle: rgba(138, 180, 248, 0.12);
    --border-glow: rgba(138, 180, 248, 0.35);
    --shadow-soft: 0 8px 32px rgba(0, 0, 0, 0.45);
    --shadow-glow: 0 0 40px rgba(138, 180, 248, 0.08);
    --radius-sm: 10px;
    --radius-md: 16px;
    --radius-lg: 24px;
    --font-sans: "Google Sans", "Segoe UI", system-ui, -apple-system, sans-serif;
    --font-mono: "JetBrains Mono", "SF Mono", "Cascadia Code", monospace;
}

*, *::before, *::after { box-sizing: border-box; }

html { scroll-behavior: smooth; }

body {
    margin: 0;
    min-height: 100vh;
    font-family: var(--font-sans);
    color: var(--text-primary);
    background: var(--bg-deep);
    line-height: 1.5;
    -webkit-font-smoothing: antialiased;
}

body::before {
    content: "";
    position: fixed;
    inset: 0;
    z-index: -2;
    background:
        radial-gradient(ellipse 80% 50% at 20% -10%, rgba(138, 180, 248, 0.18), transparent 55%),
        radial-gradient(ellipse 60% 40% at 90% 10%, rgba(197, 138, 249, 0.14), transparent 50%),
        radial-gradient(ellipse 50% 30% at 50% 100%, rgba(120, 217, 236, 0.1), transparent 45%),
        var(--bg-deep);
}

body::after {
    content: "";
    position: fixed;
    inset: 0;
    z-index: -1;
    opacity: 0.35;
    background-image:
        linear-gradient(rgba(138, 180, 248, 0.03) 1px, transparent 1px),
        linear-gradient(90deg, rgba(138, 180, 248, 0.03) 1px, transparent 1px);
    background-size: 48px 48px;
    mask-image: radial-gradient(ellipse 70% 60% at 50% 30%, black, transparent);
    pointer-events: none;
}

a {
    color: var(--accent-blue);
    text-decoration: none;
    transition: color 0.2s ease, text-shadow 0.2s ease;
}

a:hover {
    color: var(--accent-cyan);
    text-shadow: 0 0 20px rgba(120, 217, 236, 0.35);
}

.site-header {
    position: sticky;
    top: 0;
    z-index: 100;
    padding: 1.25rem 2rem;
    background: rgba(10, 10, 15, 0.75);
    backdrop-filter: blur(20px) saturate(1.2);
    -webkit-backdrop-filter: blur(20px) saturate(1.2);
    border-bottom: 1px solid var(--border-subtle);
    box-shadow: var(--shadow-glow);
}

.site-header__inner {
    max-width: 1400px;
    margin: 0 auto;
    display: flex;
    align-items: center;
    gap: 1rem;
    flex-wrap: wrap;
}

.site-logo {
    width: 40px;
    height: 40px;
    border-radius: 12px;
    background: var(--accent-gradient);
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 1.1rem;
    font-weight: 700;
    color: var(--bg-deep);
    box-shadow: 0 4px 20px rgba(138, 180, 248, 0.35);
    flex-shrink: 0;
}

.site-title {
    margin: 0;
    font-size: 1.35rem;
    font-weight: 500;
    letter-spacing: -0.02em;
    background: var(--accent-gradient);
    -webkit-background-clip: text;
    background-clip: text;
    -webkit-text-fill-color: transparent;
}

.site-subtitle {
    margin: 0;
    font-size: 0.85rem;
    color: var(--text-secondary);
    width: 100%;
    padding-left: 52px;
    margin-top: -0.5rem;
}

@media (min-width: 640px) {
    .site-subtitle {
        width: auto;
        padding-left: 0;
        margin-top: 0;
        margin-left: auto;
    }
}

.main-content {
    max-width: 1400px;
    margin: 0 auto;
    padding: 2rem;
}

.video-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
    gap: 1.5rem;
}

.video-card {
    position: relative;
    border-radius: var(--radius-md);
    background: var(--bg-surface);
    border: 1px solid var(--border-subtle);
    overflow: hidden;
    transition: transform 0.25s ease, border-color 0.25s ease, box-shadow 0.25s ease;
    backdrop-filter: blur(12px);
}

.video-card::before {
    content: "";
    position: absolute;
    inset: 0;
    border-radius: inherit;
    padding: 1px;
    background: var(--accent-gradient);
    -webkit-mask: linear-gradient(#fff 0 0) content-box, linear-gradient(#fff 0 0);
    mask: linear-gradient(#fff 0 0) content-box, linear-gradient(#fff 0 0);
    -webkit-mask-composite: xor;
    mask-composite: exclude;
    opacity: 0;
    transition: opacity 0.25s ease;
    pointer-events: none;
}

.video-card:hover {
    transform: translateY(-4px);
    border-color: var(--border-glow);
    box-shadow: var(--shadow-soft), var(--shadow-glow);
}

.video-card:hover::before { opacity: 1; }

.video-card__link {
    display: block;
    color: inherit;
}

.video-card__thumb-wrap {
    position: relative;
    aspect-ratio: 16 / 9;
    overflow: hidden;
    background: var(--bg-elevated);
}

.video-card__thumb {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
    transition: transform 0.4s ease;
}

.video-card:hover .video-card__thumb {
    transform: scale(1.04);
}

.video-card.is-previewing .video-card__thumb {
    transform: none;
}

.video-card__body {
    padding: 1rem 1.15rem 1.2rem;
}

.video-card__title {
    margin: 0;
    font-size: 0.95rem;
    font-weight: 500;
    color: var(--text-primary);
    word-break: break-all;
    line-height: 1.4;
}

.video-card__meta {
    margin: 0.4rem 0 0;
    font-size: 0.75rem;
    color: var(--text-muted);
    font-family: var(--font-mono);
}

/* 详情页 */
.back-nav {
    margin-bottom: 1.5rem;
}

.back-link {
    display: inline-flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.5rem 1rem;
    border-radius: var(--radius-sm);
    background: var(--bg-surface);
    border: 1px solid var(--border-subtle);
    font-size: 0.9rem;
    color: var(--text-secondary);
}

.back-link:hover {
    border-color: var(--border-glow);
    color: var(--accent-blue);
}

.back-link::before {
    content: "←";
    font-size: 1rem;
}

.detail-hero {
    margin-bottom: 2rem;
}

.detail-title {
    margin: 0 0 1.25rem;
    font-size: 1.5rem;
    font-weight: 500;
    letter-spacing: -0.02em;
    word-break: break-all;
}

.player-shell {
    border-radius: var(--radius-lg);
    overflow: hidden;
    background: var(--bg-elevated);
    border: 1px solid var(--border-subtle);
    box-shadow: var(--shadow-soft);
}

.player-shell video {
    display: block;
    width: 100%;
    max-height: 70vh;
    background: #000;
}

.cmd-block {
    margin-top: 1.25rem;
    padding: 1rem 1.25rem;
    border-radius: var(--radius-md);
    background: rgba(0, 0, 0, 0.35);
    border: 1px solid var(--border-subtle);
    font-family: var(--font-mono);
    font-size: 0.8rem;
    color: var(--accent-cyan);
    overflow-x: auto;
    white-space: pre-wrap;
    word-break: break-all;
}

.section-heading {
    margin: 2.5rem 0 1.25rem;
    font-size: 1.1rem;
    font-weight: 500;
    display: flex;
    align-items: center;
    gap: 0.75rem;
}

.section-heading::after {
    content: "";
    flex: 1;
    height: 1px;
    background: linear-gradient(90deg, var(--border-glow), transparent);
}

.screenshot-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 1.25rem;
}

.screenshot-item {
    border-radius: var(--radius-md);
    overflow: hidden;
    border: 1px solid var(--border-subtle);
    background: var(--bg-surface);
    transition: border-color 0.2s ease, box-shadow 0.2s ease;
}

.screenshot-item:hover {
    border-color: var(--border-glow);
    box-shadow: var(--shadow-glow);
}

.screenshot-item img {
    width: 100%;
    height: auto;
    display: block;
    vertical-align: middle;
}

.screenshot-item figcaption {
    padding: 0.6rem 0.85rem;
    font-size: 0.8rem;
    color: var(--text-muted);
    font-family: var(--font-mono);
    text-align: center;
}

@media (max-width: 900px) {
    .screenshot-grid {
        grid-template-columns: repeat(2, 1fr);
    }
}

@media (max-width: 560px) {
    .screenshot-grid {
        grid-template-columns: 1fr;
    }
}

.site-footer {
    max-width: 1400px;
    margin: 3rem auto 0;
    padding: 1.5rem 2rem 2rem;
    text-align: center;
    font-size: 0.75rem;
    color: var(--text-muted);
    border-top: 1px solid var(--border-subtle);
}

.empty-state {
    text-align: center;
    padding: 4rem 2rem;
    color: var(--text-secondary);
}

.empty-state__icon {
    font-size: 3rem;
    margin-bottom: 1rem;
    opacity: 0.5;
}
STYLES_EOF
}

# 列表页：悬停时按 1s 间隔循环播放 9 张截图
emit_preview_script() {
cat << 'PREVIEW_JS_EOF'
<script>
(function () {
    var INTERVAL_MS = 1000;
    var cards = document.querySelectorAll(".video-card[data-preview]");
    for (var c = 0; c < cards.length; c++) {
        (function (card) {
            var img = card.querySelector(".video-card__thumb");
            if (!img) return;
            var frames = card.getAttribute("data-preview").split(",");
            var defaultSrc = img.getAttribute("data-default") || img.getAttribute("src");
            var timer = null;
            var index = 0;

            function stopPreview() {
                if (timer !== null) {
                    clearInterval(timer);
                    timer = null;
                }
                card.classList.remove("is-previewing");
                img.src = defaultSrc;
            }

            function startPreview() {
                stopPreview();
                card.classList.add("is-previewing");
                for (var p = 0; p < frames.length; p++) {
                    var preload = new Image();
                    preload.src = frames[p];
                }
                index = 0;
                img.src = frames[0];
                timer = setInterval(function () {
                    index = (index + 1) % frames.length;
                    img.src = frames[index];
                }, INTERVAL_MS);
            }

            card.addEventListener("mouseenter", startPreview);
            card.addEventListener("mouseleave", stopPreview);
        })(cards[c]);
    }
})();
</script>
PREVIEW_JS_EOF
}

html_page_open() {
    local title="$1"
    local subtitle="$2"
    cat << EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${title}</title>
    <style>
EOF
    emit_page_styles
    cat << EOF
    </style>
</head>
<body>
<header class="site-header">
    <div class="site-header__inner">
        <div class="site-logo" aria-hidden="true">▶</div>
        <h1 class="site-title">${title}</h1>
        <p class="site-subtitle">${subtitle}</p>
    </div>
</header>
<main class="main-content">
EOF
}

html_page_close() {
    cat << 'EOF'
</main>
<footer class="site-footer">Generated by generate_videos.sh</footer>
</body>
</html>
EOF
}

# 生成单个视频的详情页 HTML
generate_video_detail_html() {
    local video_html="$1"
    local base_name="$2"
    local md5="$3"
    local video_file="$4"
    {
        html_page_open "$base_name" "视频详情 · 截图预览"
        echo '<nav class="back-nav"><a class="back-link" href="index.html">返回列表</a></nav>'
        echo '<section class="detail-hero">'
        echo "<h2 class=\"detail-title\">${base_name}</h2>"
        echo '<div class="player-shell">'
        echo '<video controls preload="metadata">'
        echo "    <source src=\"../${base_name}\" type=\"video/mp4\">"
        echo '    您的浏览器不支持 video 标签。'
        echo '</video>'
        echo '</div>'
        echo "<pre class=\"cmd-block\">open \"${video_file}\"</pre>"
        echo '</section>'
        echo '<h3 class="section-heading">截图预览</h3>'
        echo '<div class="screenshot-grid">'
        local i
        for i in {1..9}; do
            echo "<figure class=\"screenshot-item\">"
            echo "    <img src=\"video_${md5}/screenshot_${i}.jpg\" alt=\"截图 ${i}\" loading=\"lazy\">"
            echo "    <figcaption>#${i}</figcaption>"
            echo "</figure>"
        done
        echo '</div>'
        html_page_close
    } > "$video_html"
}

# 生成低清晰度缩略图 preview.png（约 20KB，独立于截图目录是否已存在）
generate_video_preview() {
    local video_file="$1"
    local video_dir="$2"
    local preview_file="$video_dir/preview.png"
    local duration preview_time w size

    if [ -f "$preview_file" ]; then
        return 0
    fi

    mkdir -p "$video_dir"

    duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$video_file")
    preview_time=$(echo "scale=2; $duration * 0.1" | bc)

    for w in 320 260 200 160; do
        ffmpeg -ss "$preview_time" -i "$video_file" -vframes 1 \
            -vf "scale=${w}:-2:flags=lanczos" \
            -compression_level 9 \
            "$preview_file" -y >/dev/null 2>&1
        if [ -f "$preview_file" ]; then
            size=$(wc -c < "$preview_file" | tr -d ' ')
            if [ -n "$size" ] && [ "$size" -le 25600 ]; then
                return 0
            fi
        fi
    done
}

# 生成 index.html 头部
{
    html_page_open "Video Gallery" "本地视频预览 · 科技风界面"
    echo '<div class="video-grid">'
} > "$LIST_DIR/index.html"

VIDEO_TOTAL=0
for video_file in "$VIDEO_DIR"/*.mp4 "$VIDEO_DIR"/*.avi "$VIDEO_DIR"/*.rmvb ; do
    if [ -f "$video_file" ]; then
        VIDEO_TOTAL=$((VIDEO_TOTAL + 1))
    fi
done
if [ "$VIDEO_TOTAL" -gt 0 ]; then
    PROGRESS_COL_W=$(progress_calc_col_width)
    progress_print_header
fi

VIDEO_INDEX=0

# 遍历视频目录下的所有视频文件
for video_file in "$VIDEO_DIR"/*.mp4 "$VIDEO_DIR"/*.avi "$VIDEO_DIR"/*.rmvb ; do
    if [ -f "$video_file" ]; then
        VIDEO_INDEX=$((VIDEO_INDEX + 1))
        base_name=$(basename "$video_file")

        # 计算视频文件的 MD5 哈希值
        md5=$(echo "$video_file" | md5sum | awk '{print $1}')
        # 为视频创建单独的目录
        video_dir="$LIST_DIR/video_$md5"
        video_html="$LIST_DIR/video_$md5.html"
        preview_file="$video_dir/preview.png"
        need_screenshots=0
        need_preview=0
        need_html=0
        if [ ! -d "$video_dir" ]; then
            need_screenshots=1
        fi
        if [ ! -f "$preview_file" ]; then
            need_preview=1
        fi
        if [ ! -f "$video_html" ] || [ "$FORCE_HTML" -eq 1 ]; then
            need_html=1
        fi

        if [ "$need_screenshots" -eq 1 ]; then
            progress_update "$VIDEO_INDEX" "$VIDEO_TOTAL" "$base_name" "Generating screenshots"
            mkdir -p "$video_dir"

            duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$video_file")
            start_time=$(echo "scale=2; $duration * 0.1" | bc)
            end_time=$(echo "scale=2; $duration * 0.9" | bc)
            interval=$(echo "scale=2; ($end_time - $start_time) / 8" | bc)

            for i in {0..8}; do
                screenshot_time=$(echo "scale=2; $start_time + $i * $interval" | bc)
                screenshot_file="$video_dir/screenshot_$((i + 1)).jpg"
                ffmpeg -ss "$screenshot_time" -i "$video_file" -vframes 1 -q:v 2 "$screenshot_file" -y >/dev/null 2>&1
            done
        fi

        if [ "$need_preview" -eq 1 ]; then
            progress_update "$VIDEO_INDEX" "$VIDEO_TOTAL" "$base_name" "Generating preview"
            generate_video_preview "$video_file" "$video_dir"
        fi

        if [ "$need_html" -eq 1 ]; then
            progress_update "$VIDEO_INDEX" "$VIDEO_TOTAL" "$base_name" "Generating HTML"
            generate_video_detail_html "$video_html" "$base_name" "$md5" "$video_file"
        elif [ "$need_screenshots" -eq 0 ] && [ "$need_preview" -eq 0 ]; then
            progress_update "$VIDEO_INDEX" "$VIDEO_TOTAL" "$base_name" "Skipped"
        fi

        # 将视频卡片添加到 index.html（悬停轮播 9 张截图）
        preview_urls=""
        for si in {1..9}; do
            if [ -n "$preview_urls" ]; then
                preview_urls="${preview_urls},"
            fi
            preview_urls="${preview_urls}video_${md5}/screenshot_${si}.jpg"
        done
        if [ "$PREVIEW_HIGH_RES" -eq 1 ]; then
            default_thumb="video_${md5}/screenshot_3.jpg"
        else
            default_thumb="video_${md5}/preview.png"
        fi
        cat >> "$LIST_DIR/index.html" << EOF
    <article class="video-card" data-preview="${preview_urls}">
        <a class="video-card__link" target="_blank" href="video_${md5}.html">
            <div class="video-card__thumb-wrap">
                <img class="video-card__thumb" src="${default_thumb}" data-default="${default_thumb}" alt="${base_name}" loading="lazy">
            </div>
            <div class="video-card__body">
                <h2 class="video-card__title">${base_name}</h2>
                <p class="video-card__meta">${md5:0:8}…</p>
            </div>
        </a>
    </article>
EOF
    fi
done

progress_finish

# 完成 index.html
{
    if [ "$VIDEO_TOTAL" -eq 0 ]; then
        echo '<div class="empty-state">'
        echo '<div class="empty-state__icon">◎</div>'
        echo '<p>未找到支持的视频文件（mp4 / avi / rmvb）</p>'
        echo '</div>'
    fi
    echo '</div>'
    emit_preview_script
    html_page_close
} >> "$LIST_DIR/index.html"

echo "Done. ${VIDEO_TOTAL} video(s), index.html updated."
