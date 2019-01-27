import tables, deques, logging, strutils, sequtils
import utils / game_state
import nimx / [ abstract_window, notification_center ]


type
    DeepLinkHandler* = ref object
        onHandle*: proc(route: string, next: proc())
        shouldBeQueued*: proc(route: var string)


    DeepLinkRouter = ref object
        registry: Table[string, DeepLinkHandler]
        queue: Deque[tuple[handler: string, route: string]]
        busy: bool
        enabled: bool


proc newDeepLinkRouter(): DeepLinkRouter =
    DeepLinkRouter(
        registry: initTable[string, DeepLinkHandler](),
        queue: initDeque[tuple[handler: string, route: string]](),
        enabled: true
    )


const RESTORE_DEEP_LINK = "RESTORE_DEEP_LINK"
const RESTORE_DEEP_LINK_NEEDED = "RESTORE_DEEP_LINK_NEEDED"


proc registerHandler*(r: DeepLinkRouter, id: string, handler: DeepLinkHandler) =
    r.registry[id] = handler


proc registerHandler*(r: DeepLinkRouter, id: string, onHandle: proc(route: string, next: proc()) = nil, shouldBeQueued: proc(route: var string) = nil) =
    r.registerHandler(
        id,
        DeepLinkHandler(
            onHandle: onHandle,
            shouldBeQueued: shouldBeQueued
        )
    )

proc getHandler(r: DeepLinkRouter, id: string): DeepLinkHandler =
    result = r.registry.getOrDefault(id)
    if result.isNil:
        warn "Deep links handler for `", id, "` has not been registered!"


proc dispatch(r: DeepLinkRouter) =
    info "DeepLinkRouter:try_dispatch:enabled:", r.enabled
    info "DeepLinkRouter:try_dispatch:busy:", r.busy
    info "DeepLinkRouter:try_dispatch:queue:", r.queue.len

    if r.enabled and not r.busy and r.queue.len > 0:
        let (id, route) = r.queue.popFirst()

        info "DeepLinkRouter:dispatch:", id, ",", route

        let handler = r.getHandler(id)
        if not handler.isNil and not handler.onHandle.isNil:
            r.busy = true
            handler.onHandle(route) do():
                r.busy = false
                r.dispatch()
        else:
            r.dispatch()


proc buildDeepLink*(pairs: openarray[tuple[id: string, route: string]]): string =
    result = ""
    for pair in pairs:
        result.add('/' & pair.id & '/' & pair.route)


proc handle*(r: DeepLinkRouter, path: string) =
    info "DeepLinkRouter:handle: ", path

    let pairs = path.split('/')
    var i = 0
    if pairs[0].len == 0:
        i.inc

    while i < pairs.high:
        let id = pairs[i]
        i.inc
        var route = pairs[i]
        i.inc

        let handler = r.getHandler(id)
        if not handler.isNil and not handler.shouldBeQueued.isNil:
            handler.shouldBeQueued(route)
            if route.len == 0:
                continue

        r.queue.addLast((id, route))
    r.dispatch()


proc enabled*(r: DeepLinkRouter): bool = r.enabled
proc `enabled=`*(r: DeepLinkRouter, v: bool) =
    info "DeepLinkRouter:enabled=: ", v
    r.enabled = v
    if v:
        r.dispatch()


proc clear*(r: DeepLinkRouter) =
    info "DeepLinkRouter:clear"
    r.queue = initDeque[tuple[handler: string, route: string]]()


proc restoreDeepLink*(r: DeepLinkRouter) =
    info "DeepLinkRouter:restoreDeepLink"
    r.clear()
    if hasGameState(RESTORE_DEEP_LINK):
        let state = getStringGameState(RESTORE_DEEP_LINK)
        removeGameState(RESTORE_DEEP_LINK)
        info "DeepLinkRouter:restoreDeepLink:", state
        r.handle(state)


proc saveDeepLink*(r: DeepLinkRouter, path: string) =
    info "DeepLinkRouter:saveDeepLink:", path
    setGameState(RESTORE_DEEP_LINK, path)


template saveDeepLink*(r: DeepLinkRouter, pairs: openarray[tuple[id: string, route: string]]) =
    r.saveDeepLink(pairs.buildDeepLink())


var sharedRouter: DeepLinkRouter
proc sharedDeepLinkRouter*(): DeepLinkRouter =
    if sharedRouter.isNil:
        sharedRouter = newDeepLinkRouter()
    result = sharedRouter


when defined(android):
    import jnim
    import android.app.activity
    import android.content.intent
    import android.net.uri
    import android.os.bundle


    proc getDeepLinkPath(intent: Intent): string =
        info "DeepLinkRouter:Indent:hasExtra(path):", intent.hasExtra("path");
        if intent.hasExtra("path"):
            result = intent.getStringExtra("path")
            intent.removeExtra("path")
            return

        let data = intent.getData()
        info "DeepLinkRouter:Indent:data.isNil:", data.isNil()
        if not data.isNil:
            if data.getScheme() == "https" and data.getHost() == "reelvalley.onsetgame.com":
                result = data.getPath()
                intent.setData(nil)

    proc handleInitialDeepLinks*() =
        let router = sharedDeepLinkRouter()
        let path = currentActivity().getIntent().getDeepLinkPath()

        if not path.isNil:
            router.handle(path)
        else:
            if hasGameState(RESTORE_DEEP_LINK_NEEDED) and getBoolGameState(RESTORE_DEEP_LINK_NEEDED):
                router.restoreDeepLink()

        setGameState(RESTORE_DEEP_LINK_NEEDED, true)

        sharedNotificationCenter().addObserver(AW_FOCUS_ENTER, router) do(argv: Variant):
            setGameState(RESTORE_DEEP_LINK_NEEDED, true)

            let path = currentActivity().getIntent().getDeepLinkPath()
            if not path.isNil:
                info "DeepLinkRouter:HAVE_TO_RESTART_APP"
                setGameState(RESTORE_DEEP_LINK, path)
                setGameState(RESTORE_DEEP_LINK_NEEDED, true)
                sharedNotificationCenter().postNotification("HAVE_TO_RESTART_APP")

        sharedNotificationCenter().addObserver(AW_FOCUS_LEAVE, router) do(argv: Variant):
            setGameState(RESTORE_DEEP_LINK_NEEDED, false)

else:
    proc handleInitialDeepLinks*() =
        discard
        # sharedDeepLinkRouter().handle("/scene/EiffelSlotView/window/ProfileWindow");
        # sharedDeepLinkRouter().handle("/window/ProfileWindow");
        # sharedDeepLinkRouter().dispatch()
