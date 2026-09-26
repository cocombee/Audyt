import Cocoa
import PDFKit

/// One production owner for PDF page previews, including form Review.
struct DocumentPreviewRenderer {
  static func render(_ data: Data, page index: Int) throws -> (bytes: Data, pages: Int) {
    guard let document = PDFDocument(data: data), !document.isLocked,
          index >= 0, index < document.pageCount, let page = document.page(at: index) else {
      throw NSError(domain: "The PDF is invalid, locked, or this page is unavailable.", code: 1)
    }
    let thumbnail = page.thumbnail(of: NSSize(width: 1440, height: 1800), for: .mediaBox)
    guard let tiff = thumbnail.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
      throw NSError(domain: "This PDF page could not be displayed.", code: 1)
    }
    return (png, document.pageCount)
  }
}
