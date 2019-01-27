import
    random, strutils,nimx.matrixes,nimx.view,nimx.window,nimx.animation,nimx.image,nimx.timer,nimx.font,nimx.types,rod.rod_types,rod.node,
    rod.viewport,rod.component.text_component,rod.component.particle_emitter,rod.component.sprite,rod.component.solid,rod.component,
    rod.component.visual_modifier,rod.component.rti,tables,core.slot.base_slot_machine_view,shared.win_popup,utils.sound,utils.sound_manager,utils.displacement,
    slots.mermaid.anim_helpers, rod.component.ae_composition, utils.helpers

type Anticipator* = ref object
    frontAnim3: Animation
    backAnim3: Animation
    frontAnim4: Animation
    backAnim4: Animation
    rayNodes: seq[Node]
    anticipationLight: Node

proc hideCircles*(v: SceneView) =
    v.rootNode.findNode("ufo3_front").findNode("anticipation_front").alpha = 0.0
    v.rootNode.findNode("ufo3_back").findNode("anticipation_back_3").alpha = 0.0
    v.rootNode.findNode("ufo3").findNode("anticipation_light").hide(0.3)
proc anticipate*(v: SceneView): Anticipator =
    let front3 = v.rootNode.findNode("ufo3_front").findNode("anticipation_front")
    let back3 = v.rootNode.findNode("ufo3_back").findNode("anticipation_back_3")
    let anticipationLightNode = v.rootNode.findNode("ufo3").findNode("anticipation_light")
    let frontAnim3 = front3.component(AEComposition).compositionNamed("play")#animationNamed("play")
    let backAnim3 = back3.component(AEComposition).compositionNamed("play")
    frontAnim3.cancelBehavior = CancelBehavior.cbJumpToStart
    backAnim3.cancelBehavior = CancelBehavior.cbJumpToStart
    front3.alpha = 1.0
    back3.alpha = 1.0
    anticipationLightNode.show(0.3)

    result.new()
    result.frontAnim3 = frontAnim3
    result.backAnim3 = backAnim3
    result.anticipationLight = anticipationLightNode
    result.frontAnim3.numberOfLoops = 3
    result.backAnim3.numberOfLoops = 3
    result.rayNodes = newSeq[Node]()
    for i in 1..5:
        var ufoNodeName = "ufo$#_front".format(i)
        if i == 3:
            ufoNodeName = "ufo3"
            result.anticipationLight.playAnimation("anticipation")
        let rayNode = v.rootNode.findNode(ufoNodeName).findNode("ufo_ray")
        rayNode.playAnimation("anticipation")
        result.rayNodes.add(rayNode)

    v.addAnimation(frontAnim3)
    v.addAnimation(backAnim3)

proc stop*(a: Anticipator) =
    a.frontAnim3.cancel()
    a.backAnim3.cancel()
    a.anticipationLight.hide(0.3)
    for rayNode in a.rayNodes:
        rayNode.playAnimation("anticipationEnd")
    a.rayNodes = @[]
