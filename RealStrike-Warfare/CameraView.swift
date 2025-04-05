// CameraView.swift
import SwiftUI
import AVFoundation

struct CameraView: UIViewRepresentable {
    @ObservedObject var cameraViewModel: CameraViewModel
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        let previewLayer = AVCaptureVideoPreviewLayer(session: cameraViewModel.session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
        if let connection = context.coordinator.previewLayer?.connection,
           connection.isVideoOrientationSupported {
            let orientation = cameraViewModel.currentOrientation
            connection.videoOrientation = videoOrientation(from: orientation)
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
    
    private func videoOrientation(from deviceOrientation: UIDeviceOrientation) -> AVCaptureVideoOrientation {
        switch deviceOrientation {
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        case .portraitUpsideDown: return .portraitUpsideDown
        default: return .portrait
        }
    }
}
