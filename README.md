# ArCity - Minimalistic Room Scanner & AR Viewer

ArCity is a streamlined iOS app for 3D room scanning and visualization using AR technology. It focuses on simplicity and minimal UX while providing powerful scanning capabilities.

## Features

### Room Scanning
- **Simple Interface**: Clean, distraction-free scanning experience
- **Real-time Feedback**: Visual indicators show scan progress and quality
- **Point Cloud Processing**: Efficient point sampling for accurate room models
- **No Textures**: Pure geometric representation for minimal storage requirements

### 3D Viewing
- **Two Viewing Modes**:
  - **3D Model Viewer**: Manipulate and explore your scanned rooms in a 3D space
  - **AR Walk Mode**: Walk inside your scans in augmented reality
- **Point-based Visualization**: Clean, geometric representation of rooms

## Technical Details

### Technologies Used
- **ARKit**: For AR tracking and point cloud generation
- **RealityKit**: For AR scene rendering
- **SceneKit**: For 3D model visualization
- **Swift/SwiftUI**: For modern UI implementation

### Hardware Requirements
- iPhone or iPad with LiDAR Scanner (for optimal results)
- iOS 15.0 or later

### Data Management
- Point clouds stored locally as JSON files
- No texture or image data - only point coordinates
- Efficient point sampling to keep file sizes small while maintaining accuracy

## Usage Guide

### Scanning a Room
1. Launch the app and ensure you have good lighting
2. Tap "Start Scan" and move around the room slowly
3. The scan coverage indicator will show your progress
4. Once satisfied with the coverage, tap "Stop Scan"
5. Enter a name for your scan and save it

### Viewing Your 3D Models
1. Switch to the viewing mode using the toggle button
2. Select a previously scanned room model
3. Use "3D Model" mode to view and manipulate the model
4. Switch to "AR Walk" mode to place the model in your environment and walk through it

## Design Philosophy

ArCity embraces minimalism in both functionality and interface:

- **Focus on Core Functions**: Scanning and viewing without unnecessary features
- **Clean UI**: Minimal controls that appear only when needed
- **Efficient Data Representation**: Store only essential geometric data
- **Intuitive Experience**: Simple gestures and clear guidance

## Privacy

ArCity respects your privacy:
- No data is sent to external servers
- All scans are stored locally on your device
- Only required permissions are requested (camera, motion, location for AR)
