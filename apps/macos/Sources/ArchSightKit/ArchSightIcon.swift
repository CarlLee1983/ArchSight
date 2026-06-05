import SwiftUI

// MARK: - Shapes
struct FolderIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: 1, y: 3))
        path.addLine(to: CGPoint(x: w * 0.4, y: 3))
        path.addLine(to: CGPoint(x: w * 0.5, y: 5))
        path.addLine(to: CGPoint(x: w - 1, y: 5))
        path.addLine(to: CGPoint(x: w - 1, y: h - 2))
        path.addLine(to: CGPoint(x: 1, y: h - 2))
        path.closeSubpath()
        return path
    }
}

struct FolderOpenIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // Rear tab
        path.move(to: CGPoint(x: 1, y: 3))
        path.addLine(to: CGPoint(x: w * 0.35, y: 3))
        path.addLine(to: CGPoint(x: w * 0.45, y: 5))
        path.addLine(to: CGPoint(x: w - 2, y: 5))
        path.addLine(to: CGPoint(x: w - 2, y: 8))
        path.addLine(to: CGPoint(x: 1, y: 8))
        path.closeSubpath()
        
        // Front pocket (slanted)
        path.move(to: CGPoint(x: 1, y: 8))
        path.addLine(to: CGPoint(x: w - 1, y: 8))
        path.addLine(to: CGPoint(x: w - 3, y: h - 2))
        path.addLine(to: CGPoint(x: 3, y: h - 2))
        path.closeSubpath()
        
        return path
    }
}

struct FileIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let fold = w * 0.35
        path.move(to: CGPoint(x: 1, y: 1))
        path.addLine(to: CGPoint(x: w - fold - 1, y: 1))
        path.addLine(to: CGPoint(x: w - 1, y: fold + 1))
        path.addLine(to: CGPoint(x: w - 1, y: h - 1))
        path.addLine(to: CGPoint(x: 1, y: h - 1))
        path.closeSubpath()
        return path
    }
}

struct FileIconFoldShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let fold = w * 0.35
        path.move(to: CGPoint(x: w - fold - 1, y: 1))
        path.addLine(to: CGPoint(x: w - fold - 1, y: fold + 1))
        path.addLine(to: CGPoint(x: w - 1, y: fold + 1))
        path.closeSubpath()
        return path
    }
}

struct SearchIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let r = w * 0.3
        let cx = w * 0.4
        let cy = h * 0.4
        
        path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        
        path.move(to: CGPoint(x: cx + r * 0.707, y: cy + r * 0.707))
        path.addLine(to: CGPoint(x: w - 2, y: h - 2))
        return path
    }
}

struct ExplorerIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        path.addRect(CGRect(x: 1, y: 1, width: w * 0.6, height: h * 0.6))
        path.addRect(CGRect(x: w * 0.35, y: h * 0.35, width: w * 0.6, height: h * 0.6))
        return path
    }
}

struct SettingsIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let cx = w / 2
        let cy = h / 2
        let rOut = min(w, h) * 0.45
        let rIn = min(w, h) * 0.25
        
        path.addEllipse(in: CGRect(x: cx - rIn, y: cy - rIn, width: rIn * 2, height: rIn * 2))
        
        for i in 0..<8 {
            let angle = Double(i) * Double.pi / 4
            let x1 = cx + CGFloat(cos(angle)) * rIn
            let y1 = cy + CGFloat(sin(angle)) * rIn
            let x2 = cx + CGFloat(cos(angle)) * rOut
            let y2 = cy + CGFloat(sin(angle)) * rOut
            path.move(to: CGPoint(x: x1, y: y1))
            path.addLine(to: CGPoint(x: x2, y: y2))
        }
        return path
    }
}

struct CloseIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: 1, y: 1))
        path.addLine(to: CGPoint(x: w - 1, y: h - 1))
        path.move(to: CGPoint(x: w - 1, y: 1))
        path.addLine(to: CGPoint(x: 1, y: h - 1))
        return path
    }
}

// MARK: - Components View wrappers
public enum ArchSightIcon {
    public struct Folder: View {
        public var color: Color = .accentColor
        public init(color: Color = .accentColor) {
            self.color = color
        }
        public var body: some View {
            FolderIconShape()
                .stroke(color, lineWidth: 1.2)
                .frame(width: 13, height: 13)
        }
    }
    
    public struct FolderOpen: View {
        public var color: Color = .accentColor
        public init(color: Color = .accentColor) {
            self.color = color
        }
        public var body: some View {
            FolderOpenIconShape()
                .stroke(color, lineWidth: 1.2)
                .frame(width: 13, height: 13)
        }
    }
    
    public struct File: View {
        public var color: Color = .secondary
        public init(color: Color = .secondary) {
            self.color = color
        }
        public var body: some View {
            ZStack {
                FileIconShape()
                    .stroke(color, lineWidth: 1.2)
                FileIconFoldShape()
                    .stroke(color, lineWidth: 1.2)
            }
            .frame(width: 11, height: 13)
        }
    }
    
    public struct Search: View {
        public var color: Color = .primary
        public init(color: Color = .primary) {
            self.color = color
        }
        public var body: some View {
            SearchIconShape()
                .stroke(color, lineWidth: 1.2)
                .frame(width: 14, height: 14)
        }
    }
    
    public struct Explorer: View {
        public var color: Color = .primary
        public init(color: Color = .primary) {
            self.color = color
        }
        public var body: some View {
            ExplorerIconShape()
                .stroke(color, lineWidth: 1.2)
                .frame(width: 14, height: 14)
        }
    }
    
    public struct Settings: View {
        public var color: Color = .primary
        public init(color: Color = .primary) {
            self.color = color
        }
        public var body: some View {
            SettingsIconShape()
                .stroke(color, lineWidth: 1.2)
                .frame(width: 14, height: 14)
        }
    }
    
    public struct Close: View {
        public var color: Color = .secondary
        public init(color: Color = .secondary) {
            self.color = color
        }
        public var body: some View {
            CloseIconShape()
                .stroke(color, lineWidth: 1.2)
                .frame(width: 7, height: 7)
        }
    }
    
    public struct StatusIndicator: View {
        public var color: Color
        public var pulsing: Bool
        @State private var animate = false
        
        public init(color: Color, pulsing: Bool = false) {
            self.color = color
            self.pulsing = pulsing
        }
        
        public var body: some View {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .scaleEffect(pulsing && animate ? 1.3 : 1.0)
                .opacity(pulsing && animate ? 0.5 : 1.0)
                .onAppear {
                    if pulsing {
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                            animate = true
                        }
                    }
                }
        }
    }
}
