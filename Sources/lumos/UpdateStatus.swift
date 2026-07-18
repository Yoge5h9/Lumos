#if canImport(AppKit)
import Foundation

/// Drives the "Update available" menu row. The value is produced by the LumosCore
/// updater (the daily GitHub version check); this target only renders it and
/// invokes the upgrade action.
enum UpdateStatus: Equatable {
    case upToDate
    case available(version: String)
}
#endif
