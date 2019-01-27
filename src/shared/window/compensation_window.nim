import json
import random
import strutils

import rod.rod_types
import rod.node
import rod.viewport
import rod.component
import rod.component.text_component
import rod.component.ui_component
import rod.component.ae_composition
import rod.utils.attributed_text

import nimx.matrixes
import nimx.button
import nimx.property_visitor
import nimx.animation
import nimx.formatted_text

import utils.helpers
import utils.console
import utils.falcon_analytics
import shared.localization_manager
import shared.window.window_component
import shared.window.button_component
import falconserver.map.building.builditem
import shared.window.window_manager
import shared.user

type CompensationWindow* = ref object of WindowComponent
    window: Node

proc initProgressListTexts(n:Node) =
    n.findNode("your_level").getComponent(Text).text = localizedString("COMPENSATION_LEVEL")
    n.findNode("you_spend").getComponent(Text).text = localizedString("COMPENSATION_SPEND")

method onInit*(tw: CompensationWindow) =
    tw.hasFade = false
    let win = newLocalizedNodeWithResource("common/gui/popups/precomps/compensation_new.json")
    tw.window = win
    tw.anchorNode.addChild(win)

    let tab_title = win.findNode("tab").findNode("title").getComponent(Text)
    tab_title.text = localizedString("COMPENSATION_TAB_TITLE")

    win.findNode("your_lost_progress").getComponent(Text).text = localizedString("COMPENSATION_LOST")
    win.findNode("your_new_progress").getComponent(Text).text = localizedString("COMPENSATION_NEW")

    win.findNode("progress_list_left").initProgressListTexts()
    win.findNode("progress_list_right").initProgressListTexts()

    let desc1_text = win.findNode("text_desc1").getComponent(Text)
    desc1_text.text = localizedString("COMPENSATION_DESC1")
    desc1_text.node.anchor = newVector3(500, 50, 0)
    desc1_text.boundingSize = newSize(1000, 170)
    desc1_text.horizontalAlignment = haCenter
    desc1_text.shadowRadius = 4.0

    let desc2_text = win.findNode("text_desc2").getComponent(Text)
    desc2_text.text = localizedString("COMPENSATION_DESC2")
    desc2_text.node.anchor = newVector3(200, 20, 0)
    desc2_text.boundingSize = newSize(400, 150)
    desc2_text.horizontalAlignment = haCenter
    # desc2_text.mText.processAttributedText()

    let btnGetReward = win.findNode("ltp_yellow_button_long")
    let bttn_title = btnGetReward.findNode("title").component(Text)
    bttn_title.text = localizedString("COMPENSATION_GET")
    bttn_title.shadowRadius = 4.0
    let btnreward = btnGetReward.component(ButtonComponent)#btnGetReward.createButtonComponent(newRect(5, 5, 490, 90))
    btnreward.onAction do():
        tw.closeButtonClick()

proc setupData*(w: CompensationWindow, data: JsonNode) =
    let oldLevel = data{"oldLvl"}.getInt()

    let leftColumnNode = w.window.findNode("progress_list_left")
    let rightColumnNode = w.window.findNode("progress_list_right")

    leftColumnNode.findNode("label_level").getComponent(Text).text = $oldLevel
    leftColumnNode.findNode("label_chips").getComponent(Text).text = formatThousands(data{"oldChips"}.getInt())
    leftColumnNode.findNode("label_bucks").getComponent(Text).text = formatThousands(data{"oldBucks"}.getInt())
    leftColumnNode.findNode("label_parts").getComponent(Text).text = formatThousands(data{"oldParts"}.getInt())


    rightColumnNode.findNode("label_level").getComponent(Text).text = $oldLevel
    rightColumnNode.findNode("label_chips").getComponent(Text).text = formatThousands(data{"newChips"}.getInt())
    rightColumnNode.findNode("label_bucks").getComponent(Text).text = formatThousands(data{"newBucks"}.getInt())
    rightColumnNode.findNode("label_parts").getComponent(Text).text = formatThousands(data{"newParts"}.getInt())


    #w.window.findNode("label_new_bucks").getComponent(Text).text = $data{"newBucks"}.getInt()

    var spend = "0 USD"
    if not data{"oldSpend"}.isNil:
        spend = $data{"oldSpend"}.getInt() & " USD"

    leftColumnNode.findNode("label_spend").getComponent(Text).text = spend
    rightColumnNode.findNode("label_spend").getComponent(Text).text = spend

    # if not data{"oldSpend"}.isNil:
    #     w.window.findNode("label_spend").getComponent(Text).text = $data{"oldSpend"}.getInt() & " USD"
    # else:
    #     w.window.findNode("label_spend").getComponent(Text).text = "0" & " USD"

    var userName = data{"userName"}.getStr()
    if userName.len() < 1:
        userName = "Player"
    w.window.findNode("text_desc1").getComponent(Text).text = localizedFormat("COMPENSATION_DESC1", userName)
    # sharedAnalytics().compensation_popup_show(oldLevel)

method hideStrategy*(tw: CompensationWindow): float =
    let showWinAnimCompos = tw.window.getComponent(AEComposition)
    let anim = showWinAnimCompos.play("show")
    anim.loopPattern = lpEndToStart

    return 0.9

method showStrategy*(w: CompensationWindow) =
    w.node.alpha = 1.0
    let showWinAnimCompos = w.window.getComponent(AEComposition)
    showWinAnimCompos.play("show")

registerComponent(CompensationWindow, "windows")

proc showCompensation(args: seq[string]): string =
    if not sharedConsole().isNil:
        echo "Show compensation window"
        let cw = sharedWindowManager().show(CompensationWindow)
        var data = newJObject()
        let user = currentUser()
        data["oldLvl"] = newJInt(user.level)
        data["oldChips"] = newJInt(user.chips)
        data["oldBucks"] = newJInt(user.bucks)
        data["oldParts"] = newJInt(user.parts)

        data["newChips"] = newJInt(user.chips*2.int)
        data["newBucks"] = newJInt(user.bucks + user.level*10.int)
        data["newParts"] = newJInt(user.parts + user.level*100.int)

        data["userName"] = newJString(user.name)

        cw.setupData(data)

registerConsoleComand(showCompensation, "showCompensation ()")
