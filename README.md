cat > README.md << 'EOF'
# Video Screenshot Grid Generator

A macOS app that generates JPEG grids of video screenshots with timestamps, optimized for Apple Silicon.

## Features
- **Parallel processing**: Process up to 10 videos simultaneously
- Individual progress bars for each video
- Batch process multiple videos at once
- Drag & drop files or entire folders
- Supports .mp4, .m4v, and .mov files (including 4K)
- Configurable grid dimensions
- Clean filenames matching source videos
- JPEGs saved next to original video files
- Thin white borders with compact spacing
- Filename displayed at top
- Chronological timestamps with drop shadows
- Optimized for M1/M2/M3 chips

## Requirements
- macOS 12.0+
- Apple Silicon (M1/M2/M3) recommended for best performance
- Xcode 14.0+ (for development)

## Building
1. Open VideoGridGenerator.xcodeproj in Xcode
2. Press Cmd+R to build and run

## Usage
1. Drag & drop video files/folders or click "Choose Files"
2. Set grid dimensions (columns × rows)
3. Set parallel processing limit (default: 5)
4. Click "Generate Grids"
5. Watch individual progress bars
6. Find JPEGs saved next to your original video files

## Performance Tips
- Default 5 concurrent tasks works well for most M1 Max setups
- Increase to 8-10 for smaller videos or if you have extra RAM
- Decrease to 3-4 for very large 4K videos
EOF

git add README.md
git commit -m "Add README with parallel processing details"
git push