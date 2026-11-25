import Foundation
import Testing

@testable import NowboardKit

/// Links as the app would make them, readable in the expectations.
private func link(_ l: ObsidianLink) -> URL? {
    switch l {
    case .note(let name): URL(string: "note:\(name.replacingOccurrences(of: " ", with: "%20"))")
    case .tag(let tag): URL(string: "tag:\(tag)")
    }
}

@Test func aWikilinkBecomesALinkToTheNote() {
    #expect(obsidianToMarkdown("See [[Meeting notes]].", link: link) == "See [Meeting notes](<note:Meeting%20notes>).")
}

@Test func aWikilinkShowsItsAlias() {
    #expect(obsidianToMarkdown("[[Meeting notes|the meeting]]", link: link) == "[the meeting](<note:Meeting%20notes>)")
}

@Test func aWikilinkToAHeadingOpensTheNote() {
    #expect(obsidianToMarkdown("[[Plan#Risks]]", link: link) == "[Plan > Risks](<note:Plan>)")
}

@Test func anEmbedBecomesALinkNotAnImage() {
    #expect(obsidianToMarkdown("![[sketch.png]]", link: link) == "[sketch.png](<note:sketch.png>)")
}

@Test func aTagBecomesALinkToItsSearch() {
    #expect(obsidianToMarkdown("#work and #area/home, done.", link: link)
        == "[#work](<tag:work>) and [#area/home](<tag:area/home>), done.")
}

@Test func headingsNumbersAndUrlFragmentsAreNotTags() {
    let text = "# Heading\nIssue #123\n[docs](https://example.com/#setup) a#b"
    #expect(obsidianToMarkdown(text, link: link) == text)
}

@Test func codeIsLeftAlone() {
    let text = "Run `grep #todo [[x]]` now\n```\n#not-a-tag [[nope]]\n```\n#yes"
    #expect(obsidianToMarkdown(text, link: link)
        == "Run `grep #todo [[x]]` now\n```\n#not-a-tag [[nope]]\n```\n[#yes](<tag:yes>)")
}

@Test func withoutAVaultWikilinksAreTextAndTagsStay() {
    #expect(obsidianToMarkdown("[[Plan|the plan]] #work", link: { _ in nil }) == "the plan #work")
}
