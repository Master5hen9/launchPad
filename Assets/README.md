# Assets

本目录存放应用图标与美术资源。

- `generate_icon.swift` — 用 AppKit 生成 1024×1024 的 Launchpad 风格图标:
  `swift Assets/generate_icon.swift` 会输出 `/tmp/appicon_1024.png`。
- `generate_status_icon.swift` — 生成菜单栏用的简洁黑白 2×2 网格模板图标:
  `swift Assets/generate_status_icon.swift` 会输出
  `Sources/launchPadCore/Resources/StatusIcon.png`(36×36)。
- `AppIcon.icns` — 打包进应用 bundle 的图标(由上面的 PNG 经 `sips` + `iconutil`
  生成,生成命令见下)。

生成 `AppIcon.icns`:

```sh
cd /tmp
rm -rf AppIcon.iconset
mkdir AppIcon.iconset
sips -z 16 16 appicon_1024.png --out AppIcon.iconset/icon_16x16.png >/dev/null
sips -z 32 32 appicon_1024.png --out AppIcon.iconset/icon_16x16@2x.png >/dev/null
sips -z 32 32 appicon_1024.png --out AppIcon.iconset/icon_32x32.png >/dev/null
sips -z 64 64 appicon_1024.png --out AppIcon.iconset/icon_32x32@2x.png >/dev/null
sips -z 128 128 appicon_1024.png --out AppIcon.iconset/icon_128x128.png >/dev/null
sips -z 256 256 appicon_1024.png --out AppIcon.iconset/icon_128x128@2x.png >/dev/null
sips -z 256 256 appicon_1024.png --out AppIcon.iconset/icon_256x256.png >/dev/null
sips -z 512 512 appicon_1024.png --out AppIcon.iconset/icon_256x256@2x.png >/dev/null
sips -z 512 512 appicon_1024.png --out AppIcon.iconset/icon_512x512.png >/dev/null
cp appicon_1024.png AppIcon.iconset/icon_512x512@2x.png
iconutil -c icns AppIcon.iconset -o AppIcon.icns
cp AppIcon.icns ~/Project/launchPad/Assets/AppIcon.icns
cp AppIcon.icns ~/Project/launchPad/Sources/launchPadCore/Resources/AppIcon.icns
```
