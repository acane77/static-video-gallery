# Static Video Library Generator

Scans a local directory of videos, captures screenshots for each file, and generates a browsable HTML gallery (`list/index.html`).

```bash
bash generate_videos.sh /path/to/videos
```

Once the process is complete, open `list/index.html` (located in the directory) in your web browser.

## Prerequisites

Dependencies: `ffmpeg`

### macOS

```bash
brew install ffmpeg
```

### Ubuntu (WSL2)

```bash
sudo apt update
sudo apt install -y ffmpeg
```
