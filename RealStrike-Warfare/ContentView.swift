import SwiftUI
import AVFoundation
import Vision

struct ContentView: View {
    @StateObject private var cameraViewModel = CameraViewModel()

    var body: some View {
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
        }
        .onAppear {
            cameraViewModel.checkPermissions()
            cameraViewModel.startSession()
        }
        .onDisappear {
            cameraViewModel.stopSession()
        }
    }
}

final class CameraViewModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession() // 🔧 Removed 'private'
    private let queue = DispatchQueue(label: "CameraQueue")

    @Published var personDetected = false

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
        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill // 🔧 Fixed
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
