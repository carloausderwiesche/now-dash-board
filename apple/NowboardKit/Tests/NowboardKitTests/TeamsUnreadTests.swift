// Reading the Teams Dock badge and the words the box shows for it.

import Testing

@testable import NowboardKit

@Test func noBadgeMeansNothingUnread() {
    #expect(UnreadCount.parse(nil) == .none)
    #expect(UnreadCount.parse("") == .none)
    #expect(UnreadCount.parse("   ") == .none)
    #expect(UnreadCount.parse("\n") == .none)
    #expect(UnreadCount.parse("0") == .none)
    #expect(UnreadCount.parse(" 0 ") == .none)
    #expect(UnreadCount.parse("000") == .none)
}

@Test func aNumberIsACount() {
    #expect(UnreadCount.parse("1") == .count(1))
    #expect(UnreadCount.parse("3") == .count(3))
    #expect(UnreadCount.parse(" 42\n") == .count(42))
    #expect(UnreadCount.parse("007") == .count(7))
    #expect(UnreadCount.parse("99") == .count(99))
}

@Test func aPlusMeansAtLeast() {
    #expect(UnreadCount.parse("99+") == .atLeast(99))
    #expect(UnreadCount.parse("9+") == .atLeast(9))
    #expect(UnreadCount.parse(" 999+ ") == .atLeast(999))
    // `0+` makes no sense: something is unread but we can't say how much.
    #expect(UnreadCount.parse("0+") == .unknown)
    #expect(UnreadCount.parse("+") == .unknown)
}

@Test func thousandsSeparatorsAreAccepted() {
    #expect(UnreadCount.parse("1,234") == .count(1234))
    #expect(UnreadCount.parse("1.234") == .count(1234))
    #expect(UnreadCount.parse("1 234") == .count(1234))
    #expect(UnreadCount.parse("1\u{00A0}234") == .count(1234))
}

@Test func aDotOrUnknownTextMeansUnreadWithoutACount() {
    for text in ["•", "●", "·", "!", "new", "unread", "3 new", "-3", "1e3", "12abc", "٣", "１２", "NaN", "∞"] {
        #expect(UnreadCount.parse(text) == .unknown, "\(text)")
    }
}

@Test func aNumberTooBigForAnIntIsNotACount() {
    #expect(UnreadCount.parse("99999999999999999999999") == .unknown)
    #expect(UnreadCount.parse("99999999999999999999999+") == .unknown)
}

@Test func onlyNoneHasNothingUnread() {
    #expect(!UnreadCount.none.hasUnread)
    for other in [UnreadCount.count(1), .atLeast(99), .unknown] { #expect(other.hasUnread) }
}

// MARK: - The box's words

@Test func theBoxSaysWhatIsKnown() {
    #expect(TeamsDisplay(.unread(.count(3))) == TeamsDisplay(.unread(.count(3))))
    let three = TeamsDisplay(.unread(.count(3)))
    #expect(three.headline == "3" && three.detail == "unread" && !three.muted && !three.needsPermission)
    let many = TeamsDisplay(.unread(.atLeast(99)))
    #expect(many.headline == "99+" && !many.muted)
    let dot = TeamsDisplay(.unread(.unknown))
    #expect(dot.headline == "•" && dot.detail.contains("unknown") && !dot.muted)
}

@Test func zeroIsDifferentFromNotAvailable() {
    let zero = TeamsDisplay(.unread(.none))
    #expect(zero.headline == "0" && zero.detail == "Nothing unread" && zero.muted)
    let off = TeamsDisplay(.notRunning)
    #expect(off.headline == "—" && off.detail == "Teams isn't running" && off.muted && !off.needsPermission)
    // Both are muted, but they never read the same.
    #expect(zero != off)
}

@Test func onlyNotAllowedAsksForPermission() {
    #expect(TeamsDisplay(.notAllowed).needsPermission)
    #expect(TeamsDisplay(.notAllowed).muted)
    for status in [TeamsStatus.notRunning, .notInDock, .unread(.none), .unread(.count(1)), .unread(.unknown)] {
        #expect(!TeamsDisplay(status).needsPermission)
    }
}

@Test func aDockReadingBecomesAStatus() {
    #expect(DockBadgeReading.notAllowed.status == .notAllowed)
    #expect(DockBadgeReading.notRunning.status == .notRunning)
    #expect(DockBadgeReading.notInDock.status == .notInDock)
    #expect(DockBadgeReading.label(nil).status == .unread(.none))  // running, no badge: nothing unread
    #expect(DockBadgeReading.label("5").status == .unread(.count(5)))
    #expect(DockBadgeReading.label("•").status == .unread(.unknown))
}
