//
//  MetalView.swift
//  metal-player
//
//  Created by Serg Liamthev on 10/19/19.
//  Copyright © 2019 serglam. All rights reserved.
//

import CoreVideo
import Foundation
import MetalKit
import MetalPerformanceShaders

final class MetalView: MTKView {
    
    var inputTime: CFTimeInterval?
    
    var pixelBuffer: CVPixelBuffer? {
        didSet {
            setNeedsDisplay()
        }
    }
    
    private var textureCache: CVMetalTextureCache?
    private var commandQueue: MTLCommandQueue
    private var computePipelineState: MTLComputePipelineState
    private var gaussianBlur: MPSImageGaussianBlur?

    private func createGaussianBlur() {
        if let device = device {
            gaussianBlur = MPSImageGaussianBlur(device: device, sigma: Float(6.0))
        }
    }

    
    override init(frame frameRect: CGRect, device: MTLDevice?) {
        // Get the default metal device.
        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            preconditionFailure("Unable to create default metal device")
        }
        
        // Create a command queue.
        guard let commandQueue = metalDevice.makeCommandQueue() else {
            preconditionFailure("Unable to create command queue")
        }
        self.commandQueue = commandQueue
        
        // Create the metal library containing the shaders
        let bundle = Bundle.main
        let url = bundle.url(forResource: "default", withExtension: "metallib")
        let library = try! metalDevice.makeLibrary(filepath: url!.path)
        
        // Create a function with a specific name.
        let function = library.makeFunction(name: "colorKernel")!
        
        // Create a compute pipeline with the above function.
        self.computePipelineState = try! metalDevice.makeComputePipelineState(function: function)
        
        // Initialize the cache to convert the pixel buffer into a Metal texture.
        var textCache: CVMetalTextureCache?
        if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, metalDevice, nil, &textCache) != kCVReturnSuccess {
            fatalError("Unable to allocate texture cache.")
        } else {
            self.textureCache = textCache
        }
        
        // Initialize super.
        super.init(frame: frameRect, device: device)
        self.isOpaque = false
        
        // Assign the metal device to this view.
        self.device = metalDevice
        
        // Enable the current drawable texture read/write.
        self.framebufferOnly = false
        
        // Disable drawable auto-resize.
        self.autoResizeDrawable = false
        
        // Set the content mode to aspect fit.
        self.contentMode = .scaleAspectFit
        
        // Change drawing mode based on setNeedsDisplay().
        self.enableSetNeedsDisplay = true
        self.isPaused = true
        
        // Set the content scale factor to the screen scale.
        self.contentScaleFactor = UIScreen.main.scale
        
        // Set the size of the drawable - see input video size
        self.drawableSize = CGSize(width: 405, height: 720)
        
        setup()
    }
    
    required init(coder: NSCoder) {
        // Get the default metal device.
        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            preconditionFailure("Unable to create default metal device")
        }
        
        // Create a command queue.
        guard let commandQueue = metalDevice.makeCommandQueue() else {
            preconditionFailure("Unable to create command queue")
        }
        self.commandQueue = commandQueue
        
        // Create the metal library containing the shaders
        let bundle = Bundle.main
        let url = bundle.url(forResource: "default", withExtension: "metallib")
        let library = try! metalDevice.makeLibrary(filepath: url!.path)
        
        // Create a function with a specific name.
        let function = library.makeFunction(name: "colorKernel")!
        
        // Create a compute pipeline with the above function.
        self.computePipelineState = try! metalDevice.makeComputePipelineState(function: function)
        
        // Initialize the cache to convert the pixel buffer into a Metal texture.
        var textCache: CVMetalTextureCache?
        if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, metalDevice, nil, &textCache) != kCVReturnSuccess {
            fatalError("Unable to allocate texture cache.")
        } else {
            self.textureCache = textCache
        }
        
        // Initialize super.
        super.init(coder: coder)
        self.isOpaque = false
        
        // Assign the metal device to this view.
        self.device = metalDevice
        
        // Enable the current drawable texture read/write.
        self.framebufferOnly = false
        
        // Disable drawable auto-resize.
        self.autoResizeDrawable = false
        
        // Set the content mode to aspect fit.
        self.contentMode = .scaleAspectFit
        
        // Change drawing mode based on setNeedsDisplay().
        self.enableSetNeedsDisplay = true
        self.isPaused = true
        
        // Set the content scale factor to the screen scale.
        self.contentScaleFactor = UIScreen.main.scale
        
//        // Set the size of the drawable - see input video size
//        self.drawableSize = CGSize(width: 1242, height: 690)
//
        
        setup()
    }
    
    func setup()
    {
        createGaussianBlur()
    }
    
    override func draw(_ rect: CGRect) {
        autoreleasepool {
            if rect.width > 0 && rect.height > 0 {
                self.render(self)
            }
        }
    }
    
    private func render(_ view: MTKView) {
        // Check if the pixel buffer exists
        guard let pixelBuffer = self.pixelBuffer else { return }
        
        // Get width and height for the pixel buffer
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        
        
        // Converts the pixel buffer in a Metal texture.
        var cvTextureOut: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, self.textureCache!, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &cvTextureOut)
        guard let cvTexture = cvTextureOut, let inputTexture = CVMetalTextureGetTexture(cvTexture) else {
            assertionFailure("Failed to create metal texture")
            return
        }
        
        // Check if Core Animation provided a drawable.
        guard let drawable: CAMetalDrawable = self.currentDrawable else { return }
        
        // Create a command buffer
        let commandBuffer = commandQueue.makeCommandBuffer()
        
        

        let containerSize = self.bounds.size;
        
        let cropWidth = containerSize.width / containerSize.height * CGFloat(height);
        let cropRect = CGRect.init(x: floor(CGFloat(width) - cropWidth) / 2, y: 0, width: cropWidth, height: CGFloat(height))

        let filter = MPSImageLanczosScale(device: device!)
        var transform = MPSScaleTransform(scaleX: 1.0, scaleY: 1.0, translateX: Double(0 - cropRect.origin.x), translateY: 0)

        
        let mtlTextureDescriptor = MTLTextureDescriptor()
        mtlTextureDescriptor.pixelFormat = .bgra8Unorm
        mtlTextureDescriptor.width = Int(cropRect.width)
        mtlTextureDescriptor.height = Int(cropRect.height)
        mtlTextureDescriptor.usage = [.shaderWrite, .shaderRead]

        // make dest texture
        guard let transformedTexture = device!.makeTexture(descriptor: mtlTextureDescriptor) else {
            fatalError()
        }

        withUnsafePointer(to: &transform) { (transformPtr: UnsafePointer<MPSScaleTransform>) -> () in
            filter.scaleTransform = transformPtr
            filter.encode(commandBuffer: commandBuffer!, sourceTexture: inputTexture, destinationTexture: transformedTexture)
        }
//        commandBuffer?.commit()
//        commandBuffer?.waitUntilCompleted()
        
        do {
            // Create a compute command encoder.
            let computeCommandEncoder = commandBuffer?.makeComputeCommandEncoder()
            
            // Set the compute pipeline state for the command encoder.
            computeCommandEncoder?.setComputePipelineState(computePipelineState)
            
            // Set the input and output textures for the compute shader.
            computeCommandEncoder?.setTexture(transformedTexture, index: 0)
            computeCommandEncoder?.setTexture(drawable.texture, index: 1)
            
            // Convert the time in a metal buffer.
            var time = Float(self.inputTime!)
            computeCommandEncoder?.setBytes(&time, length: MemoryLayout<Float>.size, index: 0)
            
            // Encode a threadgroup's execution of a compute function
            computeCommandEncoder?.dispatchThreadgroups(transformedTexture.threadGroups(), threadsPerThreadgroup: transformedTexture.threadGroupCount())
            
            // End the encoding of the command.
            computeCommandEncoder?.endEncoding()
        }
        
        // Register the current drawable for rendering.
        commandBuffer?.present(drawable)
        
//        if let gaussianBlur = gaussianBlur {
//            // apply the gaussian blur with MPS
//            let inplaceTexture = UnsafeMutablePointer<MTLTexture>.allocate(capacity: 1)
//            inplaceTexture.initialize(to: drawable.texture)
//            gaussianBlur.encode(commandBuffer: commandBuffer!, inPlaceTexture: inplaceTexture)
//        }

        
        // Commit the command buffer for execution.
        commandBuffer?.commit()
        
    }
    
}
