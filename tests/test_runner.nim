import strutils, logging, times
import test_utils
import eiffel_test, candy_test, witch_test, ufo_test, groovy_test, candy2_test, mermaid_test, balloon_test, card_test

import core.net.server, stub_server, utils.timesync
import nimx.autotest

proc setupStubServer() =
    info "Using stub server"
    syncTime(epochTime())
    setSharedServer(StubServer.new())

if haveTestsToRun():
    setupStubServer() # TODO: This should be done in another way.

proc startFalconAutotests*() =
    uiTest theLastOne:
        waitUntil(mapLoaded(), waitUntilSceneLoaded)
        quitApplication()
    registerTest(theLastOne)

    startRequestedTests() do():
        startTest(theLastOne)

