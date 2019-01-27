import json, logging, strutils

import nimx / [ view, button, matrixes, text_field, panel_view, view_event_handling, notification_center, table_view, scroll_view ]
import rod / [ rod_types, viewport, node, component ]
import rod / component / [ ui_component ]
import utils / [ console, game_state, falcon_analytics ]

import shared / [ game_scene ]
import core.net.server
import falconserver.map.building.builditem
import falconserver.quest.quest_types
import quest.quest_helpers

const
    CB_MAIN_TITLE       = "Cheats"
    COMMON_CHEAT_KEY    = "common"

type
    CheatsView* = ref object of View
        cheatsButton:   Button
        config:         JsonNode
        isMenuOpened:   bool
        cheatsList:     View
        posX:           Coord
        posY:           Coord
        cheat_width:    Coord
        cheat_height:   Coord
        btn_size:       Coord
        extraFields*:   JsonNode

var custom_Spin_Cheat = ["1,1,1,1,1", "1,1,1,1,1", "1,1,1,1,1"]

proc createCheatsButton(cv: CheatsView, title: string, callback: proc()): Button =
    result = newButton(newRect(cv.posX, cv.posY, cv.btn_size, cv.btn_size))
    result.title = title
    result.onAction do():
        callback()

proc createCheatsView*(config: JsonNode, frame: Rect): CheatsView =
    result.new()
    result.init(frame)

    result.posX = 10
    result.posY = frame.height/7
    result.cheat_width = 200.0
    result.cheat_height = frame.height/20
    result.btn_size = frame.width/21

    result.autoresizingMask = { afFlexibleHeight, afFlexibleWidth }
    result.config = config
    result.isMenuOpened = false

proc verifyCheatField(field: seq[string]): bool =

    if field.len != 15: return false

    for snum in field:
        var n: int
        try: n = parseInt(snum)
        except: return false

        if n >= 0 and n <= 12:
            discard
        else:
            return false

    result = true

import preferences

proc showCheats*(cv: CheatsView, cheatsKey: varargs[string])=
    if cv.config.isNil: return

    proc parseCheats(jn: JsonNode, arr: var seq[JsonNode])=
        if jn.kind == JArray:
            for ch in jn:
                arr.add(ch)
        else:
            for k, v in jn:
                for ch in v:
                    arr.add(ch)

    var cheatsConf = newSeq[JsonNode]()

    let common_cheats = cv.config{COMMON_CHEAT_KEY}
    var machine : string

    if not common_cheats.isNil:
        common_cheats.parseCheats(cheatsConf)

    if cheatsKey.len > 0:
        let other_cheats = cv.config{@cheatsKey}
        if not other_cheats.isNil and other_cheats.kind != JNull:
            machine = cheatsKey[1]
            other_cheats.parseCheats(cheatsConf)

            var customCheat = newJObject()
            customCheat["request"] = cheatsConf[cheatsConf.len - 1]["request"]
            customCheat["name"] = %"spin"
            customCheat["value"] = %"custom"
            cheatsConf.add(customCheat)

    proc createTable() : View =
        var cheatsPerRow = min(cheatsConf.len div 2, 10)
        let numberOfCols = max(cheatsConf.len div cheatsPerRow, 1)
        var numberOfRows = cheatsConf.len div numberOfCols
        numberOfRows += cheatsConf.len mod numberOfCols

        let height = numberOfRows.float * cv.cheat_height
        let tableView = newTableView(newRect(cv.btn_size + cv.posX, cv.posY , cv.cheat_width * numberOfCols.float, height.Coord))
        tableView.autoresizingMask = { afFlexibleMaxX, afFlexibleHeight }
        tableView.numberOfRows = proc: int = numberOfRows
        tableView.defaultColWidth = cv.cheat_width
        tableView.numberOfColumns = numberOfCols
        tableView.heightOfRow = proc (row:int): Coord = cv.cheat_height

        tableView.createCell = proc (): TableViewCell =
            result = newTableViewCell(newButton(newRect(0, 0, tableView.defaultColWidth, cv.cheat_height)))

        tableView.configureCell = proc (c: TableViewCell) =
            let confidx = c.row + (numberOfRows * c.col)
            if confidx >= cheatsConf.len:
                return

            let cheat_name = $cheatsConf[confidx]["name"].str
            var val = cheatsConf[confidx]["value"]

            var valstr = if val.kind == Jstring : val.str
                                            else: $val

            if "chips" in cheat_name:
                c.subviews[0].backgroundColor = newColor(0.8, 0.3, 0.3, 0.2)
            elif "parts" in cheat_name:
                c.subviews[0].backgroundColor = newColor(0.2, 0.2, 0.8, 0.2)
            elif "bucks" in cheat_name:
                c.subviews[0].backgroundColor = newColor(0.2, 0.8, 0.2, 0.2)
            elif "tutorial" in cheat_name:
                c.subviews[0].backgroundColor = newColor(0.4, 0.0, 0.3, 0.2)
            elif "spin" in cheat_name:
                c.subviews[0].backgroundColor = newColor(0.0, 0.7, 0.5, 0.2)

            Button(c.subviews[0]).title = cheat_name & "_" & valstr
            if machine.len == 0 or confidx < cheatsConf.len - 1:
                Button(c.subviews[0]).onAction do():
                    tableView.removeFromSuperview()
                    cv.isMenuOpened = false
                    let index = confidx
                    info "Cheat clicked ", cheatsConf[index]

                    if valstr == "Progress":
                        removeStatesByTag(ANALYTICS_TAG)
                        removeStatesByTag(DEFAULT_TAG)
                    var body = %*{"machine": machine, "value": valstr}
                    if not cv.extraFields.isNil:
                        for k,val in cv.extraFields:
                            body[k] = val
                    sharedServer().sendCheatRequest( cheatsConf[index]["request"].str, body, proc(jn: JsonNode)=
                        sharedNotificationCenter().postNotification( cheat_name, newVariant(jn))
                        )
            else:
                Button(c.subviews[0]).onAction do():
                    tableView.removeFromSuperview()
                    cv.isMenuOpened = false
                    info "Cheat clicked ", "custom"

                    var panel = new(PanelView)
                    panel.init( newRect(cv.btn_size * 2.0 + cv.posX, cv.posY, cv.cheat_width * 2.0, cv.cheat_height * 4.0) )

                    var btn = newButton( newRect(cv.cheat_width * 0.5, cv.cheat_height * 3 + 10, cv.cheat_width, cv.cheat_height - 5))
                    btn.title = "Enter field!"

                    var textFields = newSeq[TextField]()

                    for i in 0..2:
                        var tf = newTextField(newRect(5, 5 + i.Coord * cv.cheat_height, cv.cheat_width - 10, cv.cheat_height))
                        tf.text = custom_Spin_Cheat[i]
                        tf.continuous = true
                        panel.addSubview(tf)
                        textFields.add(tf)

                    proc collectFields(): seq[string]=
                        result = @[]
                        for tf in textFields:
                            result.add(tf.text.split(','))

                    proc verifyFields(tf: int)=
                        let arr = collectFields()

                        if verifyCheatField(arr) and textFields.len > tf and textFields[tf].text.split(',').len == 5:
                            custom_Spin_Cheat[tf] = textFields[tf].text
                            btn.enabled = true
                            btn.title = "Send"
                        else:
                            btn.title = "Incorrect"
                            btn.enabled = false

                    textFields[0].onAction do():
                        verifyFields(0)

                    textFields[1].onAction do():
                        verifyFields(1)

                    textFields[2].onAction do():
                        verifyFields(2)

                    panel.addSubview(btn)
                    cv.addSubview(panel)

                    btn.enabled = verifyCheatField(collectFields())

                    btn.onAction do():
                        panel.removeFromSuperview()
                        let index = confidx
                        let arr = collectFields()
                        var i_arr = newSeq[int]()

                        for nsum in arr: i_arr.add( nsum.parseInt() )

                        info "Cheat clicked custom "
                        var body = %*{"machine": machine, "value": valstr, "cs": %i_arr}
                        if not cv.extraFields.isNil:
                            for k,val in cv.extraFields:
                                body[k] = val
                        sharedServer().sendCheatRequest( cheatsConf[index]["request"].str, body, proc(jn: JsonNode)=
                            sharedNotificationCenter().postNotification( cheat_name, newVariant(jn))
                            )


        tableView.reloadData()
        result = tableView

    cv.cheatsButton = cv.createCheatsButton(CB_MAIN_TITLE, proc() =
        cv.isMenuOpened = not cv.isMenuOpened
        if cv.isMenuOpened:
            cv.cheatsList = createTable()
            cv.addSubview(cv.cheatsList)
        elif not cv.cheatsList.isNil:
            cv.cheatsList.removeFromSuperview()
            cv.cheatsList = nil
    )
    cv.addSubview(cv.cheatsButton)

    when defined(android) or defined(ios):
        let consoleBttn= newButton(newRect(cv.posX, cv.posY + cv.btn_size + 10, 60, 40))
        consoleBttn.title = "console"
        consoleBttn.onAction do():
            showConsole(consoleBttn.superview)

        cv.addSubview(consoleBttn)

proc sendCheatCommand*(cmd: string, machine: string)=
    var body : JsonNode
    if cmd == "custom":
        var ci = newSeq[int]()
        for cs in custom_Spin_Cheat:
            var spCs = cs.split(',')
            for stri in spCs:
                ci.add(parseInt(stri))

        body = %*{"machine": machine, "value": cmd, "cs": %ci}
    else:
        body = %*{"machine": machine, "value": cmd}

    sharedServer().sendCheatRequest("/cheats/slot", body, proc(jn: JsonNode)=
        sharedNotificationCenter().postNotification("spin", newVariant(jn))
        )


type GameSceneWithCheats* = ref object of GameScene
    cheatsView*: CheatsView

method onKeyDown*(gs: GameSceneWithCheats, e: var Event): bool =
    result = procCall gs.GameScene.onKeyDown(e)

    if not result and e.modifiers.anyOsModifier():
        result = true
        case e.keyCode:
        of VirtualKey.Z:
            if gs.cheatsView.superview.isNil:
                gs.addSubview(gs.cheatsView)
            else:
                gs.cheatsView.removeFromSuperview()
        of VirtualKey.X:
            var guiNode = gs.rootNode.findNode("GUI")
            if guiNode.isNil:
                guiNode = gs.rootNode.findNode("gui_parent")

            if not guiNode.isNil:
                guiNode.enabled = not guiNode.enabled
        else:
            result = false
