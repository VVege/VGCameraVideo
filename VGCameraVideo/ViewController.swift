//
//  ViewController.swift
//  VGCameraVideo
//
//  Created by 周智伟 on 2020/11/13.
//

import UIKit
import AVFoundation
import Photos

class ViewController: UIViewController {

    var layer: AVCaptureVideoPreviewLayer!
    var captureSession: AVCaptureSession!
    var animateLayer: CALayer!
    
    //视频数据处理队列
    let videoDataQueue = DispatchQueue(label: "com.xzh.videoDataCaptureQueue")
    //音频数据处理队列
    let audioDataQueue = DispatchQueue(label: "com.xzh.audioDataCaptureQueue")
    //捕捉的视频数据输出对象
    let videoDataOutput = AVCaptureVideoDataOutput()
    //捕捉的音频数据输出对象
    let audioDataOutput = AVCaptureAudioDataOutput()
    
    private var videoWriter: VGVideoWritter!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        captureSession = AVCaptureSession.init()
        configSession()
        layer = AVCaptureVideoPreviewLayer.init(session: captureSession)
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        captureSession.startRunning()
        
        animateLayer = CALayer.init()
        animateLayer.backgroundColor = UIColor.red.cgColor
        animateLayer.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        layer.addSublayer(animateLayer)
        
        animateLayer.frame = animateLayer.frame.offsetBy(dx: 100, dy: 100)
        
        setupSessionOutput()
        setupAssetWriter()
        
        let button = UIButton(frame: CGRect(x: 19, y: 20, width: 50, height: 50))
        button.setTitle("", for: <#T##UIControl.State#>)
    }
    
}

//MARK:- Private
extension ViewController {
    func configSession() {
        //配置摄像头
        guard let videoDevice = AVCaptureDevice.default(for: .video) else {
            return
        }
        do {
            let videoInput = try AVCaptureDeviceInput.init(device: videoDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            }
        } catch {
            return
        }
        
        //配置麦克风
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            return
        }
        do {
            let audioInput = try AVCaptureDeviceInput.init(device: audioDevice)
            if captureSession.canAddInput(audioInput) {
                captureSession.addInput(audioInput)
            }
        } catch {
            return
        }
    }
    
    private func setupSessionOutput(){
        let outputError = NSError.init(
            domain: "com.session.error",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey:NSLocalizedString("输出设置出错", comment: "")])
        
        //摄像头采集的yuv是压缩的视频信号，要还原成可以处理的数字信号
        let outputSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoDataOutput.videoSettings = outputSettings
        //不丢弃迟到帧，但会增加内存开销
        videoDataOutput.alwaysDiscardsLateVideoFrames = false
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataQueue)
        if captureSession.canAddOutput(videoDataOutput){
            captureSession.addOutput(videoDataOutput)
        }else{
            return
        }
        
        audioDataOutput.setSampleBufferDelegate(self, queue: audioDataQueue)
        if captureSession.canAddOutput(audioDataOutput) {
            captureSession.addOutput(audioDataOutput)
        }else{
            return
        }
        
    }
    
    private func setupAssetWriter() {
        //输出视频的参数设置，如果要自定义视频分辨率，在此设置。否则可使用相应格式的推荐参数
        guard let videoSetings = self.videoDataOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mp4) as? [String: Any],
              let audioSetings = self.audioDataOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mp4) as? [String: Any]
            else{
                return
        }
        videoWriter = VGVideoWritter(videoSetting: videoSetings, audioSetting: audioSetings, fileType: .mp4)
        //录制成功回调
        videoWriter.finishWriteCallback = { [weak self] url in
            guard let strongSelf = self else {return}
            strongSelf.saveToAlbum(atURL: url, complete: { (success) in
                DispatchQueue.main.async {
                    strongSelf.showSaveResult(isSuccess: success)
                }
                
            })
        }
    }
}

extension ViewController : AVCaptureVideoDataOutputSampleBufferDelegate,AVCaptureAudioDataOutputSampleBufferDelegate{
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output == videoDataOutput {
            //数据处理
            
            
        }else{
            
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
    }
}

extension ViewController {
    func saveToAlbum(atURL url: URL,complete: @escaping ((Bool) -> Void)){
        
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }, completionHandler: { (success, error) in
            complete(success)
        })
    }
    func showSaveResult(isSuccess: Bool) {
        let message = isSuccess ? "保存成功" : "保存失败"
        
        let alertController =  UIAlertController.init(title: nil, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction.init(title: "确定", style: .default, handler: { (action) in
            
        }))
        self .present(alertController, animated: true, completion: nil)
    }
}
