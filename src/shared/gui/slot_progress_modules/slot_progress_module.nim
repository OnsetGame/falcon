import .. / gui_module


type SlotProgressPanelModule* = ref object of GUIModule


method checkPanel*(module: SlotProgressPanelModule, force: bool = false) {.base.} = discard