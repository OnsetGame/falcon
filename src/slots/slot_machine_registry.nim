import falconserver.map.building.builditem
import shared / [ loading_info, director, game_scene ]
import core / slot / slot_types
import shafa / slot / slot_data_types
import nimx.class_registry
import typetraits
import logging
import tables
export SlotModeKind

template registerSlot*(b_id:BuildingId, T: typedesc) =
    method loadingInfo*(v:T): LoadingInfo =
        result = newLoadingInfo($b_id, $b_id)
    method buildingId*(v:T): BuildingId =
        result = b_id
    registerClass(T)
    buildingIdToClassName[b_id] = typetraits.name(T)

export BuildingId

var buildingIdToClassName* = initTable[BuildingId, string]()
## Register all slots resources and loading info.
buildingIdToClassName[noBuilding] = "AnySlotMachine"
buildingIdToClassName[anySlot] = "AnySlotMachine"

proc startSlotMachineGame*(slotMachineName: BuildingId, mode: SlotModeKind): GameScene =
    let director = currentDirector()
    let slotClassName = buildingIdToClassName[slotMachineName]

    if not director.currentScene.isNil and director.currentScene.name == slotClassName and 
      director.currentScene.ModedBaseMachineView.mode == mode and mode == smkDefault:
        return director.currentScene

    let scene = director.moveToScene(slotClassName).ModedBaseMachineView
    scene.mode = mode
    return scene

proc buildingIdFromClassName*(cname: string): BuildingId=
    for k, v in buildingIdToClassName:
        if v == cname:
            return k

    return noBuilding
