import node_proxy / proxy
import rod / node
import json

type StoreTabKind* {.pure.} = enum
    Bucks
    Chips
    Boosters
    Vip


nodeProxy StoreTab:
    source* string
    currTaskProgress* float

method remove*(tab: StoreTab, removeFromParent: bool = true) {.base.} =
    if removeFromParent:
        tab.node.removeFromParent()
