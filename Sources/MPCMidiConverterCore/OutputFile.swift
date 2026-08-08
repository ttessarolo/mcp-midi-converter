import Foundation

public enum OutputFile {
    public static func url(for input: URL) throws -> URL {
        let extensionLowercased = input.pathExtension.lowercased()
        guard extensionLowercased == "mid" || extensionLowercased == "midi" else {
            throw OutputFileError.unsupportedExtension(input.pathExtension)
        }
        let baseName = input.deletingPathExtension().lastPathComponent
        let outputName = "\(baseName)-mpc.\(input.pathExtension)"
        return input.deletingLastPathComponent().appendingPathComponent(outputName)
    }

    public static func write(
        _ data: Data,
        for input: URL,
        overwrite: Bool
    ) throws -> URL {
        let output = try url(for: input)
        if FileManager.default.fileExists(atPath: output.path), !overwrite {
            throw OutputFileError.outputAlreadyExists(output)
        }
        if overwrite {
            try data.write(to: output, options: .atomic)
        } else {
            do {
                try data.write(to: output, options: .withoutOverwriting)
            } catch {
                let cocoaError = error as NSError
                if cocoaError.domain == NSCocoaErrorDomain,
                   cocoaError.code == CocoaError.fileWriteFileExists.rawValue {
                    throw OutputFileError.outputAlreadyExists(output)
                }
                throw error
            }
        }
        return output
    }
}

public enum OutputFileError: LocalizedError, Equatable {
    case unsupportedExtension(String)
    case outputAlreadyExists(URL)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedExtension(fileExtension):
            "Unsupported extension: .\(fileExtension). Use a .mid or .midi file."
        case let .outputAlreadyExists(url):
            "\(url.lastPathComponent) already exists. Enable overwrite or move the existing file."
        }
    }
}
