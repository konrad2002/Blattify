import AppleArchive
import Foundation
import System

/// Packs a folder into an Apple Archive (LZFSE) file and unpacks it again.
nonisolated enum BackupArchive {
    enum ArchiveError: LocalizedError {
        case invalidKeySet

        var errorDescription: String? {
            String(localized: "The backup archive could not be created.")
        }
    }

    static func compress(directory: URL, to file: URL) throws {
        guard let keySet = ArchiveHeader.FieldKeySet("TYP,PAT,DAT,MOD,MTM") else { throw ArchiveError.invalidKeySet }
        try ArchiveByteStream.withFileStream(
            path: FilePath(file.path(percentEncoded: false)),
            mode: .writeOnly,
            options: [.create, .truncate],
            permissions: FilePermissions(rawValue: 0o644)
        ) { fileStream in
            try ArchiveByteStream.withCompressionStream(using: .lzfse, writingTo: fileStream) { compressionStream in
                try ArchiveStream.withEncodeStream(writingTo: compressionStream) { encoder in
                    try encoder.writeDirectoryContents(
                        archiveFrom: FilePath(directory.path(percentEncoded: false)),
                        keySet: keySet
                    )
                }
            }
        }
    }

    /// Extracts only `data.json` and `images/*.jpg`; everything else (e.g. paths with `..`) is skipped.
    static func extract(file: URL, to directory: URL) throws {
        try ArchiveByteStream.withFileStream(
            path: FilePath(file.path(percentEncoded: false)),
            mode: .readOnly,
            options: [],
            permissions: FilePermissions(rawValue: 0o644)
        ) { fileStream in
            try ArchiveByteStream.withDecompressionStream(readingFrom: fileStream) { decompressionStream in
                try ArchiveStream.withDecodeStream(readingFrom: decompressionStream) { decoder in
                    try ArchiveStream.withExtractStream(
                        extractingTo: FilePath(directory.path(percentEncoded: false)),
                        selectUsing: { message, path, _ in
                            guard message == .extractBegin else { return .ok }
                            return isAllowedEntry(path.string) ? .ok : .skip
                        }
                    ) { extractor in
                        _ = try ArchiveStream.process(readingFrom: decoder, writingTo: extractor)
                    }
                }
            }
        }
    }

    static func isAllowedEntry(_ path: String) -> Bool {
        path.isEmpty || path == "."
            || path == BackupCoding.dataFileName
            || path == BackupCoding.imagesDirectory
            || BackupCoding.isValidImagePath(path)
    }
}
