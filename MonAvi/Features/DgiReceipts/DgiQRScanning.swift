import SwiftUI
import AVFoundation
import Vision
import UIKit

/// Escaneo de QR con la camara. Usa AVFoundation directo (el detector de
/// QR nativo, el mas rapido): camara a 1080p con enfoque continuo de cerca y
/// un poco de zoom para los QR densos de la DGI, deteccion en un hilo aparte
/// y vibracion al leer. Encima, un marco con una linea verde que sube y baja.
struct DgiQRScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void
    var onError: (String) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        AVFoundationQRScannerViewController(onScan: onScan, onError: onError)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

final class AVFoundationQRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let onScan: (String) -> Void
    private let onError: (String) -> Void
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "monavi.qr.session")
    private let metadataQueue = DispatchQueue(label: "monavi.qr.metadata")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    /// Ultimo QR leido: si el mismo codigo se ve de nuevo en menos de 3 s
    /// se ignora; si era invalido, se puede intentar con otro sin reabrir.
    private var lastPayload: String?
    private var lastScanAt = Date.distantPast

    // Marco y linea animada.
    private let dimLayer = CAShapeLayer()
    private let frameLayer = CAShapeLayer()
    private let scanLine = UIView()
    private var scanLineTop: NSLayoutConstraint?
    private let scanBox = UIView()

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
        configureOverlay()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startScanLineAnimation()
        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        layoutOverlay()
    }

    private func configureSession() {
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device)
        else {
            onError("No se pudo acceder a la cámara.")
            return
        }

        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            onError("No se pudo acceder a la cámara.")
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            onError("No se pudo configurar el escaneo.")
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: metadataQueue)
        output.metadataObjectTypes = [.qr]
        session.commitConfiguration()

        // Enfoque continuo, priorizando cerca (una factura a 10-20 cm), y
        // un poco de zoom: el QR de la DGI es denso y asi se lee antes.
        if (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.videoZoomFactor = min(1.6, device.activeFormat.videoMaxZoomFactor)
            device.unlockForConfiguration()
        }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    // MARK: - Marco y linea verde

    private var boxRect: CGRect {
        let side = min(view.bounds.width, view.bounds.height) * 0.72
        return CGRect(
            x: (view.bounds.width - side) / 2,
            y: (view.bounds.height - side) / 2 - 20,
            width: side,
            height: side
        )
    }

    private func configureOverlay() {
        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = UIColor.black.withAlphaComponent(0.45).cgColor
        view.layer.addSublayer(dimLayer)

        frameLayer.strokeColor = UIColor(red: 0.13, green: 0.85, blue: 0.55, alpha: 1).cgColor
        frameLayer.fillColor = UIColor.clear.cgColor
        frameLayer.lineWidth = 4
        frameLayer.lineCap = .round
        view.layer.addSublayer(frameLayer)

        scanBox.clipsToBounds = true
        scanBox.isUserInteractionEnabled = false
        view.addSubview(scanBox)

        scanLine.backgroundColor = UIColor(red: 0.13, green: 0.85, blue: 0.55, alpha: 1)
        scanLine.layer.shadowColor = UIColor(red: 0.13, green: 0.85, blue: 0.55, alpha: 1).cgColor
        scanLine.layer.shadowOpacity = 0.9
        scanLine.layer.shadowRadius = 8
        scanLine.layer.shadowOffset = .zero
        scanLine.layer.cornerRadius = 1.5
        scanBox.addSubview(scanLine)
    }

    private func layoutOverlay() {
        let box = boxRect
        let dim = UIBezierPath(rect: view.bounds)
        dim.append(UIBezierPath(roundedRect: box, cornerRadius: 18))
        dimLayer.path = dim.cgPath

        // Esquinas del marco.
        let corner: CGFloat = 34
        let path = UIBezierPath()
        let (minX, minY, maxX, maxY) = (box.minX, box.minY, box.maxX, box.maxY)
        path.move(to: CGPoint(x: minX, y: minY + corner)); path.addLine(to: CGPoint(x: minX, y: minY)); path.addLine(to: CGPoint(x: minX + corner, y: minY))
        path.move(to: CGPoint(x: maxX - corner, y: minY)); path.addLine(to: CGPoint(x: maxX, y: minY)); path.addLine(to: CGPoint(x: maxX, y: minY + corner))
        path.move(to: CGPoint(x: maxX, y: maxY - corner)); path.addLine(to: CGPoint(x: maxX, y: maxY)); path.addLine(to: CGPoint(x: maxX - corner, y: maxY))
        path.move(to: CGPoint(x: minX + corner, y: maxY)); path.addLine(to: CGPoint(x: minX, y: maxY)); path.addLine(to: CGPoint(x: minX, y: maxY - corner))
        frameLayer.path = path.cgPath

        scanBox.frame = box.insetBy(dx: 10, dy: 10)
        if scanLine.layer.animation(forKey: "scan") == nil {
            scanLine.frame = CGRect(x: 0, y: 0, width: scanBox.bounds.width, height: 3)
        }
    }

    private func startScanLineAnimation() {
        layoutOverlay()
        scanLine.frame = CGRect(x: 0, y: 0, width: scanBox.bounds.width, height: 3)
        let animation = CABasicAnimation(keyPath: "position.y")
        animation.fromValue = 2
        animation.toValue = scanBox.bounds.height - 2
        animation.duration = 1.6
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        scanLine.layer.add(animation, forKey: "scan")
    }

    // MARK: - Deteccion

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard
            let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
            object.type == .qr,
            let payload = object.stringValue
        else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if payload == self.lastPayload, Date().timeIntervalSince(self.lastScanAt) < 3 { return }
            self.lastPayload = payload
            self.lastScanAt = Date()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            self.onScan(payload)
        }
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
