import Testing

@testable import Maestro

@MainActor
struct MainWindowOpenerTests {
  @Test func queuesRequestUntilOpenerRegisters() {
    let opener = MainWindowOpener()
    var callCount = 0

    #expect(opener.hasRegisteredOpener == false)
    #expect(opener.openMainWindow() == true)
    #expect(callCount == 0)

    opener.register { callCount += 1 }

    #expect(opener.hasRegisteredOpener == true)
    #expect(callCount == 1)
  }

  @Test func coalescesRequestsBeforeRegistration() {
    let opener = MainWindowOpener()
    var callCount = 0

    #expect(opener.openMainWindow() == true)
    #expect(opener.openMainWindow() == true)
    #expect(opener.openMainWindow() == true)

    opener.register { callCount += 1 }

    #expect(callCount == 1)
  }

  @Test func invokesRegisteredOpenerForEveryRequest() {
    let opener = MainWindowOpener()
    var callCount = 0

    opener.register { callCount += 1 }

    #expect(opener.openMainWindow() == true)
    #expect(opener.openMainWindow() == true)
    #expect(callCount == 2)
  }

  @Test func reregisteringAfterPendingConsumptionUsesLatestOpenerWithoutReplaying() {
    let opener = MainWindowOpener()
    var firstCount = 0
    var secondCount = 0

    _ = opener.openMainWindow()
    opener.register { firstCount += 1 }
    opener.register { secondCount += 1 }

    #expect(firstCount == 1)
    #expect(secondCount == 0)

    _ = opener.openMainWindow()

    #expect(firstCount == 1)
    #expect(secondCount == 1)
  }

  @Test func reregisteringWithoutPendingReplacesPreviousOpener() {
    let opener = MainWindowOpener()
    var firstCount = 0
    var secondCount = 0

    opener.register { firstCount += 1 }
    opener.register { secondCount += 1 }

    #expect(firstCount == 0)
    #expect(secondCount == 0)

    _ = opener.openMainWindow()

    #expect(firstCount == 0)
    #expect(secondCount == 1)
  }

  @Test func clearsPendingBeforeInvokingOpener() {
    let opener = MainWindowOpener()
    var initialCount = 0
    var replacementCount = 0

    _ = opener.openMainWindow()
    opener.register {
      initialCount += 1
      opener.register { replacementCount += 1 }
    }

    #expect(initialCount == 1)
    #expect(replacementCount == 0)

    _ = opener.openMainWindow()

    #expect(initialCount == 1)
    #expect(replacementCount == 1)
  }
}
