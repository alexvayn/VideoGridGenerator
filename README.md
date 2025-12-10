# Video Grid Generator

A professional macOS app that generates beautiful screenshot grids from video files with intelligent frame selection and customizable output options.

![macOS](https://img.shields.io/badge/macOS-12.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)
![Xcode](https://img.shields.io/badge/Xcode-14.0+-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

## Features

### Smart Frame Selection
- **Intelligent Sampling**: Automatically skips intros/outros (first/last 5%)
- **Distinctness Algorithm**: Analyzes color histograms, edge density, brightness, and color variance
- **Quality Filters**: Removes fade transitions, solid colors, and blank frames
- **Optimized Performance**: 2× oversampling with multi-metric analysis

### Flexible Output Options
- **Grid Sizes**: 1-10 rows and columns (fully customizable)
- **Output Resolutions**: 1920px, 2560px, 3000px, or 4K (3840px)
- **Aspect Modes**: Fill (crop), Fit (letterbox), or Source (preserve ratio)
- **Background Themes**: Black or White
- **Timestamps**: Optional, with customizable formatting (hh:mm:ss or mm:ss)

### Batch Processing
- **Parallel Processing**: Process up to 10 videos simultaneously
- **Drag & Drop**: Files or entire folders
- **Real-time Progress**: Individual progress bars for each video
- **Custom Output Folder**: Save to any location with proper permissions

### Professional UI
- **Split-View Layout**: Controls on left, progress queue on right
- **Settings Persistence**: All preferences saved automatically
- **Output Path Display**: See exactly where files are saved with "Reveal" buttons
- **Cancel Support**: Stop processing at any time

## Installation

### Requirements
- macOS 12.0 or later
- Apple Silicon (M1/M2/M3) or Intel processor
- Xcode 14.0+ (for building from source)

### Building from Source

1. Clone the repository:
```bash
git clone https://github.com/yourusername/VideoGridGenerator.git
cd VideoGridGenerator
```

2. Open in Xcode:
```bash
open VideoGridGenerator.xcodeproj
```

3. Configure signing:
   - Select the project in Xcode
   - Go to Signing & Capabilities
   - Select your development team

4. Build and run:
   - Press `Cmd+R` or click the Run button
   - The app will launch automatically

### Sandbox Permissions

The app requires these sandbox permissions (already configured):
- ✅ User Selected File (Read/Write)
- ✅ Downloads Folder (Read/Write)

## Usage

### Basic Workflow

1. **Add Videos**
   - Drag & drop video files or folders into the app
   - Or click "Choose Files" to select videos

2. **Configure Settings**
   - Set grid size (rows × columns)
   - Choose output width (1920px - 4K)
   - Select aspect mode and background theme
   - Toggle timestamps on/off
   - Set parallel processing limit (1-10)

3. **Optional: Set Output Folder**
   - Click "Set Output Folder" to choose where files are saved
   - Without this, files save next to the original video (if permissions allow)

4. **Generate**
   - Click "Generate Grids"
   - Watch real-time progress for each video
   - Click "Reveal" to open completed files in Finder

### Supported Formats

- `.mp4` - MPEG-4 video
- `.m4v` - iTunes video
- `.mov` - QuickTime movie

All formats support up to 4K resolution.

## Output

### File Naming

Generated files are named: `OriginalVideoName_RxC.jpg`

Examples:
- `MyVideo.mp4` → `MyVideo_4x4.jpg`
- `Interview.m4v` → `Interview_5x3.jpg`

If a file exists, it adds a suffix: `MyVideo_4x4_1.jpg`, `MyVideo_4x4_2.jpg`, etc.

### Grid Layout

```
┌─────────────────────────────────────────┐
│ Filename • 4×4 • 12m 34s                │  ← Header with metadata
├───────┬───────┬───────┬───────┐
│ 00:15 │ 01:22 │ 02:45 │ 04:12 │  ← Timestamps
├───────┼───────┼───────┼───────┤
│ 05:30 │ 06:48 │ 08:05 │ 09:23 │
├───────┼───────┼───────┼───────┤
│ 10:41 │ 11:59 │ 13:16 │ 14:34 │
├───────┼───────┼───────┼───────┤
│ 15:52 │ 17:10 │ 18:27 │ 19:45 │
└───────┴───────┴───────┴───────┘
```

- White borders around each frame (2pt)
- 8pt padding between frames
- Black or white background
- Timestamps with drop shadows for readability

## Architecture

The app follows clean MVVM architecture:

```
VideoGridGenerator/
├── Models/
│   ├── VideoJob.swift           # Job state management
│   ├── AspectMode.swift          # Aspect ratio options
│   └── BackgroundTheme.swift     # Theme options
├── ViewModels/
│   └── GeneratorViewModel.swift  # Core business logic
├── Views/
│   ├── ContentView.swift         # Main UI
│   └── DropView.swift            # Drag & drop handler
├── Services/
│   ├── FrameExtractor.swift      # Video frame extraction
│   └── GridComposer.swift        # Image composition
└── Assets.xcassets/
    └── AppIcon                   # App icon
```

### Key Components

**GeneratorViewModel**
- Manages video job queue
- Handles concurrent processing with semaphore
- Persists user preferences via @AppStorage

**FrameExtractor**
- Extracts video frames using AVFoundation
- Implements distinctness algorithm with multi-metric analysis
- Filters out low-quality frames (fades, solid colors, blank frames)

**GridComposer**
- Composites frames into grid layout
- Handles aspect ratio modes
- Renders text overlays and borders

## Performance

### Benchmarks (M1 Max, 4×4 grid)

| Resolution | Time per Video | Notes |
|------------|----------------|-------|
| 1080p      | ~3-4 seconds   | Fast |
| 4K         | ~6-8 seconds   | Optimized |
| 8K         | ~15-20 seconds | Still reasonable |

### Parallel Processing

- Default: 2 concurrent videos
- Recommended for M1 Max: 3-5
- Each video uses ~1-2GB RAM during processing

### Optimizations

- 2× candidate oversampling (down from 3×)
- 24×24 pixel analysis images (down from 32×32)
- 4 comparison points per frame (down from 8)
- 400×400 max thumbnail size (down from 800×800)

**Result**: ~40-45% faster than naive implementation with identical quality.

## Advanced Features

### Distinctness Algorithm

The app uses a sophisticated multi-metric algorithm to select the most representative frames:

1. **Color Histogram** (50% weight): Detects color/tone changes
2. **Edge Density** (30% weight): Detects scene composition changes via Sobel operator
3. **Brightness** (20% weight): Detects lighting changes using relative luminance

### Quality Filters

Frames are filtered out if they have:
- Brightness < 15% or > 85% (fade in/out)
- Edge density < 5% (blurry/out of focus)
- Color variance < 1% (solid colors/gradients)

This ensures every frame in the grid is clear, distinct, and representative.

## Troubleshooting

### Files save to wrong location

**Problem**: Files save to Downloads instead of next to video  
**Solution**: Click "Set Output Folder" and choose your desired location. This grants proper write permissions.

### Processing is slow

**Problem**: Takes longer than expected  
**Solution**: 
- Reduce grid size (try 3×3 instead of 5×5)
- Lower parallel processing count
- Use lower output resolution
- Close other intensive apps

### Some frames are still similar

**Problem**: Multiple frames look the same  
**Solution**: The video might have long static shots. Try:
- Increasing grid size to get more variety
- Using a different section of the video

### App won't accept dropped files

**Problem**: Drag & drop doesn't work  
**Solution**: 
- Make sure you're dropping .mp4, .m4v, or .mov files
- Try using "Choose Files" button instead
- Check file isn't corrupted (try playing in QuickTime)

## Development

### Running Tests

```bash
# In Xcode
Cmd+U

# Or via command line
xcodebuild test -scheme VideoGridGenerator -destination 'platform=macOS'
```

### Code Style

- Swift 5.9+
- SwiftUI for UI
- async/await for concurrency
- MVVM architecture
- Comprehensive documentation

### Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Roadmap

- [ ] Video preview with timeline scrubbing
- [ ] Custom timestamp positioning
- [ ] Export to PDF
- [ ] Preset templates (YouTube, Vimeo, etc.)
- [ ] Batch export with naming templates
- [ ] GPU acceleration for 8K videos
- [ ] Command-line interface

## License

MIT License - see LICENSE file for details

## Acknowledgments

- Built with Swift and SwiftUI
- Uses AVFoundation for video processing
- Icon design inspired by film strips and grid layouts

