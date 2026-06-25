// Smoke.swift — headless end-to-end check of the discovery path the app uses,
// without launching the GUI or invoking claude. Compiles against the app's own
// Backend.swift + ReviewStreamParser.swift so it exercises the real code:
//
//   swiftc Sources/Backend.swift Sources/ReviewStreamParser.swift tests/Smoke.swift -o /tmp/rq-smoke
//   /tmp/rq-smoke
//
// Proves: ProcessRunner.collect spawns review-queue with the pinned PATH,
// --list-json returns 0, and the JSON decodes into [PRItem].

import Foundation

@main
struct Smoke {
    static func main() async {
        FileHandle.standardError.write(Data("smoke: review-queue = \(Paths.reviewQueueBin.path)\n".utf8))
        let r = await ProcessRunner.collect(Paths.bash, [Paths.reviewQueueBin.path, "--list-json"])
        if !r.err.isEmpty {
            FileHandle.standardError.write(Data("smoke: stderr diagnostics:\n".utf8))
            FileHandle.standardError.write(r.err)
        }
        guard r.code == 0 else {
            print("FAIL: list-json exit \(r.code)")
            exit(1)
        }
        do {
            let result = try JSONDecoder().decode(ListResult.self, from: r.out)
            print("decoded \(result.eligible.count) eligible PR(s):")
            for p in result.eligible {
                print("  \(p.name)#\(p.number)  [\(p.reason)]  \(p.title)")
            }
            print("decoded \(result.skipped.count) skipped PR(s):")
            for p in result.skipped {
                print("  \(p.name)#\(p.number)  [\(p.reason)]  \(p.title)")
            }
            print("SMOKE OK")
        } catch {
            print("FAIL: decode error: \(error)")
            exit(1)
        }
    }
}
