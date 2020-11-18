//
//  VGVideoWritter.swift
//  VGCameraVideo
//
//  Created by 周智伟 on 2020/11/13.
//

import UIKit
import AVFoundation

class VGVideoWritter: NSObject {
    var videoSettings: [String:Any]
    var audioSettings: [String:Any]
    let fileType: AVFileType
    let assetWriter: AVAssetWriter
    let videoInput: AVAssetWriterInput
    let audioInput: AVAssetWriterInput
    let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor
    let processQueue = DispatchQueue(label: "com.xzh.vieoWriteQueue")
    let ciContext: CIContext = {
        let eaglContext = EAGLContext.init(api: .openGLES2)!
        //因为需要实时处理图像，通过EAGL上下文来生成CIContext对象。此时，渲染的对象被保存在GPU,并且不会被拷贝到CPU内存。
        return CIContext.init(eaglContext: eaglContext, options: [CIContextOption.workingColorSpace: NSNull()])
        
    }()
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    //是否正在写入
    var isWriting = false
    //标记接下来接收到的作为第一帧数据
    var firstSampleFlag = true
    var finishWriteCallback: ((URL) -> Void)?
    
    init(videoSetting: [String:Any],audioSetting: [String:Any],fileType: AVFileType) {
    
        self.videoSettings = videoSetting
        self.audioSettings = audioSetting
        self.fileType = fileType
        //如果要修改输出视频的宽高等，可修改videoInput配置中的AVVideoHeightKey，AVVideoWidthKey
        self.videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: self.videoSettings)
        self.audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSetting)
        //针对实时性进行优化
        self.videoInput.expectsMediaDataInRealTime = true
        self.audioInput.expectsMediaDataInRealTime = true
        //手机默认是头部向左拍摄的，需要旋转调整
        self.videoInput.transform = VGVideoWritter.fixTransform(deviceOrientation: UIDevice.current.orientation)
        //每个AssetWriterInput都期望接收CMSampelBufferRef格式的数据，如果是CVPixelBuffer格式的数据，就需要通过adaptor来格式化后再写入
        let attributes = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                          kCVPixelBufferWidthKey: videoSetting[AVVideoWidthKey]!,
                          kCVPixelBufferHeightKey: videoSetting[AVVideoHeightKey]!,
                          kCVPixelFormatOpenGLCompatibility: true] as [String : Any]
        self.pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: self.videoInput, sourcePixelBufferAttributes: attributes )
        
        let outputURL = VGVideoWritter.createTemplateFileURL()
        do {
           self.assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: fileType)
            if self.assetWriter.canAdd(videoInput) {
                self.assetWriter.add(videoInput)
            }
            if self.assetWriter.canAdd(audioInput) {
                self.assetWriter.add(audioInput)
            }
        } catch {
            fatalError()
        }
        
        super.init()
    }
    
    //MARK: - Operation
    public func startWriting() {
        processQueue.async {
            self.isWriting = true
        }
    }
    public func stopWriting() {
        isWriting = false
        processQueue.async {
            self.assetWriter.finishWriting(completionHandler: {
                if self.assetWriter.status.rawValue == 2 {
                    DispatchQueue.main.async {
                        guard let callback = self.finishWriteCallback else {
                            return
                        }
                        callback(self.assetWriter.outputURL)
                    }
                }
            })
        }
    }
    
    
    public func processImageData(sampleBuffer: CMSampleBuffer, layer : CALayer, atTime time: CMTime) {
        guard isWriting != false else { return  }
        
        if firstSampleFlag {
            //收到第一帧视频数据,开始写入
            let result = assetWriter.startWriting()
            guard result != false else {
                print("开启录制失败")
                return
            }
            assetWriter.startSession(atSourceTime: time)
            firstSampleFlag = false
        }
        
        var outputRenderBuffer: CVPixelBuffer?
        guard let pixelBufferPool = pixelBufferAdaptor.pixelBufferPool else {
            return
        }
        let result = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &outputRenderBuffer)
        if result != kCVReturnSuccess {
            return
        }
        
        if let originVideoBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let image = CIImage.init(cvPixelBuffer: originVideoBuffer)
            ciContext.render(image, to: outputRenderBuffer!, bounds: image.extent, colorSpace: colorSpace)
        }
        
        fillPixelBuffer(layer, pixelBuffer: outputRenderBuffer!)

        if videoInput.isReadyForMoreMediaData {
           let result = pixelBufferAdaptor.append(outputRenderBuffer!, withPresentationTime: time)
            if !result {
                print("拼接视频数据失败")
            }
        }
        
    }
    
    
    public func processAudioData(CMSampleBuffer buffer: CMSampleBuffer) {
        guard firstSampleFlag == false else {
            return
        }
        if audioInput.isReadyForMoreMediaData {
            let result = audioInput.append(buffer)
            if !result {
                print("拼接音频数据失败")
            }
        }
    }
    
    //MARK: - utils
    private class func createTemplateFileURL() -> URL {
        
        NSHomeDirectory()
        let path = NSTemporaryDirectory() + "writeTemp.mp4"
        let fileURL = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do { try FileManager.default.removeItem(at: fileURL) } catch {
                
            }
        }
        return fileURL
    }
    private class func fixTransform(deviceOrientation: UIDeviceOrientation) -> CGAffineTransform {
        let orientation = deviceOrientation == .unknown ? .portrait : deviceOrientation
        var result: CGAffineTransform
        
        switch orientation {
        case .landscapeRight:
            result = CGAffineTransform(rotationAngle: CGFloat(Double.pi))
        case .portraitUpsideDown:
            result = CGAffineTransform(rotationAngle: CGFloat(Double.pi / 2 * 3))
        case .portrait,.faceUp,.faceDown:
            result = CGAffineTransform(rotationAngle: CGFloat(Double.pi / 2))
        default:
            result = CGAffineTransform.identity
        }
        return result;
    }
}

///
extension VGVideoWritter {
    private func fillPixelBuffer(_ imageLayer: CALayer, pixelBuffer: CVPixelBuffer) {
        // lock the buffer memoty so no one can access it during manipulation
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
        
        // get the pixel data from the address in the memory
        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer)
        
        // create a color scheme
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        
        /// set the context size
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // generate a context where the image will be drawn
        if let context = CGContext(data: pixelData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) {
            let contentRect = CGRect(x: 0, y: 0, width: width, height: height)
            context.clear(contentRect)
            let flipVertical = CGAffineTransform.init(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(height))
            context.concatenate(flipVertical)
            // draw the layer in the context
            //绘制视频的当前帧，绘制到 context 中
           
            imageLayer.render(in: context)
            
            // unlock the buffer memory
            CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
        }
    }
}
