import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let files: [ExportedFile]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        var urls: [URL] = []
        for file in files {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.filename)
            try? file.data.write(to: url, options: .atomic)
            urls.append(url)
        }
        return UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
