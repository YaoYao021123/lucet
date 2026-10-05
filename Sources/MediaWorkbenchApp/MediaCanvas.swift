import AppKit
import AVKit
import CoreImage
import MediaCore
import MetalKit
import Photos
import PhotosUI
import SwiftUI

struct HDRImageCanvas: NSViewRepresentable {
    let frame: GradeFrame
    let comparing: Bool
    let hdr: Bool
    let onHeadroom: (CGFloat) -> Void

    func makeCoordinator() -> Renderer { Renderer() }
    func makeNSView(context: Context) -> MTKView {
        let view = EDRView(frame: .zero, device: context.coordinator.device)
        view.colorPixelFormat = .rgba16Float
        view.framebufferOnly = false
        view.isPaused = true; view.enableSetNeedsDisplay = true
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.delegate = context.coordinator
        if let layer = view.layer as? CAMetalLayer {
            layer.colorspace = ColorPipeline.linearSpace
            layer.wantsExtendedDynamicRangeContent = true
        }
        view.report = onHeadroom
        return view
    }
    func updateNSView(_ view: MTKView, context: Context) {
        let renderer = context.coordinator
        renderer.frame = frame; renderer.comparing = comparing; renderer.hdr = hdr
        (view as? EDRView)?.report = onHeadroom
        view.setNeedsDisplay(view.bounds)
    }

    @MainActor
    final class Renderer: NSObject, MTKViewDelegate {
        let device = MTLCreateSystemDefaultDevice()
        let queue: MTLCommandQueue?
        let context: CIContext
        var frame: GradeFrame?
        var comparing = false
        var hdr = true
        override init() {
            queue = device?.makeCommandQueue(maxCommandBufferCount: 3)
            context = device.map { CIContext(mtlDevice: $0, options: [.workingColorSpace: ColorPipeline.linearSpace,
                .workingFormat: CIFormat.RGBAh.rawValue, .cacheIntermediates: false]) } ?? ColorPipeline.context()
            super.init()
        }
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { view.setNeedsDisplay(view.bounds) }
        func draw(in view: MTKView) {
            guard let frame, let drawable = view.currentDrawable, let buffer = queue?.makeCommandBuffer() else { return }
            let size = view.drawableSize
            let canvas = CGRect(origin: .zero, size: size)
            let source = comparing ? frame.original : frame.image
            let reference = source.extent.size
            let scale = min(max(0, size.width - 40) / reference.width, max(0, size.height - 40) / reference.height)
            let headroom = comparing ? frame.sourceHeadroom : frame.headroom
            let screen = Float(view.window?.screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1)
            let mapped = ColorPipeline.toneMap(source, sourceHeadroom: headroom, targetHeadroom: hdr ? screen : 1)
            let fitted = mapped.transformed(by: .init(translationX: -mapped.extent.minX, y: -mapped.extent.minY))
                .transformed(by: .init(scaleX: scale, y: scale))
            let centered = fitted.transformed(by: .init(translationX: (size.width - fitted.extent.width) / 2,
                                                        y: (size.height - fitted.extent.height) / 2))
            let black = CIImage(color: .black).cropped(to: canvas)
            context.render(centered.composited(over: black), to: drawable.texture, commandBuffer: buffer,
                           bounds: canvas, colorSpace: ColorPipeline.linearSpace)
            buffer.present(drawable); buffer.commit()
        }
    }
    final class EDRView: MTKView {
        var report: ((CGFloat) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateHeadroom()
        }
        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            updateHeadroom()
            setNeedsDisplay(bounds)
        }
        private func updateHeadroom() {
            let headroom = window?.screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1
            Task { @MainActor [weak self] in self?.report?(headroom) }
        }
    }
}

struct VideoCanvas: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none; view.videoGravity = .resizeAspect; view.player = player
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) { if view.player !== player { view.player = player } }
}

struct LiveCanvas: NSViewRepresentable {
    let photo: PHLivePhoto
    func makeNSView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView(); view.contentMode = .aspectFit; view.livePhoto = photo
        view.startPlayback(with: .full)
        return view
    }
    func updateNSView(_ view: PHLivePhotoView, context: Context) { view.livePhoto = photo }
}
