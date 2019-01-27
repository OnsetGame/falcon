import macros, logging, tables

proc appearsAux(head, body: NimNode): NimNode=
    let baseStateTyp = ident("BaseFlowState")

    let typ = head

    let oname = newNimNode(nnkDotExpr).add(ident("o")).add(ident("name"))

    var xpr = newNimNode(nnkInfix)

    # echo "bodykind ", body.kind, " treerepr ", treeRepr(body)

    if body.kind == nnkBracket:
        var names = newNimNode(nnkBracket)

        for ch in body:
            names.add(newStrLitNode($ch))

        xpr.add(
            ident("in")
        )
        xpr.add(oname)
        xpr.add(names)

    else:
        xpr.add(
            ident("==")
        )
        xpr.add(oname)
        xpr.add(
            newStrLitNode($body)
        )

    var procBody = newNimNode(nnkStmtList)
    var retSt = newNimNode(nnkAsgn)

    retSt.add(ident("result")).add(xpr)

    procBody.add(retSt)

    var procDef = newProc(
        newNimNode(nnkPostfix).add(ident("*"), ident("appearsOn")),
        [
            ident("bool"),
            newNimNode(nnkIdentDefs).add(ident("s")).add(typ).add(newNimNode(nnkEmpty)),
            newNimNode(nnkIdentDefs).add(ident("o")).add(baseStateTyp).add(newNimNode(nnkEmpty))
        ],
        procBody,
        nnkMethodDef
        )

    # echo "\n", repr(procDef)
    result = procDef

macro appears*(head, body: untyped): untyped=
    result = appearsAux(head, body)

macro awake*(head, body: untyped): untyped=
    let typ = ident($head)
    var procDef = newProc(
        newNimNode(nnkPostfix).add(ident("*"), ident("wakeUp")),
        [
            newNimNode(nnkEmpty),
            newNimNode(nnkIdentDefs).add(ident("state")).add(typ).add(newNimNode(nnkEmpty))
        ],
        body,
        nnkMethodDef
        )

    # echo "\n", repr(procDef)
    result = procDef

type AppearsRelation = tuple
    child: NimNode
    parents: NimNode

proc extractRelations(root: NimNode, stmtList: NimNode): Table[string, AppearsRelation]=
    var r = initTable[string, AppearsRelation]()

    for ch in stmtList.children:
        let chIdent = ch[1]
        var rel = r.getOrDefault($chIdent)
        if rel.parents.isNil:
            rel.child = chIdent
            rel.parents = newNimNode(nnkBracket)
        rel.parents.add(root)

        r[$chIdent] = rel

        if ch.len > 2 and ch[2].kind == nnkStmtList:
            var chrel = chIdent.extractRelations(ch[2])
            for k, v in chrel:
                var rel = r.getOrDefault(k)
                if rel.parents.isNil:
                    rel = v
                else:
                    for ch in v.parents:
                        if rel.parents.find(ch) == -1:
                            rel.parents.add(ch)
                r[k] = rel
    result = r

macro stateMachine*(head, body: untyped): untyped =
    var relations = head.extractRelations(body)
    result = newNimNode(nnkStmtList)

    for k, v in relations:
        var r = appearsAux(v.child, v.parents)
        result.add(r)

    # echo "stateMachine ", $head, " :\n",  repr(result)

template dummySlotAwake*(head: untyped): untyped =
    method wakeUp*(state: head)=
        let hasReact = state.slot.react(state)
        if not hasReact:
            weakPop(state)

template dummyAwake*(head: untyped): untyped =
    method wakeUp*(state: head)=
        weakPop(state)
