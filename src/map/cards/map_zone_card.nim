import times, tables
import node_proxy / proxy
import rod / node
import rod / component / [text_component, ae_composition, solid]
import nimx / [types, matrixes, animation]
import utils / [helpers, icon_component, outline]
import shared / window / button_component
import shared / [localization_manager]
import quest / [quests, quest_icon_component]
import core / helpers / sound_helper


proc `icon=`*(c: ButtonComponent, icon: string) =
    let comp = c.node.findNode("icon_placeholder").component(IconComponent)
    comp.setup:
        comp.name = icon
        comp.hasOutline = true
    if not comp.iconNode.isNil:
        comp.iconNode.getComponent(Outline).radius = 25.0

proc `icon=`*(c: ButtonComponent, icon: tuple[composition: string, name: string]) =
    let comp = c.node.findNode("icon_placeholder").component(IconComponent)
    comp.setup:
        comp.composition = icon.composition
        comp.name = icon.name
        comp.hasOutline = true
    if not comp.iconNode.isNil:
        comp.iconNode.getComponent(Outline).radius = 25.0


type MapZoneCardBgStyle* {.pure.} = enum
    BottomLeft = "map_zone_info_bl"
    BottomMiddle = "map_zone_info_bm"


nodeProxy MapZoneCardBg:
    parent* Node {withName: "parent"}
    bgColor* Node {withName: "bg_color"}:
        affectsChildren = true

    showAnim* Animation {withKey: "show"}
    hideAnim* Animation {withKey: "hide"}


proc newMapZoneCardBg*(style: MapZoneCardBgStyle): MapZoneCardBg =
    result = MapZoneCardBg.new(newNodeWithResource("tiledmap/gui/ui2_0/" & $style))


nodeProxy MapZoneCard:
    showAnim* Animation {withKey: "show"}
    hideAnim* Animation {withKey: "hide"}

    bigIconBgNode* Node {withName: "circle_shape_shaderfx"}:
        affectsChildren = true

    zoneIconNode* Node {withName: "zone_icon_placeholder"}:
        alpha = 0.0
    zoneIcon* IconComponent {onNode: zoneIconNode}

    questIcon* QuestIconComponent {onNodeAdd: "quest_icon"}:
        configure do():
            np.questIcon.iconImageType = qiitSingle
            np.questIcon.mainRect = newRect(0.0, -20.0, 220.0, 220.0)

    signsPlaceholderBig Node {withName: "icons_signs_placeholder_big"}:
        alpha = 0.0
    signsPlaceholderSmall Node {withName: "icons_signs_placeholder_small"}:
        alpha = 0.0

    lockComp* Node {withName: "lock_comp"}:
        alpha = 0.0

    timerNode* Node {withName: "timer_placeholder"}:
        alpha = 0.0
    timerTextNode* Node {withName: "timer_text"}

    descriptionNode* Node {withName: "zone_description"}:
        alpha = 0.0
    descriptionText* Text {onNode: descriptionNode}:
        bounds = newRect(-175.0, -37.4, 350.0, 100.0)
        verticalAlignment = vaCenter
    descriptionWithIncomeNode* Node {withName: "zone_description_with_income"}:
        alpha = 0.0
    descriptionWithIncomeText* Text {onNode: descriptionWithIncomeNode}:
        verticalAlignment = vaCenter

    title* Node {withName: "zone_title"}
    titleBg* Node {withName: "zone_title_bg"}
    titleText* Text {onNode: title}

    cornerPlaceholder* Node {withName: "corner_placeholder"}:
        alpha = 0.0

    income* Node {withName: "income_in_zone_card"}:
        alpha = 0.0

    buttonUnlock* ButtonComponent {withValue: np.node.findNode("unlock_placeholder").createButtonComponent(newRect(-175.0, -30.0, 350.0, 60.0))}:
        enabled = false
        node.alpha = 0.0

    buttonBuild* ButtonComponent {onNode: "button_build"}:
        enabled = false
        node.alpha = 0.0

    buttonSpeedup* ButtonComponent {onNode: "button_speedup"}:
        enabled = false
        node.alpha = 0.0

    buttonComplete* ButtonComponent {onNode: "button_complete"}:
        enabled = false
        node.alpha = 0.0
        
    buttonCollect* ButtonComponent {onNode: "button_collect"}:
        enabled = false
        node.alpha = 0.0

    rewardsPlaceholder* Node {addTo: "button_controller"}:
        alpha = 0.0
        positionY = -250.0

    buttonShadow* Node {withName: "button_shadow"}:
        alpha = 0.0

    bg* MapZoneCardBg

    showHideAnimation Animation
    onAction* proc()

    isHidden* bool


template rootNode*(c: MapZoneCard): Node = c.bg.node


method show*(c: MapZoneCard, cb: proc() = nil) {.base.} =
    if not c.isHidden:
        if not cb.isNil:
            if not c.showHideAnimation.isNil:
                c.showHideAnimation.onComplete(cb)
            else:
                cb()
        return
    c.isHidden = false

    c.node.playSound("BUILDINGMENU_OPEN")

    if not c.showHideAnimation.isNil:
        c.showHideAnimation.cancel()
        c.showHideAnimation = nil

    let showHideAnimation = newCompositAnimation(true, c.bg.showAnim, c.showAnim)
    showHideAnimation.numberOfLoops = 1
    showHideAnimation.onComplete do():
        if not showHideAnimation.isCancelled:
            c.showHideAnimation = nil
        if not cb.isNil:
            cb()

    c.node.addAnimation(showHideAnimation)
    c.showHideAnimation = showHideAnimation

method hide*(c: MapZoneCard, cb: proc() = nil) {.base.} =
    if c.isHidden:
        if not cb.isNil:
            cb()
        return
    c.isHidden = true

    c.node.playSound("BUILDINGMENU_HIDE")

    if not c.showHideAnimation.isNil:
        c.showHideAnimation.cancel()
        c.showHideAnimation = nil

    let showHideAnimation = newCompositAnimation(true, c.bg.hideAnim, c.hideAnim)
    showHideAnimation.numberOfLoops = 1
    showHideAnimation.onComplete do():
        if not showHideAnimation.isCancelled:
            c.showHideAnimation = nil
        if not cb.isNil:
            cb()

    c.node.addAnimation(showHideAnimation)
    c.showHideAnimation = showHideAnimation

proc destroy*(c: MapZoneCard, cb: proc() = nil) =
    c.onAction = nil
    c.hide() do():
        c.rootNode.removeFromParent()
        if not cb.isNil:
            cb()

template activateButton*(c: MapZoneCard, b: ButtonComponent, x: untyped): untyped =
    c.buttonUnlock.enabled = false
    c.buttonBuild.enabled = false
    c.buttonSpeedup.enabled = false
    c.buttonComplete.enabled = false
    c.buttonCollect.enabled = false
    c.buttonShadow.alpha = 0.4

    b.node.alpha = 1.0
    b.enabled = true
    b.animation = b.node.animationNamed("press")
    b.onAction do():
        if not c.onAction.isNil:
            c.onAction()
            c.onAction = nil

    x

proc new*(T: typedesc[MapZoneCard], style: MapZoneCardBgStyle, parent: Node): T =
    let node = newNodeWithResource("tiledmap/gui/ui2_0/map_zone_info_inner")
    result = T.new(node)

    let bg = newMapZoneCardBg(style)
    bg.parent.addChild(node)
    node.position = -bg.parent.position
    bg.node.anchor = bg.parent.position

    parent.addChild(bg.node)
    result.bg = bg

    result.isHidden = true