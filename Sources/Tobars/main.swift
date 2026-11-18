import Foundation
import SwiftUI

let arguments = CommandLine.arguments

if let index = arguments.firstIndex(of: "--render-snapshot") {
    guard index + 1 < arguments.count else {
        fputs("用法: Tobars --render-snapshot <输出目录>\n", stderr)
        exit(2)
    }
    let output = arguments[index + 1]
    Task { @MainActor in
        SnapshotRenderer.run(outputDirectory: output)
    }
    RunLoop.main.run()
} else if arguments.contains("--migrate-credentials") {
    CredentialMigration.run()
} else if arguments.contains("--print-usage") {
    PrintUsage.run(demo: arguments.contains("--demo"))
} else {
    TobarsApp.main()
}
