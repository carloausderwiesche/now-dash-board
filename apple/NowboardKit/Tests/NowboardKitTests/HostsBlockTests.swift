// The hosts-file rules: this code runs as root in the helper, so it is tested hard.

import Foundation
import Testing

@testable import NowboardKit

private let start = HostsBlock.startMarker
private let end = HostsBlock.endMarker

/// A typical macOS hosts file.
private let system = """
    ##
    # Host Database
    #
    # localhost is used to configure the loopback interface
    ##
    127.0.0.1\tlocalhost
    255.255.255.255\tbroadcasthost
    ::1             localhost

    """

// MARK: - Names

@Test func plainHostNamesAreValid() {
    for ok in ["youtube.com", "www.youtube.com", "a.b", "xn--bcher-kva.example", "my-site.co.uk", "a1.b2.c3", "x.com", "sub.domain.example.org"] {
        #expect(HostsBlock.isValidDomain(ok), "\(ok)")
    }
}

@Test func anythingThatIsNotAPlainHostNameIsRefused() {
    let tooLongLabel = String(repeating: "a", count: 64) + ".com"
    let tooLong = (0..<60).map { _ in "abcd" }.joined(separator: ".") + ".com"
    let bad = [
        "", "localhost", "com", ".", ".com", "a..b", "a.b.", "-a.com", "a-.com", "a.-b.com", "UPPER.com", "a b.com", "a.com b", "a.com\n",
        "a.com\r\nevil.com", "a.com#x", "a.com # comment", "127.0.0.1", "1.2.3.4", "999.999.999.999", "::1", "a.com/path", "a.com:80",
        "ünicode.com", "a_b.com", "a.com;rm", "$(x).com", "a.com`x`", "a\u{0}.com", "a\tb.com", "a.1", "a.123", tooLongLabel, tooLong, "*.example.com",
        "http://a.com", "a.com\u{2028}b.com", "ａ.com",
    ]
    for name in bad { #expect(!HostsBlock.isValidDomain(name), "\(name.debugDescription)") }
}

@Test func sanitizingKeepsOnlyValidDistinctSortedLowerCaseNames() {
    let result = HostsBlock.sanitize(["B.com", "a.com", "a.com", " c.com ", "bad name", "d.com.", "127.0.0.1", "a.com\nevil.com", ""])
    #expect(result == ["a.com", "b.com", "c.com", "d.com"])
    #expect(HostsBlock.sanitize([]).isEmpty)
    #expect(HostsBlock.sanitize(["nope"]).isEmpty)
}

@Test func theNumberOfNamesIsCapped() {
    let many = (0..<2000).map { "site\($0).example.com" }
    #expect(HostsBlock.sanitize(many).count == HostsBlock.maxDomains)
}

// MARK: - Inserting

@Test func theBlockIsAddedAtTheEndAndNothingElseChanges() {
    let result = HostsBlock.inserting(domains: ["youtube.com", "www.youtube.com"], into: system)
    #expect(result.hasPrefix(system))  // the file as it was, untouched
    let added = String(result.dropFirst(system.count))
    #expect(added == """
        \(start)
        127.0.0.1 www.youtube.com
        ::1 www.youtube.com
        127.0.0.1 youtube.com
        ::1 youtube.com
        \(end)

        """)
}

@Test func insertingTwiceGivesTheSameText() {
    let once = HostsBlock.inserting(domains: ["a.com", "b.com"], into: system)
    #expect(HostsBlock.inserting(domains: ["a.com", "b.com"], into: once) == once)
    // A different list replaces the old block, it doesn't add a second.
    let other = HostsBlock.inserting(domains: ["c.com"], into: once)
    #expect(other.components(separatedBy: start).count == 2)
    #expect(!other.contains("a.com") && other.contains("c.com"))
    #expect(other.hasPrefix(system))
}

@Test func removingTheBlockGivesBackTheOriginalFile() {
    let blocked = HostsBlock.inserting(domains: ["a.com"], into: system)
    #expect(HostsBlock.removing(from: blocked) == system)
    #expect(HostsBlock.removing(from: system) == system)  // nothing to remove: unchanged
    #expect(!HostsBlock.hasBlock(in: HostsBlock.removing(from: blocked)))
    #expect(HostsBlock.hasBlock(in: blocked))
}

@Test func handWrittenEntriesStayWhereTheyAre() {
    let mine = "10.0.0.5 nas.local\n127.0.0.1 youtube.com\n# my note\n"
    // Even a hand-written line for the same name outside the block is not ours to touch.
    let text = system + mine
    let blocked = HostsBlock.inserting(domains: ["youtube.com"], into: text)
    #expect(blocked.hasPrefix(text))
    #expect(HostsBlock.removing(from: blocked) == text)
}

@Test func noValidNameMeansNoBlockAndAnOldBlockIsRemoved() {
    #expect(HostsBlock.inserting(domains: [], into: system) == system)
    #expect(HostsBlock.inserting(domains: ["not a name", "1.2.3.4"], into: system) == system)
    let blocked = HostsBlock.inserting(domains: ["a.com"], into: system)
    #expect(HostsBlock.inserting(domains: ["bad"], into: blocked) == system)
}

@Test func theLinesCanNeverCarryAnythingButValidNames() {
    // A hostile list can't smuggle a second line or a comment into the file.
    let blocked = HostsBlock.inserting(
        domains: ["a.com\n127.0.0.1 bank.com", "evil.com # x", "ok.com\r\n0.0.0.0 other.com", "fine.com"], into: system)
    let added = blocked.dropFirst(system.count).split(separator: "\n").map(String.init)
    #expect(added == [start, "127.0.0.1 fine.com", "::1 fine.com", end])
}

@Test func aFileWithoutAFinalLineBreakGetsOneBeforeTheBlock() {
    let text = "127.0.0.1 localhost"  // no line break at the end
    let blocked = HostsBlock.inserting(domains: ["a.com"], into: text)
    #expect(blocked.hasPrefix("127.0.0.1 localhost\n\(start)\n"))
    // Removing gives the file back, now ending with a line break.
    #expect(HostsBlock.removing(from: blocked) == "127.0.0.1 localhost\n")
}

@Test func anEmptyFileWorks() {
    let blocked = HostsBlock.inserting(domains: ["a.com"], into: "")
    #expect(blocked == "\(start)\n127.0.0.1 a.com\n::1 a.com\n\(end)\n")
    #expect(HostsBlock.removing(from: blocked) == "")
}

@Test func windowsLineBreaksAreKept() {
    let text = "127.0.0.1 localhost\r\n::1 localhost\r\n"
    let blocked = HostsBlock.inserting(domains: ["a.com"], into: text)
    #expect(blocked == "127.0.0.1 localhost\r\n::1 localhost\r\n\(start)\r\n127.0.0.1 a.com\r\n::1 a.com\r\n\(end)\r\n")
    #expect(HostsBlock.removing(from: blocked) == text)
}

// MARK: - Half and odd blocks

@Test func aStartWithoutAnEndRemovesOnlyOurLinesBelowIt() {
    let text = "127.0.0.1 localhost\n\(start)\n127.0.0.1 a.com\n::1 a.com\n10.0.0.9 mine.local\n127.0.0.1 b.com\n"
    // The file was cut: the marker and our two lines go; the first other line and everything after stay.
    #expect(HostsBlock.removing(from: text) == "127.0.0.1 localhost\n10.0.0.9 mine.local\n127.0.0.1 b.com\n")
}

@Test func aStartAtTheVeryEndGoes() {
    #expect(HostsBlock.removing(from: "127.0.0.1 localhost\n\(start)") == "127.0.0.1 localhost\n")
    #expect(HostsBlock.removing(from: "\(start)\n") == "")
}

@Test func anEndWithoutAStartGoes() {
    #expect(HostsBlock.removing(from: "a\n\(end)\nb\n") == "a\nb\n")
}

@Test func linesAddedByHandInsideTheBlockSurvive() {
    let text = "a\n\(start)\n127.0.0.1 x.com\n10.1.1.1 mine.local\n::1 x.com\n\(end)\nb\n"
    #expect(HostsBlock.removing(from: text) == "a\n10.1.1.1 mine.local\nb\n")
}

@Test func severalBlocksAreAllRemoved() {
    let text = "a\n\(start)\n127.0.0.1 x.com\n\(end)\nb\n\(start)\n::1 y.com\n\(end)\nc\n"
    #expect(HostsBlock.removing(from: text) == "a\nb\nc\n")
}

@Test func twoStartsThenOneEndDoNotEatTheLinesBetween() {
    // start, start, ours, end: the first block ends at the first end marker; nothing outside is lost.
    let text = "a\n\(start)\nmine\n\(start)\n127.0.0.1 x.com\n\(end)\nb\n"
    let result = HostsBlock.removing(from: text)
    #expect(result.contains("a\n") && result.contains("mine\n") && result.hasSuffix("b\n"))
    #expect(!HostsBlock.hasBlock(in: result) || result.contains(start))  // a stray marker may remain, never user data lost
    #expect(!result.contains("x.com"))
}

@Test func markersWithSpacesAroundThemAreStillOurs() {
    let text = "a\n  \(start)  \n127.0.0.1\tx.com\n\(end)\t\nb\n"
    #expect(HostsBlock.removing(from: text) == "a\nb\n")
}

@Test func aLookAlikeMarkerIsNotOurs() {
    let text = "a\n# >>> nowboard focus block extra\nb\n"
    #expect(HostsBlock.removing(from: text) == text)
}

@Test func linesThatMerelyLookLikeOursOutsideABlockStay() {
    // Without markers nothing is removed, however much a line looks like one of ours.
    let text = "127.0.0.1 youtube.com\n::1 youtube.com\n"
    #expect(HostsBlock.removing(from: text) == text)
}

@Test func removingNeverChangesLinesWithOddContent() {
    let text = "\u{FEFF}# bom line\n127.0.0.1 localhost\u{00A0}\n\t\n   \nunicode ünï\n"
    #expect(HostsBlock.removing(from: text) == text)
    let blocked = HostsBlock.inserting(domains: ["a.com"], into: text)
    #expect(HostsBlock.removing(from: blocked) == text)
}

// MARK: - Sites

@Test func theDefaultSitesExpandToEveryNameTheyUse() {
    let names = BlockedSites.domains(for: BlockedSites.defaults)
    for expected in [
        "youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be", "instagram.com", "www.instagram.com", "x.com", "twitter.com",
        "reddit.com", "old.reddit.com", "facebook.com", "m.facebook.com", "fb.com", "tiktok.com", "www.tiktok.com",
    ] { #expect(names.contains(expected), "\(expected)") }
    #expect(names.allSatisfy(HostsBlock.isValidDomain))
    #expect(names == names.sorted() && Set(names).count == names.count)
}

@Test func anUnknownSiteGetsItsNameAndWww() {
    #expect(BlockedSites.names(for: "news.ycombinator.com") == ["news.ycombinator.com", "www.news.ycombinator.com"])
    #expect(BlockedSites.names(for: "example.org") == ["example.org", "www.example.org"])
    #expect(BlockedSites.names(for: "www.example.org") == ["example.org", "www.example.org"])
}

@Test func anAddressTypedByAPersonIsCutDownToItsHost() {
    #expect(BlockedSites.normalized("https://www.Example.com:8080/path?x=1#y") == "example.com")
    #expect(BlockedSites.normalized("  Example.COM ") == "example.com")
    #expect(BlockedSites.normalized("http://news.example.com/") == "news.example.com")
    for bad in ["", "   ", "localhost", "1.2.3.4", "not a site", "a.com\nb.com", "https://", "://x", "x", ".com"] {
        #expect(BlockedSites.normalized(bad) == nil, "\(bad.debugDescription)")
    }
}

@Test func twitterAndXAreTheSameSite() {
    #expect(BlockedSites.names(for: "twitter.com") == BlockedSites.names(for: "x.com"))
}

@Test func theListGrowsOnlyWithValidNewSites() {
    var list = ["youtube.com"]
    list = BlockedSites.adding("https://www.example.com/x", to: list)
    #expect(list == ["youtube.com", "example.com"])
    #expect(BlockedSites.adding("example.com", to: list) == list)  // already there
    #expect(BlockedSites.adding("not valid", to: list) == list)
    let full = (0..<BlockedSites.maxEntries).map { "site\($0).com" }
    #expect(BlockedSites.adding("one-more.com", to: full) == full)
}

@Test func hostileEntriesGiveNoNames() {
    let names = BlockedSites.domains(for: ["a.com\n127.0.0.1 bank.com", "x # y", "$(rm -rf).com", "https://evil.com\r\nb.com"])
    #expect(names.allSatisfy(HostsBlock.isValidDomain))
    #expect(!names.contains { $0.contains("bank") })
}

@Test func theMacsOwnAndAppleNamesAreNeverBlocked() {
    let protected = [
        "localhost", "a.localhost", "printer.local", "apple.com", "ocsp.apple.com", "time.apple.com", "captive.apple.com", "icloud.com",
        "mask.icloud.com", "x.icloud.com", "1.0.0.127.in-addr.arpa", "x.ip6.arpa", "mzstatic.com", "gs.apple.com", "foo.apple",
    ]
    #expect(HostsBlock.sanitize(protected).isEmpty)
    // A name that only ends in the same letters is a different name.
    #expect(HostsBlock.sanitize(["notapple.com", "myicloud.com", "pineapple.com", "localhost.example.com"]).count == 4)
}

@Test func aProtectedSiteCannotBeOnTheList() {
    #expect(BlockedSites.normalized("apple.com") == nil)
    #expect(BlockedSites.normalized("https://www.icloud.com/x") == nil)
    #expect(BlockedSites.isProtectedEntry("apple.com"))
    #expect(BlockedSites.isProtectedEntry("https://support.apple.com/"))
    #expect(!BlockedSites.isProtectedEntry("youtube.com"))
    #expect(!BlockedSites.isProtectedEntry("not a name"))  // invalid, but not "protected"
    #expect(BlockedSites.adding("apple.com", to: ["a.com"]) == ["a.com"])
}

@Test func aHugeListOfNamesIsCutBeforeItIsWorkedThrough() {
    let many = (0..<20_000).map { "bad name \($0)" } + ["good.com"]
    // The good name is past the input limit, so it isn't even looked at: the work is bounded.
    #expect(HostsBlock.sanitize(many).isEmpty)
    #expect(HostsBlock.sanitize(["good.com"] + many) == ["good.com"])
}
