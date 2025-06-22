import Foundation
import AVFoundation
import Vision
import SwiftUI

final class CameraViewModel: NSObject, ObservableObject,
                              AVCaptureVideoDataOutputSampleBufferDelegate,
                              AVCaptureMetadataOutputObjectsDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "CameraQueue")
    
    @Published var personDetected = false
    @Published var currentOrientation: UIDeviceOrientation = .portrait
    // The normalized bounding box (in Vision coordinates) of the first detected person.
    @Published var currentDetection: CGRect? = nil
    // When a hit is registered, this temporarily holds the bounding box to show an overlay.
    @Published var hitBoundingBox: CGRect? = nil
    
    /// Called when a QR code is detected.
    var onQRCodeScanned: ((String) -> Void)?
    
    // Create a VNDetectHumanRectanglesRequest without setting unavailable properties.
    private lazy var detectionRequest: VNDetectHumanRectanglesRequest = {
        let request = VNDetectHumanRectanglesRequest { [weak self] request, error in
            guard let results = request.results as? [VNHumanObservation] else { return }
            DispatchQueue.main.async {
                self?.personDetected = !results.isEmpty
                self?.currentDetection = results.first?.boundingBox
            }
        }
        return request
    }()
    
    override init() {
        super.init()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(orientationChanged),
                                               name: UIDevice.orientationDidChangeNotification,
                                               object: nil)
    }
    
    @objc private func orientationChanged() {
        currentOrientation = UIDevice.current.orientation
    }
    
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted { self.startSession() }
            }
        default:
            break
        }
    }
    
    func startSession() {
        session.beginConfiguration()
        
        guard let camera = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else { return }
        session.addInput(input)
        
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        
        // Add metadata output for QR codes
        let metadataOutput = AVCaptureMetadataOutput()
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            metadataOutput.metadataObjectTypes = [.qr]
        }
        
        session.commitConfiguration()
        session.startRunning()
    }
    
    func stopSession() {
        session.stopRunning()
    }
    
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .up,
                                            options: [:])
        do {
            try handler.perform([detectionRequest])
        } catch {
            print("Error performing detection: \(error)")
        }
    }
    
    // MARK: - QR Code Detection

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        for object in metadataObjects {
            guard let readable = object as? AVMetadataMachineReadableCodeObject,
                  readable.type == .qr,
                  let stringValue = readable.stringValue else { continue }
            DispatchQueue.main.async {
                self.onQRCodeScanned?(stringValue)
            }
            // Only take the first QR code per frame
            break
        }
    }
}
