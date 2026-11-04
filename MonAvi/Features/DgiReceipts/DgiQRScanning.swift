import SwiftUI
import VisionKit
import AVFoundation
import Vision
import UIKit

/// Escaneo de QR con la camara — VisionKit (`DataScannerViewController`,
/// mejor UX: resalta el codigo en vivo) cuando esta disponible, con
/// respaldo en AVFoundation puro para dispositivos/simuladores donde no
/// lo esta (el simulador de Xcode no tiene camara real, por ejemplo).
///
/// NOTA: no se pudo probar en un dispositivo real desde este entorno
/// (sin Xcode/simulador aqui) — el timing de `startScanning()` dentro de
/// `updateUIViewController` es el patron estandar para
/// `DataScannerViewController`, pero confirma en un iPhone real que la
/// camara arranca sola al abrir la pantalla.
struct DgiQRScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void
    var onError: (String) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        if DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
            let scanner = DataScannerViewController(
                recognizedDataTypes: [.barcode(symbologies: [.qr])],
                qualityLevel: .balanced,
                recognizesMultipleItems: false,
                isHighlightingEnabled: true
            )
            scanner.delegate = context.coordinator
            return scanner
        }
        return AVFoundationQRScannerViewController(onScan: onScan, onError: onError)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard let scanner = uiViewController as? DataScannerViewController, !scanner.isScanning else { return }
        DispatchQueue.main.async {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        (uiViewController as? DataScannerViewController)?.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onError: onError)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private let onError: (String) -> Void
        private var hasScanned = false

        init(onScan: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onScan = onScan
            self.onError = onError
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !hasScanned else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    hasScanned = true
                    onScan(payload)
                    return
                }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            onError("La camara no esta disponible ahorita. Intenta de nuevo o usa una foto de la galeria.")
        }
    }
}

/// Respaldo con AVFoundation puro (QR unicamente) para cuando
/// `DataScannerViewController` no esta disponible — misma idea de
/// "primer QR que aparece, listo", sin el resaltado en vivo de VisionKit.
final class AVFoundationQRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let onScan: (String) -> Void
    private let onError: (String) -> Void
    private let session = AVCaptureSession()
    private var hasScanned = false

    init(onScan: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        self.onScan = onScan
        self.onError = onError
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) no implementado")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard session.isRunning else { return }
        session.stopRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        (view.layer.sublayers?.first as? AVCaptureVideoPreviewLayer)?.frame = view.bounds
    }

    private func configureSession() {
        guard
            let device = AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            onError("No se pudo acceder a la camara.")
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            onError("No se pudo configurar el escaneo.")
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasScanned else { return }
        guard
            let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
            object.type == .qr,
            let payload = object.stringValue
        else { return }
        hasScanned = true
        session.stopRunning()
        onScan(payload)
    }
}

/// Lee un QR desde una foto de la galeria (PhotosPicker, igual que el
/// logo del negocio) — para cuando el recibo ya esta fotografiado en vez
/// de tenerlo en mano para apuntar la camara.
enum GalleryQRScanner {
    static func scan(imageData: Data) -> String? {
        guard let cgImage = UIImage(data: imageData)?.cgImage else { return nil }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        return request.results?.first { $0.symbology == .qr }?.payloadStringValue
    }
}
