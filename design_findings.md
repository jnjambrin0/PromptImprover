# macOS "Glass" Design Findings & Principles

## Key Technical Findings

1. **Native Materials (SwiftUI)**: SwiftUI provides built-in `Material` types (`.ultraThinMaterial`, `.thinMaterial`, `.regularMaterial`, `.thickMaterial`) that offer excellent default glass effects.
2. **AppKit Bridging (`NSVisualEffectView`)**: For the most authentic macOS "Tahoe" aesthetic (like `.sidebar`, `.headerView`, or `.underWindowBackground`), wrapping `NSVisualEffectView` via `NSViewRepresentable` provides deeper control over blending modes (`.behindWindow`, `.withinWindow`) and states (`.active`), matching the OS perfectly.
3. **Accessibility (Reduce Transparency)**: The glass effect must gracefully degrade when the user enables "Reduce Transparency" in macOS settings. We will use the `@Environment(\.accessibilityReduceTransparency)` property to supply high-contrast, solid fallback colors when this is enabled.

## Design Principles for this Redesign

- **Single Input Focus (Idle State)**: The app will launch with only the input prompt field visible. The output area will remain entirely hidden until generation begins.
- **Progressive Disclosure**: The UI will transition smoothly from the input-only state to a split/results state once the optimized prompt is generated.
- **Layered "Liquid Glass" Hierarchy**: 
  - **Base/Background**: Deep, vibrant glass effect (using AppKit/SwiftUI materials) showing the desktop wallpaper through the window.
  - **Cards/Panels**: Subtle elevated translucent surfaces for the text editors, ensuring text readability is paramount. 
  - **Controls**: Accent-colored (amber) interactions drawn from the brand palette in `AGENTS.md`.
- **Contrast & Legibility**: Ensure contrast ratios remain high, using standard Apple typography and appropriate material vibrancy layers.
