import Testing

// This project runs its Swift Testing suite as an executable because the
// Command Line Tools' `swift test` does not discover tests (see Package.swift).
// Run with: swift run launchPadTests
@main
struct TestRunner {
    static func main() async {
        await Testing.__swiftPMEntryPoint() as Never
    }
}
