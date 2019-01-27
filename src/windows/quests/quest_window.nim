import strutils
import node_proxy.proxy
import nimx/ [ matrixes, types, view, animation ]
import rod / [ node, component, viewport ]
import rod / component / [ text_component, ae_composition, clipping_rect_component, camera, particle_system ]
import utils / [ helpers, node_scroll, falcon_analytics, falcon_analytics_helpers, sound_manager ]
import quest_zone_panel
import quest / [ quests, quests_actions ]
import algorithm, times, json, preferences
import core.notification_center
import falconserver.map.building.builditem

import shared.window.window_component
import shared.window.button_component
import shared.window.window_manager
import shared.game_scene

import map / tiledmap_actions


const cardOffset = 10.0
const frontLightOffset = newVector3() #newVector3(40.0, 120.0)

nodeProxy QuestWindowProxy:
    buttonCloseNode Node {withName: "button_close"}
    questBarParent Node {withName: "quest_bar_parent"}
    tabTitle Text {onNode:"text_content_active"}:
        text = "Quests"

    buttonLeftNode Node {withName:"button_left"}
    buttonRightNode Node {withName:"button_right"}

    backLight Node {withName: "back_light"}:
        positionX = -10.0

    frontLight Node {withName: "front_light"}

    aeLight AEComposition {onNode: frontLight}

    aeComp AEComposition {onNode: node}
    closeButton ButtonComponent {onNodeAdd: buttonCloseNode}:
        bounds = newRect(0, 0, 100, 100)
        pressAnim = np.buttonCloseNode.animationNamed("press")

    leftButton ButtonComponent {onNodeAdd: buttonLeftNode}:
        bounds = newRect(0, 0, 100, 100)
        pressAnim = np.buttonLeftNode.animationNamed("press")

    rightButton ButtonComponent {onNodeAdd: buttonRightNode}:
        bounds = newRect(0, 0, 100, 100)
        pressAnim = np.buttonRightNode.animationNamed("press")

    gradientL Node {withName:"grad_l"}
    gradientR Node {withName:"grad_r"}

type QuestWindow* = ref object of WindowComponent
    proxy: QuestWindowProxy
    scrollNode: NodeScroll
    panels: seq[QuestZonePanel]
    fromSource*: int
    # onGetReward*:   proc(id: int)
    leadToZone*: Zone
    tabEnterTime: float
    ps: ParticleSystem

proc soundClick(qw: QuestWindow)=
    qw.anchorNode.sceneView.GameScene.soundManager.sendEvent("COMMON_GUI_CLICK")

proc onQuestAcion(qw: QuestWindow): proc(q: Quest)=
    result = proc(q: Quest)=
        case q.status:
        of QuestProgress.Ready:
            qw.soundClick()
            qw.proxy.node.sceneView.GameScene.dispatchAction(OpenQuestCardAction, newVariant(q))
            qw.closeButtonClick()

        of QuestProgress.InProgress:
            qw.soundClick()
            sharedAnalytics().quest_speedup_show(q.config.name, "panel")
            qw.proxy.node.sceneView.GameScene.dispatchAction(OpenQuestCardAction, newVariant(q))
            qw.closeButtonClick()

        of QuestProgress.Completed:
            qw.soundClick()
            qw.proxy.node.sceneView.GameScene.dispatchAction(ZoomToQuestAction, newVariant(q))
            qw.proxy.node.sceneView.GameScene.dispatchAction(TryToGetRewardsQuestAction, newVariant(q))
            qw.closeButtonClick()

        of QuestProgress.GoalAchieved:
            qw.soundClick()
            sharedAnalytics().quest_complete(q.config.name, "panel")
            qw.proxy.node.sceneView.GameScene.dispatchAction(ZoomToQuestAction, newVariant(q))
            qw.proxy.node.sceneView.GameScene.dispatchAction(TryToCompleteQuestAction, newVariant(q))
            qw.closeButtonClick()

        else: discard

proc onQuestStateChanged(qw: QuestWindow): proc(p: QuestZonePanel, z: Zone)=
    let w = qw
    result = proc(p: QuestZonePanel, z: Zone)=
        let i = qw.panels.find(p)
        if i >= 0:
            let index = qw.scrollNode.indexOf(p.node)

            var np = createQuestBarForZone(z)
            np.onClick = qw.onQuestAcion()
            np.onQuestStateChanged = qw.onQuestStateChanged()
            np.node.position = p.node.position

            qw.panels[i] = np
            qw.scrollNode.removeChild(p.node)
            qw.scrollNode.insertChild(np.node, index)

proc onPlayClick(zoneName: string)=
    currentNotificationCenter().postNotification("MapPlaySlotClicked", newVariant(parseEnum[BuildingId](zoneName)))

proc onLeadToZone(qw: QuestWindow): proc(z: Zone)=
    result = proc(z: Zone)=
        for p in qw.panels:
            if p.zone == z:
                let i = qw.scrollNode.indexOf(p.node)
                qw.scrollNode.scrollToIndex(i)
                qw.proxy.frontLight.enabled = true
                qw.proxy.backLight.enabled = true
                qw.ps.isPlayed = true
                break

method onInit*(qw: QuestWindow) =
    qw.proxy = new(QuestWindowProxy, newLocalizedNodeWithResource("tiledmap/gui/ui2_0/map_quest_menu"))
    qw.anchorNode.addChild(qw.proxy.node)
    
    let zones = getQuestZones()
    let width = zones.len * 455 + 10
    let bounds = qw.node.sceneView.bounds
    let vp = qw.node.sceneView.camera.viewportSize
    let coof = clamp((bounds.width / bounds.height) / (vp.width / vp.height), 1.0, 4.0)

    let w = 1920 * coof
    qw.scrollNode = createNodeScroll(newRect((1920 - w) * 0.5, -100, w, 810), qw.proxy.questBarParent)
    qw.scrollNode.nodeSize = newSize(455.0, 795.0)
    qw.scrollNode.scrollDirection = NodeScrollDirection.horizontal
    qw.scrollNode.setClippingEnabled(false)
    qw.scrollNode.notDrawInvisible = true

    qw.scrollNode.contentOffset = newVector3(722.5 * coof)

    qw.panels = @[]
    qw.proxy.gradientL.positionX = qw.proxy.gradientL.positionX + ((1920 - w) * 0.5)
    qw.proxy.gradientR.positionX = qw.proxy.gradientR.positionX - ((1920 - w) * 0.5)

    qw.proxy.buttonLeftNode.positionX = qw.proxy.buttonLeftNode.positionX + ((1920 - w) * 0.5)
    qw.proxy.buttonRightNode.positionX = qw.proxy.buttonRightNode.positionX - ((1920 - w) * 0.5)

    qw.scrollNode.contentBackNode.addChild(qw.proxy.backLight)
    qw.scrollNode.contentFrontNode.addChild(qw.proxy.frontLight)

    for i, zone in zones:
        let p = createQuestBarForZone(zone)
        p.onClick = qw.onQuestAcion()
        p.onQuestStateChanged = qw.onQuestStateChanged()
        p.onLeadToZone = qw.onLeadToZone()
        let zName = zone.name
        p.onPlayClick = proc() = onPlayClick(zName)
        qw.panels.add p

    qw.panels.sort(proc(a, b: QuestZonePanel): int=
        result = cmp(a.priority, b.priority),
        Descending
    )

    for i, p in qw.panels:
        let qb = p.node
        qb.positionX = cardOffset + (i * 455).float
        qw.scrollNode.addChild(qb)

    qw.scrollNode.looped = true
    qw.scrollNode.pading = true

    var arrowPressed = false

    let particle = newNodeWithResource("common/gui/popups/precomps/lightup_prt")
    qw.ps = particle.getComponent(ParticleSystem)
    qw.proxy.frontLight.addChild(particle)
    particle.position = newVector3(224.0, 840.0)

    qw.scrollNode.onActionStart = proc()=
        qw.proxy.frontLight.enabled = false
        qw.proxy.backLight.enabled = false
        qw.ps.isPlayed = false

    qw.scrollNode.onActionEnd = proc()=
        qw.proxy.frontLight.enabled = arrowPressed
        qw.proxy.backLight.enabled = arrowPressed
        qw.ps.isPlayed = arrowPressed
        arrowPressed = false

    qw.proxy.closeButton.onAction do():
        qw.closeButtonClick()

    qw.proxy.leftButton.onAction do():
        qw.scrollNode.moveLeft()
        arrowPressed = true

    qw.proxy.rightButton.onAction do():
        qw.scrollNode.moveRight()
        arrowPressed = true
        # qw.proxy.frontLight.enabled = true
        # qw.proxy.backLight.enabled = true

proc getCheapestPrice(qw: QuestWindow): int =
    let qm = sharedQuestManager()

    for quest in qm.activeStories():
        if quest.status == QuestProgress.Ready:
            if quest.config.price < result or result == 0:
                result = quest.config.price

proc sendOpenCloseEvent(qw: QuestWindow, open: bool) =
    let qm = sharedQuestManager()
    let name = qw.anchorNode.sceneView.name
    let activeQuests = qm.uncompletedQuests().len
    let questRewards = qm.complitedQuests().len
    let exitTime = epochTime()
    let stayTime = (exitTime - qw.tabEnterTime).int
    let hasSign = sharedPreferences(){"hasGuiQuestSign"}.getBool()

    if open:
        sharedAnalytics().wnd_quests_open(name, activeQuests, questRewards, qw.getCheapestPrice(), hasSign, qw.fromSource)
    else:
        sharedAnalytics().wnd_quests_close(stayTime, activeQuests, questRewards, qw.getCheapestPrice(), hasSign, false)

method hideStrategy*(qw: QuestWindow): float =
    let a = qw.proxy.aeComp.play("out")
    result = a.loopDuration
    qw.sendOpenCloseEvent(true)

method showStrategy*(qw: QuestWindow) =
    qw.node.alpha = 1.0
    qw.proxy.aeComp.play("in", @["back_light","front_light"])

    let idle = newAnimation()
    idle.loopDuration = 2.0
    idle.addLoopProgressHandler(1.0, false) do():
        qw.proxy.aeLight.play("play")

    qw.proxy.node.addAnimation(idle)
    qw.tabEnterTime = epochTime()
    qw.sendOpenCloseEvent(true)

method onShowed*(qw: QuestWindow)=
    if not qw.leadToZone.isNil:
        for p in qw.panels:
            if p.zone == qw.leadToZone:
                let i = qw.scrollNode.indexOf(p.node)
                qw.scrollNode.scrollToIndex(i)
                break
        qw.leadToZone = nil
    else:
        qw.onLeadToZone()(qw.panels[0].zone)

registerComponent(QuestWindow, "windows")
