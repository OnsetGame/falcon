import macros
import rod.node
# import rod.component
import rod.viewport
import rod.rod_types
import rod.component.text_component

template declProxyType(typ): untyped =
    type typ* = ref object of RootObj

template errorInvalidProxy(node): untyped =
    error "Invalid proxy kind " & $node.kind & " repr " & treeRepr(node)

macro nodeProxy*(head, body: untyped): untyped =
    # echo "head ", treeRepr(head)
    # echo "body ", treeRepr(body)

    var npType = head # todo iheritance

    var typeDesc = getAst(declProxyType(npType))
    
    echo "typeDesc ", treeRepr(typeDesc)

    result = newNimNode(nnkStmtList)
    result.add typeDesc

    var recList = newNimNode(nnkRecList)
    # var creatorDef = newNimNode(nnkProcDef)

    for node in body.children:
        case node.kind:
        of nnkCommand:
            echo "nnkCommand skip"
            # echo "body_component kind ", node.kind, " repr ", treeRepr(node)
        of nnkCall:
            if node.len > 1 and node[1].kind == nnkStmtList and node[0].kind == nnkIdent:
                echo "body_call kind ", node.kind, " repr ", treeRepr(node)
                if cmp($node[0].ident, "creator") == 0:
                    echo "creator found! generating create proc ... "

                let procName = newNimNode(nnkPostfix).add(newIdentNode("*")).add(newIdentNode("create"))
                var procArg = newIdentDefs(newIdentNode("np"), newNimNode(nnkVarTy).add(npType))
                # echo " create ", creatorArgName
                var creatorDef = newProc(
                    procName,
                    [newEmptyNode(), procArg]
                )
                # var bodyNode = newNimNode(nnkStmtList)
                # let discadef = newNimNode(nnkDiscardStmt).add(newNimNode(nnkEmpty)).add(newNimNode(nnkEmpty))
                # bodyNode.add(discadef)
                # creatorDef.body.add(discadef)
                var cb = node[1][0]
                var pc = quote do:
                    np.new()
                    var node = `cb`()
                    echo "create node ", node.name

                # echo "treerepr ", treeRepr(pc)

                creatorDef.body.add(pc)
                # echo "creator proc ", treeRepr(creatorDef)
                # echo "creator repr ", repr(creatorDef)
                result.add(newNimNode(nnkEmpty))
                result.add(creatorDef)
                echo "result ast \n", treeRepr(result)
                echo "result \n", repr(result)
            else:
                # error "Invalid proxy " & treeRepr(node)
                errorInvalidProxy(node)
        else:
            errorInvalidProxy(node)
            # error "Invalid proxy " & treeRepr(node)

    # result.add(creatorDef)

when isMainModule:

    proc nodeForTest(): Node =
        result = newNode("test")
        discard result.newChild("child1")
        discard result.newChild("child2").newChild("somenode")

    proc getSomeEnabled(): bool = true

    nodeProxy TestProxy:
        creator: nodeForTest
        # composition: "lalala.json"

        someNode Node:
            name "somenode"
            enabled = getSomeEnabled()

        someComponent component Text:
            fromNode = somenode
            text = "some mega text"

    var tproxy: TestProxy # = new(TestProxy)
    tproxy.create()
    echo "testProxy created ", not tproxy.isNil


