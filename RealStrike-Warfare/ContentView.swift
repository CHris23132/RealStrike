import SwiftUI
import AVFoundation
import Vision

struct ContentView: View {
    @StateObject private var cameraViewModel = CameraViewModel()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CameraView(cameraViewModel: cameraViewModel)
                    .edgesIgnoringSafeArea(.all)

                VStack {
                    Spacer()
                    Text(cameraViewModel.personDetected ? "👤 Person Detected" : "No Person")
                        .padding()
                        .background(cameraViewModel.personDetected ? Color.green : Color.red)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .padding()
                }
                .frame(width: geometry.size.width)
            }
            .onAppear {
                UIDevice.current.beginGeneratingDeviceOrientationNotifications()
                cameraViewModel.checkPermissions()
                cameraViewModel.startSession()
            }
            .onDisappear {
                UIDevice.current.endGeneratingDeviceOrientationNotifications()
                cameraViewModel.stopSession()
            }
        }
    }
}

final class CameraViewModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "CameraQueue")

    @Published var personDetected = false
    @Published var currentOrientation: UIDeviceOrientation = .portrait

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(orientationChanged),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
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
                if granted {
                    self.startSession()
                }
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

        session.commitConfiguration()
        session.startRunning()
    }

    func stopSession() {
        session.stopRunning()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectHumanRectanglesRequest { [weak self] request, error in
            guard let results = request.results as? [VNHumanObservation] else { return }

            DispatchQueue.main.async {
                self?.personDetected = !results.isEmpty
            }
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? handler.perform([request])
    }
}

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

        // Update preview orientation
        if let connection = context.coordinator.previewLayer?.connection,
           connection.isVideoOrientationSupported {

            let orientation = cameraViewModel.currentOrientation
            connection.videoOrientation = videoOrientation(from: orientation)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

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
