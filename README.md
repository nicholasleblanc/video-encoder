# Batch Video Encoder

Uses `ffmpeg` to transcode either a directory of videos or a single video file.

- `./batch-transcode.sh -h`
- `./transcode.sh -h`

Windows 10 `ffmpeg` executables can be downloaded from https://github.com/AnimMouse/ffmpeg-autobuild and put into `/bin`.

## Config

Edit `common.config` as you see fit. Defaults work great.

## Logs

`batch-transcode.sh` logs are stored in ./logs. We do not curently clean them up,
so if you want to, you will need to do so manually.

`transcode.sh` logs are stored next to the source file.
