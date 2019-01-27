import rod.rod_types
import rod.node
import shared.fb_share_button

type WinDialogWindow* = ref object of RootObj
    node*: Node
    onDestroy*: proc()
    destroyed*: bool
    readyForClose*: bool
    shareBttn*: FBShareButton

method destroy*(winAnim: WinDialogWindow) {.base.} = discard

proc `onShareClick=`*(winAnim: WinDialogWindow, p: proc()) =
    discard

method createShareButton*(winAnim: WinDialogWindow) {.base.} =
    discard
