// hausocr — recognize text in an image file, print it to stdout.
//
// The whole binary exists for one palette command (commands/copy-text.sh):
// `screencapture -i` already ships the drag-an-area crosshair, and pbcopy
// already ships the clipboard, so the ONLY missing piece of "drag a region,
// its text lands on the clipboard" is image → text. Apple's Vision framework
// does that offline in ~50 lines; shelling out to it is the same trade every
// helper in this repo makes (hausax, hausdisp, barpop, floatring, hausrect):
// compile one file against a system framework with the CLT rather than pull a
// third-party OCR stack into the closure.
//
// Output is one recognized line per stdout line, in the order Vision returns
// observations — top-to-bottom in practice for the screen crops this reads.
// Multi-column layouts are inherently ambiguous to a line sorter, so no
// re-ordering pass pretends otherwise.
//
// Exit codes, read by copy-text.sh:
//   0  text on stdout
//   3  the image was readable but Vision found no text — distinct from failure
//      because "nothing legible there" is a user-facing message, not a fault
//   64 usage, 66 unreadable image, 1 Vision error

import Foundation
import ImageIO
import Vision

guard CommandLine.arguments.count == 2 else {
  FileHandle.standardError.write(Data("usage: hausocr <image>\n".utf8))
  exit(64)
}

let path = CommandLine.arguments[1]
let url = URL(fileURLWithPath: path)
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
  FileHandle.standardError.write(Data("hausocr: cannot read image at \(path)\n".utf8))
  exit(66)
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true
if #available(macOS 13.0, *) {
  request.automaticallyDetectsLanguage = true
}

do {
  try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
} catch {
  FileHandle.standardError.write(Data("hausocr: \(error.localizedDescription)\n".utf8))
  exit(1)
}

let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
guard !lines.isEmpty else { exit(3) }
print(lines.joined(separator: "\n"))
