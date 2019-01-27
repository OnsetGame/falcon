import rod / [ node, component ]
import rod.component.sprite
import nimx / [ matrixes, types, animation ]
import utils / [ win_line, helpers ]

let positions = @[
    @[newVector3(340.0, 480.0), newVector3(1590.0, 480.0)],
    @[newVector3(340.0, 280.0), newVector3(1590.0, 280.0)],
    @[newVector3(340.0, 710.0), newVector3(1590.0, 710.0)],
    @[newVector3(260.0, 255.0), newVector3(515.0, 225.0), newVector3(985.0, 800.0), newVector3(1450.0, 225.0), newVector3(1585.0, 255.0)],
    @[newVector3(300.0, 760.0), newVector3(490.0, 765.0), newVector3(990.0, 185.0), newVector3(1450.0, 765.0), newVector3(1630.0, 760.0)],
    @[newVector3(310.0, 480.0), newVector3(465.0, 535.0), newVector3(725.0, 180.0), newVector3(1245.0, 830.0), newVector3(1450.0, 430.0), newVector3(1600.0, 480.0)],
    @[newVector3(350.0, 480.0), newVector3(530.0, 400.0), newVector3(725.0, 840.0), newVector3(1245.0, 140.0), newVector3(1450.0, 605.0), newVector3(1600.0, 480.0)],
    @[newVector3(340.0, 255.0), newVector3(785.0, 255.0), newVector3(1180.0, 740.0), newVector3(1580.0, 740.0)],
    @[newVector3(340.0, 720.0), newVector3(785.0, 720.0), newVector3(1150.0, 220.0), newVector3(1580.0, 220.0)],
    @[newVector3(340.0, 250.0), newVector3(515.0, 250.0), newVector3(750.0, 610.0), newVector3(970.0, 170.0), newVector3(1240.0, 610.0), newVector3(1450.0, 250.0), newVector3(1630.0, 250.0)],
    @[newVector3(340.0, 720.0), newVector3(515.0, 720.0), newVector3(750.0, 400.0), newVector3(970.0, 830.0), newVector3(1240.0, 400.0), newVector3(1450.0, 720.0), newVector3(1630.0, 720.0)],
    @[newVector3(300.0, 500.0), newVector3(470.0, 540.0), newVector3(690.0, 240.0), newVector3(1290.0, 240.0), newVector3(1420.0, 540.0), newVector3(1590.0, 500.0)],
    @[newVector3(270.0, 465.0), newVector3(460.0, 445.0), newVector3(765.0, 730.0), newVector3(1240.0, 730.0), newVector3(1430.0, 445.0), newVector3(1585.0, 465.0)],
    @[newVector3(320.0, 190.0), newVector3(500.0, 200.0), newVector3(720.0, 510.0), newVector3(1270.0, 510.0), newVector3(1430.0, 200.0), newVector3(1590.0, 190.0)],
    @[newVector3(340.0, 730.0), newVector3(475.0, 775.0), newVector3(655.0, 480.0), newVector3(1275.0, 480.0), newVector3(1480.0, 775.0), newVector3(1600.0, 730.0)],
    @[newVector3(290.0, 480.0), newVector3(830.0, 480.0), newVector3(950.0, 145.0), newVector3(1180.0, 480.0), newVector3(1600.0, 480.0)],
    @[newVector3(290.0, 480.0), newVector3(830.0, 480.0), newVector3(980.0, 840.0), newVector3(1180.0, 480.0), newVector3(1600.0, 480.0)],
    @[newVector3(340.0, 250.0), newVector3(610.0, 250.0), newVector3(720.0, 1075.0), newVector3(970.0, 55.0), newVector3(1240.0, 1035.0), newVector3(1360.0, 250.0), newVector3(1630.0, 250.0)],
    @[newVector3(340.0, 720.0), newVector3(540.0, 720.0), newVector3(750.0, 55.0), newVector3(980.0, 990.0), newVector3(1220.0, 30.0), newVector3(1400.0, 720.0), newVector3(1630.0, 720.0)],
    @[newVector3(340.0, 720.0), newVector3(575.0, 700.0), newVector3(735.0, 105.0), newVector3(990.0, 630.0), newVector3(1200.0, 105.0), newVector3(1380.0, 700.0), newVector3(1630.0, 720.0)]
]

proc playWinLine*(node: Node, index: int):Animation {.discardable.} =
    let wlNode = node.newChild("wlNode")
    let imageNode = newNodeWithResource("slots/candy2_slot/winlines/precomps/winline")
    let wlComp = wlNode.addComponent(WinLine)
    let anim = imageNode.animationNamed("play")

    node.addChild(imageNode)
    imageNode.enabled = false

    for i in 0..positions[index].high:
        let ch = wlNode.newChild($i)
        ch.worldPos = positions[index][i]

    wlComp.createPointsFromChildren()
    wlComp.color = newColor(0,0,0,0)
    wlComp.width = 25.0
    wlComp.density = 0.5
    wlComp.sprite = imageNode.children[0].getComponent(Sprite)
    node.addAnimation(anim)
    anim.onComplete do():
        wlNode.removeFromParent()
        imageNode.removeFromParent()
        
    result = anim