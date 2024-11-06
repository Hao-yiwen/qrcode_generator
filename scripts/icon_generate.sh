#!/bin/bash

# 创建 .appiconset 目录
ICON_SET="AppIcon.appiconset"
mkdir -p "$ICON_SET"

# 创建 Contents.json 文件
cat > "$ICON_SET/Contents.json" << EOF
{
  "images" : [
    {
      "size" : "16x16",
      "idiom" : "mac",
      "filename" : "icon_16x16.png",
      "scale" : "1x"
    },
    {
      "size" : "16x16",
      "idiom" : "mac",
      "filename" : "icon_16x16@2x.png",
      "scale" : "2x"
    },
    {
      "size" : "32x32",
      "idiom" : "mac",
      "filename" : "icon_32x32.png",
      "scale" : "1x"
    },
    {
      "size" : "32x32",
      "idiom" : "mac",
      "filename" : "icon_32x32@2x.png",
      "scale" : "2x"
    },
    {
      "size" : "128x128",
      "idiom" : "mac",
      "filename" : "icon_128x128.png",
      "scale" : "1x"
    },
    {
      "size" : "128x128",
      "idiom" : "mac",
      "filename" : "icon_128x128@2x.png",
      "scale" : "2x"
    },
    {
      "size" : "256x256",
      "idiom" : "mac",
      "filename" : "icon_256x256.png",
      "scale" : "1x"
    },
    {
      "size" : "256x256",
      "idiom" : "mac",
      "filename" : "icon_256x256@2x.png",
      "scale" : "2x"
    },
    {
      "size" : "512x512",
      "idiom" : "mac",
      "filename" : "icon_512x512.png",
      "scale" : "1x"
    },
    {
      "size" : "512x512",
      "idiom" : "mac",
      "filename" : "icon_512x512@2x.png",
      "scale" : "2x"
    }
  ],
  "info" : {
    "version" : 1,
    "author" : "xcode"
  }
}
EOF

# 生成各种尺寸的图标并应用圆角
function create_icon() {
    size=$1
    scale=$2
    output_size=$((size * scale))
    
    # 计算圆角半径（约22.35%的边长）
    radius=$(echo "scale=0; $output_size * 0.2235" | bc)
    
    convert "original_icon.png" \
        -resize ${output_size}x${output_size} \
        \( +clone -alpha extract \
           -draw "roundrectangle 0,0,$((output_size-1)),$((output_size-1)),$radius,$radius" \
           -alpha copy \) \
        -compose copy_opacity -composite \
        "$ICON_SET/icon_${size}x${size}$([[ $scale == 2 ]] && echo "@2x").png"
}

# 生成所有需要的尺寸
create_icon 16 1
create_icon 16 2
create_icon 32 1
create_icon 32 2
create_icon 128 1
create_icon 128 2
create_icon 256 1
create_icon 256 2
create_icon 512 1
create_icon 512 2

echo "图标集生成完成：$ICON_SET"