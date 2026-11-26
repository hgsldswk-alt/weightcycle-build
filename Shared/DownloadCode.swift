import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum DownloadCode {
    static let placeholder = URL(string: "https://apps.apple.com/")!

    static func url(storeID: String) -> URL {
        guard !storeID.isEmpty, storeID.utf8.allSatisfy({ (48...57).contains($0) }),
              let url = URL(string: "https://apps.apple.com/app/id" + storeID) else { return placeholder }
        return url
    }

    static func image(for url: URL) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let frame = scaled.extent.insetBy(dx: -32, dy: -32)
        let white = CIImage(color: .white).cropped(to: frame)
        return CIContext().createCGImage(scaled.composited(over: white), from: frame)
    }
}
