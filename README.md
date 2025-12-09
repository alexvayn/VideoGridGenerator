cat > README.md << 'EOF'
# Video Screenshot Grid Generator

A macOS app that generates JPEG grids of video screenshots with timestamps.

## Features
- Batch process multiple videos at once
- Drag & drop files or entire folders
- Supports .mp4, .m4v, and .mov files (including 4K)
- Configurable grid dimensions
- Clean filenames matching source videos
- JPEGs saved next to original video files
- Thin white borders with compact spacing
- Filename displayed at top
- Chronological timestamps with drop shadows

## Requirements
- macOS 12.0+
- Xcode 14.0+ (for development)

## Building
1. Open VideoGridGenerator.xcodeproj in Xcode
2. Press Cmd+R to build and run

## Usage
1. Drag & drop video files/folders or click "Choose Files"
2. Set grid dimensions (columns × rows)
3. Click "Generate Grids"
4. Find JPEGs saved next to your original video files
EOF

git add README.md
git commit -m "Add README"
git push