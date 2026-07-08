import XCTest
@testable import RustTopTahoe

final class RustTopSnapshotProviderPathTests: XCTestCase {
    func testExplicitBinaryURLWinsWhenExecutable() throws {
        let explicit = URL(fileURLWithPath: "/tmp/rusttop-explicit/rust_top")
        let override = URL(fileURLWithPath: "/tmp/rusttop-override/rust_top")
        let provider = RustTopSnapshotProvider(binaryURL: explicit)

        let resolved = try provider.resolvedBinaryURL(
            environment: ["RUSTTOP_BINARY": override.path],
            resourceURL: URL(fileURLWithPath: "/tmp/RustTopTahoe.app/Contents/Resources"),
            sourceRepoRoot: URL(fileURLWithPath: "/tmp/RustTop"),
            currentDirectoryURL: URL(fileURLWithPath: "/tmp/RustTop/macos/RustTopTahoe"),
            isExecutable: { $0 == explicit || $0 == override }
        )

        XCTAssertEqual(resolved, explicit)
    }

    func testCandidatesIncludeEnvironmentResourceRepoAndCurrentDirectoryFallbacks() {
        let provider = RustTopSnapshotProvider()
        let override = URL(fileURLWithPath: "/tmp/rusttop-override/rust_top")
        let resource = URL(fileURLWithPath: "/tmp/RustTopTahoe.app/Contents/Resources")
        let repoRoot = URL(fileURLWithPath: "/tmp/RustTop")
        let packageRoot = URL(fileURLWithPath: "/tmp/RustTop/macos/RustTopTahoe")

        let candidates = provider.candidateBinaryURLs(
            environment: ["RUSTTOP_BINARY": override.path],
            resourceURL: resource,
            sourceRepoRoot: repoRoot,
            currentDirectoryURL: packageRoot
        )

        XCTAssertEqual(candidates[0], override)
        XCTAssertEqual(candidates[1], resource.appendingPathComponent("rust_top"))
        XCTAssertEqual(candidates[2], repoRoot.appendingPathComponent("target/release/rust_top"))
        XCTAssertEqual(candidates[3], repoRoot.appendingPathComponent("target/debug/rust_top"))
        XCTAssertTrue(candidates.contains(packageRoot.appendingPathComponent("target/release/rust_top")))
        XCTAssertTrue(candidates.contains(packageRoot.appendingPathComponent("target/debug/rust_top")))
        XCTAssertTrue(candidates.contains(repoRoot.appendingPathComponent("target/release/rust_top")))
        XCTAssertTrue(candidates.contains(repoRoot.appendingPathComponent("target/debug/rust_top")))
    }

    func testMissingBinaryReportsCandidatePaths() throws {
        let provider = RustTopSnapshotProvider()
        let override = URL(fileURLWithPath: "/tmp/missing-rusttop/rust_top")
        let packageRoot = URL(fileURLWithPath: "/tmp/RustTop/macos/RustTopTahoe")

        XCTAssertThrowsError(
            try provider.resolvedBinaryURL(
                environment: ["RUSTTOP_BINARY": override.path],
                resourceURL: nil,
                sourceRepoRoot: nil,
                currentDirectoryURL: packageRoot,
                isExecutable: { _ in false }
            )
        ) { error in
            guard case SnapshotProviderError.binaryNotFound(let paths) = error else {
                return XCTFail("Expected binaryNotFound, got \(error)")
            }

            XCTAssertEqual((error as? SnapshotProviderError)?.failureState, .missingHelper)
            XCTAssertTrue(paths.contains(override.path))
            XCTAssertTrue(paths.contains(packageRoot.appendingPathComponent("target/release/rust_top").path))
            XCTAssertTrue(paths.contains(packageRoot.appendingPathComponent("target/debug/rust_top").path))
        }
    }
}
