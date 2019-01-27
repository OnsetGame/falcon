when defined(windows) or defined(macosx):
    import strutils, tables, times, json, os, logging

    import nimx.view
    import nimx.text_field
    import nimx.matrixes
    import nimx.image
    import nimx.button
    import nimx.font
    import nimx.linear_layout
    import nimx.property_visitor
    import nimx.numeric_text_field
    import nimx.slider
    import nimx.animation
    import nimx.popup_button

    import nimx.property_editors.standard_editors
    import rod.property_editors.propedit_registry
    import rod.node
    import rod.viewport
    import rod.quaternion
    import rod.component
    import rod.component.mesh_component
    import rod.component.ae_composition
    import rod.tools.serializer
    import rod.utils.json_serializer

    import variant

    import narrative / narrative
    import os_files.dialog

    when defined(js):
        from dom import alert
    elif not defined(android) and not defined(ios) and not defined(emscripten):
        import os_files.dialog

    template toStr(v: SomeReal, precision: uint): string = formatFloat(v, ffDecimal, precision)
    template toStr(v: SomeInteger): string = $v

    template fromStr(v: string, t: var SomeReal) = t = v.parseFloat()
    template fromStr(v: string, t: var SomeInteger) = t = v.parseInt()

    proc serializeCustom*(n: Node, s: Serializer): JsonNode =
        result = newJObject()
        result.add("name", s.getValue(n.name))
        result.add("translation", s.getValue(n.position))
        result.add("scale", s.getValue(n.scale))
        result.add("rotation", s.getValue(n.rotation))
        result.add("anchor", s.getValue(n.anchor))
        result.add("alpha", s.getValue(n.alpha))
        result.add("layer", s.getValue(n.layer))
        result.add("affectsChildren", s.getValue(n.affectsChildren))
        result.add("enabled", s.getValue(n.enabled))


        let narrative = n.getComponent(Narrative)
        if not narrative.isNil:
            var componentsNode = newJArray()
            result.add("components", componentsNode)
            var jcomp: JsonNode
            jcomp = narrative.serialize(s)

            if not jcomp.isNil:
                jcomp.add("_c", %narrative.className())
                componentsNode.add(jcomp)

    proc nodeToJson(n: Node, path: string): JsonNode =
        let s = Serializer.new()
        s.url = "file://" & path
        result = n.serializeCustom(s)

    proc saveNode(selectedNode: Node) =
        var di: DialogInfo
        di.folder = getAppDir()
        di.extension = "jcomp"
        di.kind = dkSaveFile
        # di.filters = @[(name:"JCOMP", ext:"*.jcomp")]
        di.title = "Save composition"
        let path = di.show()
        if path.len != 0:
            try:
                let sData = nodeToJson(selectedNode, path)
                writeFile(path, sData.pretty())
            except:
                error "Exception caught: ", getCurrentExceptionMsg()
                error "stack trace: ", getCurrentException().getStackTrace()

    proc newNarrativePropertyView(setter: proc(s: Narrative), getter: proc(): Narrative): PropertyEditorView =
        var height = 0.0
        var narrative = getter()
        result = PropertyEditorView.new(newRect(0.0, 0.0, 208.0, editorRowHeight))
        let r = result

        let saveButton = Button.new(newRect(0, 0, 100, editorRowHeight))
        saveButton.title = "Save"
        r.addSubview(saveButton)
        saveButton.onAction do():
            saveNode(narrative.node)

    proc newNarrativeFramePropertyView(setter: proc(s: seq[NarrativeFrame]), getter: proc(): seq[NarrativeFrame]): PropertyEditorView =
        var height = 0.0
        var frames = getter()
        let h = float(frames.len * 12 * editorRowHeight) + editorRowHeight
        result = PropertyEditorView.new(newRect(0.0, 0.0, 208.0, h))
        let r = result

        proc onFrameChanged(i: int, frame: NarrativeFrame) =
            frames[i] = frame
            setter(frames)

        for i, f in frames:
            closureScope:
                let index = i
                var frame = frames[index]
                let indexField = newLabel(newRect(0, height, 200, editorRowHeight))
                indexField.font = editorFont()
                indexField.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
                indexField.text = $index
                r.addSubview(indexField)

                var offset = 1.0
                discard newLabel(r, newPoint(-100, offset*editorRowHeight + height), newSize(100, editorRowHeight), "right")
                let rightCB = newCheckbox(newRect(0, offset*editorRowHeight + height, editorRowHeight, editorRowHeight))
                rightCB.value = if frame.right: 1 else: 0
                r.addSubview(rightCB)
                rightCB.onAction do():
                    frame.right = rightCB.boolValue
                    onFrameChanged(index, frame)

                offset+=1.0
                discard newLabel(r, newPoint(-100, offset*editorRowHeight + height), newSize(100, editorRowHeight), "bottom")
                let bottomCB = newCheckbox(newRect(0, offset*editorRowHeight + height, editorRowHeight, editorRowHeight))
                bottomCB.value = if frame.bottom: 1 else: 0
                r.addSubview(bottomCB)
                bottomCB.onAction do():
                    frame.bottom = bottomCB.boolValue
                    onFrameChanged(index, frame)

                offset+=1.0
                discard newLabel(r, newPoint(-100, offset*editorRowHeight + height), newSize(100, editorRowHeight), "needZoom")
                let zoomCB = newCheckbox(newRect(0, offset*editorRowHeight + height, editorRowHeight, editorRowHeight))
                zoomCB.value = if frame.needZoom: 1 else: 0
                r.addSubview(zoomCB)
                zoomCB.onAction do():
                    frame.needZoom = zoomCB.boolValue
                    onFrameChanged(index, frame)

                offset+=1.0
                discard newLabel(r, newPoint(-100, offset*editorRowHeight + height), newSize(100, editorRowHeight), "withoutAction")
                let withoutActionCB = newCheckbox(newRect(0, offset*editorRowHeight + height, editorRowHeight, editorRowHeight))
                withoutActionCB.value = if frame.withoutAction: 1 else: 0
                r.addSubview(withoutActionCB)
                withoutActionCB.onAction do():
                    frame.withoutAction = withoutActionCB.boolValue
                    onFrameChanged(index, frame)

                offset+=1.0
                discard newLabel(r, newPoint(-100, offset*editorRowHeight + height), newSize(50, editorRowHeight), "showDelay")
                let showField = newNumericTextField(newRect(0.Coord, offset*editorRowHeight + height, 100, editorRowHeight))
                showField.font = editorFont()
                showField.text = $frame.showDelay
                r.addSubview(showField)
                showField.onAction do():
                    try: frame.showDelay = showField.text.parseFloat()
                    except: frame.showDelay = 0.0
                    onFrameChanged(index, frame)

                offset+=1.0
                discard newLabel(r, newPoint(-100, offset*editorRowHeight + height), newSize(100, editorRowHeight), "text")
                let textField = newTextField(newRect(0, offset*editorRowHeight + height, 200, editorRowHeight))
                textField.font = editorFont()
                textField.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
                textField.text = frame.text
                r.addSubview(textField)
                textField.onAction do():
                    frame.text = textField.text
                    onFrameChanged(index, frame)


                offset+=1.0
                discard newLabel(r, newPoint(-100, offset*editorRowHeight + height), newSize(100, editorRowHeight), "secondText")
                let stextField = newTextField(newRect(0, offset*editorRowHeight + height, 200, editorRowHeight))
                stextField.font = editorFont()
                stextField.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
                stextField.text = frame.secondText
                r.addSubview(stextField)
                stextField.onAction do():
                    frame.secondText = stextField.text
                    onFrameChanged(index, frame)

                offset+=1.0
                discard newLabel(r, newPoint(-100, offset*editorRowHeight + height), newSize(50, editorRowHeight), "body")
                let bodyField = newNumericTextField(newRect(0.Coord, offset*editorRowHeight + height, 100, editorRowHeight))
                bodyField.font = editorFont()
                bodyField.text = $frame.characterBody
                r.addSubview(bodyField)
                bodyField.onAction do():
                    try: frame.characterBody = bodyField.text.parseInt()
                    except: frame.characterBody = 0
                    onFrameChanged(index, frame)

                offset+=1.0
                discard newLabel(r, newPoint(-100, offset*editorRowHeight + height), newSize(50, editorRowHeight), "head")
                let headField = newNumericTextField(newRect(0.Coord, offset*editorRowHeight + height, 100, editorRowHeight))
                headField.font = editorFont()
                headField.text = $frame.characterHead
                r.addSubview(headField)
                headField.onAction do():
                    try: frame.characterHead = headField.text.parseInt()
                    except: frame.characterHead = 0
                    onFrameChanged(index, frame)

                offset+=1.0
                discard newLabel(r, newPoint(-100, offset*editorRowHeight + height), newSize(100, editorRowHeight), "target")
                let targetField = newTextField(newRect(0.Coord, offset*editorRowHeight + height, 200, editorRowHeight))
                targetField.font = editorFont()
                targetField.text = frame.targetName
                r.addSubview(targetField)
                targetField.onAction do():
                    frame.targetName = targetField.text
                    onFrameChanged(index, frame)

                # enumerator ....
                var possibleValues = initTable[string, int]()
                var enumItems = newSeq[string]()
                for i in low(ArrowType) .. high(ArrowType):
                    possibleValues[$i] = ord(i)
                for k, v in possibleValues:
                    enumItems.add(k)

                var startVal = 0
                for i, v in enumItems:
                    if possibleValues[v] == ord(frame.arrowType):
                        startVal = i
                        break

                offset+=1.0
                discard newLabel(r, newPoint(-100, offset*editorRowHeight + height), newSize(100, editorRowHeight), "arrowType")
                var enumChooser = newPopupButton(r, newPoint(0.Coord, offset*editorRowHeight + height), newSize(208, editorRowHeight), enumItems, startVal)
                enumChooser.autoresizingMask = {afFlexibleWidth, afFlexibleMaxY}
                enumChooser.onAction do():
                    frame.arrowType = ArrowType(possibleValues[enumChooser.selectedItem()])
                    onFrameChanged(index, frame)

                offset+=1.0
                height += offset*editorRowHeight

        let addButton = Button.new(newRect(0, height, editorRowHeight, editorRowHeight))
        addButton.title = "+"
        r.addSubview(addButton)
        addButton.onAction do():
            var fr: NarrativeFrame
            if frames.isNil:
                frames = newSeq[NarrativeFrame]()
            frames.add(fr)
            setter(frames)
            if not r.changeInspector.isNil:
                r.changeInspector()


    registerPropertyEditor(newNarrativeFramePropertyView)
    registerPropertyEditor(newNarrativePropertyView)
