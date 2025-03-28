import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var inputFile: URL?
    @State private var outputFile: URL?
    @State private var conversionStatus = ""

    var body: some View {
        VStack {
            Text("NFC/Dump File Converter")
                .font(.title)

            Button("Select File") {
                selectInputFile()
            }
            .padding()

            if let file = inputFile {
                Text("Selected File: \(file.lastPathComponent)")
            }

            Button("Convert File") {
                convertFile()
            }
            .padding()
            .disabled(inputFile == nil)

            Text(conversionStatus)
                .foregroundColor(conversionStatus.contains("Error") ? .red : .green)
        }
        .frame(width: 400, height: 300)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            if let item = providers.first {
                item.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
                    if let data = data, let url =  try? URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async {
                            self.inputFile = url
                        }
                    }
                }
            }
            return true
        }
    }

    func selectInputFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "nfc")!, UTType(filenameExtension: "dump")!]

        if panel.runModal() == .OK {
            inputFile = panel.url
        }
    }

    func convertFile() {
        guard let input = inputFile else {
            conversionStatus = "Error: No file selected"
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fileExtension = input.pathExtension.lowercased()

                if fileExtension == "nfc" {
                    try convertNfcToDump(inputURL: input)
                } else if fileExtension == "dump" {
                    try convertDumpToNfc(inputURL: input)
                } else {
                    updateStatus("Error: Unsupported file type")
                }
            } catch {
                updateStatus("Conversion Error: \(error.localizedDescription)")
            }
        }
    }

    func updateStatus(_ status: String) {
        DispatchQueue.main.async {
            conversionStatus = status
        }
    }

    // Convert NFC to Dump
    func convertNfcToDump(inputURL: URL) throws {
        let content = try String(contentsOf: inputURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        var hexBlocks: [String] = []

        for line in lines {
            if line.hasPrefix("Block ") {
                let hexLine = line.replacingOccurrences(of: "Block \\d+: ", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: " ", with: "")
                    .lowercased()
                hexBlocks.append(hexLine)
            }
        }

        let dumpContent = hexBlocks.map { formatHexLine($0) }.joined(separator: "\n")

        DispatchQueue.main.async {
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [UTType(filenameExtension: "dump")!]
            
            // Retaining the original file name but with a .dump extension
            let baseName = inputURL.deletingPathExtension().lastPathComponent
            savePanel.nameFieldStringValue = "\(baseName).dump"

            if savePanel.runModal() == .OK, let saveURL = savePanel.url {
                do {
                    try dumpContent.write(to: saveURL, atomically: true, encoding: .utf8)
                    updateStatus("Successfully converted .nfc to .dump")
                    outputFile = saveURL
                } catch {
                    updateStatus("Error writing .dump file: \(error.localizedDescription)")
                }
            }
        }
    }

    // Convert Dump to NFC
    func convertDumpToNfc(inputURL: URL) throws {
        let dumpData = try Data(contentsOf: inputURL)

        var hexLines: [String] = []

        let chunkSize = 16
        for i in stride(from: 0, to: dumpData.count, by: chunkSize) {
            let chunk = dumpData.subdata(in: i..<min(i + chunkSize, dumpData.count))
            let hexLine = chunk.map { String(format: "%02X", $0) }.joined(separator: " ")
            hexLines.append(hexLine)
        }

        var nfcTemplate = """
        Filetype: Flipper NFC device
        Version: 4
        # Device type can be ISO14443-3A, ISO14443-3B, ISO14443-4A, ISO14443-4B, ISO15693-3, FeliCa, NTAG/Ultralight, Mifare Classic, Mifare DESFire, SLIX, ST25TB, EMV
        Device type: Mifare Classic
        # UID is common for all formats
        UID: \(hexLines[0].prefix(12).replacingOccurrences(of: " ", with: " "))
        # ISO14443-3A specific data
        ATQA: 00 04
        SAK: 08
        # Mifare Classic specific data
        Mifare Classic type: 1K
        Data format version: 2
        # Mifare Classic blocks, '??' means unknown data
        """

        for (index, hexLine) in hexLines.enumerated() {
            nfcTemplate += "\nBlock \(index): \(formatHexLine(hexLine))"
        }

        DispatchQueue.main.async {
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [UTType(filenameExtension: "nfc")!]
            
            // Retaining the original file name but with a .nfc extension
            let baseName = inputURL.deletingPathExtension().lastPathComponent
            savePanel.nameFieldStringValue = "\(baseName).nfc"

            if savePanel.runModal() == .OK, let saveURL = savePanel.url {
                do {
                    try nfcTemplate.write(to: saveURL, atomically: true, encoding: .utf8)
                    updateStatus("Successfully converted .dump to .nfc")
                    outputFile = saveURL
                } catch {
                    updateStatus("Error writing .nfc file: \(error.localizedDescription)")
                }
            }
        }
    }

    // Helper to format hex lines with a space every 4 characters
    func formatHexLine(_ line: String) -> String {
        let cleanLine = line.replacingOccurrences(of: " ", with: "")
        var formattedLine = ""
        for (index, char) in cleanLine.enumerated() {
            if index % 4 == 0 && index > 0 {
                formattedLine += " "
            }
            formattedLine += String(char)
        }
        return formattedLine
    }
}
