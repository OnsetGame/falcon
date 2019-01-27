import rod / component
import rod / component / ae_composition
import rod / node
import nimx / [ matrixes, types, animation ]
import shared / window / button_component
import core / [ zone, zone_helper ]

import utils / icon_component

import falconserver / common / game_balance

type ZoneFeatureButton* = ref object of Component
    bttn*: ButtonComponent
    zone: Zone
    isShowed*: bool

    bucksIco*: Node
    chipsIco*: Node
    featureIco*: Node
    freeIco*: Node
    alertBig*: Node
    alertSmall*: Node
    playBttnNode*: Node
    shadowGreen*: Node
    shadowRed*: Node
    shadowBlack*: Node
    boostersAll*: Node
    freeShadow*: Node
    animCompos*: AEComposition

proc show*(c: ZoneFeatureButton) =
    if not c.isShowed:
        c.node.alpha = 1.0
        c.isShowed = true
        c.animCompos.play("in")
        c.bttn.enabled = true

proc hide*(c: ZoneFeatureButton) =
    if c.isShowed:
        c.isShowed = false
        let anim = c.animCompos.play("out")
        anim.onComplete do():
            c.node.alpha = 0.0
        c.bttn.enabled = false

method componentNodeWasAddedToSceneView*(c: ZoneFeatureButton) =
    let r = newNodeWithResource("common/gui/ui2_0/map_feature_buttons")
    r.scale = newVector3(0.75, 0.75, 1)
    r.anchor = newVector3(135.0, 270.0, 0.0)
    c.bttn = r.createButtonComponent(newRect(60, 60, 180, 180))

    c.bucksIco    = r.findNode("currency_bucks_placeholder")
    c.chipsIco    = r.findNode("currency_chips_placeholder")
    c.featureIco  = r.findNode("feature_icon_placeholder")
    c.freeIco     = r.findNode("free_round_freecup_placeholder")
    c.alertBig    = r.findNode("alert_big_comp")
    c.alertSmall  = r.findNode("alert_comp")
    c.playBttnNode = r.findNode("play_button")
    c.shadowGreen = r.findNode("shadow_green")
    c.shadowRed   = r.findNode("shadow_red")
    c.shadowBlack = r.findNode("shadow_black")
    c.freeShadow  = r.findNode("free_shadow")
    c.boostersAll = r.findNode("boosters_all")
    c.bucksIco.alpha      = 0.0
    c.chipsIco.alpha      = 0.0
    c.featureIco.alpha    = 0.0
    c.freeIco.alpha       = 0.0
    c.alertBig.alpha      = 0.0
    c.alertSmall.alpha    = 0.0
    c.playBttnNode.alpha  = 0.0
    c.shadowGreen.alpha   = 0.0
    c.shadowRed.alpha     = 0.0
    c.shadowBlack.alpha   = 0.0
    c.boostersAll.alpha   = 0.0
    c.freeShadow.alpha    = 0.0
    c.animCompos = r.getComponent(AEComposition)

    c.node.addChild(r)
    c.bttn.enabled = false
    c.node.alpha = 0.0

method setBttnAction*(c: ZoneFeatureButton) {.base.} =
    c.bttn.onAction do():
        c.zone.openFeatureWindow()

proc `zone=`*(c: ZoneFeatureButton, z: Zone) =
    c.zone = z
    c.featureIco.component(IconComponent).name = $c.zone.feature.kind
    c.setBttnAction()

proc zone*(c: ZoneFeatureButton): Zone = c.zone

method onUpdate*(c: ZoneFeatureButton) {.base.} = discard

registerComponent(ZoneFeatureButton)
