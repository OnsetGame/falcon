import nimx / [ animation, types, button ]
import rod.node
import rod.rod_types
import rod.component / [ ae_composition, text_component, gradient_fill, particle_system, ui_component ]

import core.slot.event_message
import utils.helpers
export event_message

import node_proxy.proxy
import sequtils

const PREFIX* = "slots/card_slot/branding/precomps/"

template getConfig(n: Node, compName: string, cb: proc()): EventMessageConfig =
    var conf: EventMessageConfig
    conf.compPath = PREFIX & compName
    conf.parent = n
    conf.cb = cb
    conf.particleConf = @[]
    conf.particleConf.add((pattern:"dust_particles", path: "slots/card_slot/particles/dust_scene"))
    conf

proc setParticleRate(p: EventWinPopup, coefs, progresses: seq[float]) =
    let particle = p.proxy.node.findNode("win_coins")
    var startBirthRates: seq[float] = @[]

    assert(coefs.len == progresses.len)

    for c in particle.children:
        let emitter = c.component(ParticleSystem)
        startBirthRates.add(emitter.birthRate)

    for i in 0..coefs.high:
        closureScope:
            let index = i
            p.proxy.playAnim.addLoopProgressHandler(progresses[index].float, false) do():
                for c in 0..particle.children.high:
                    closureScope:
                        let cc = c
                        let emitter = particle.children[cc].component(ParticleSystem)
                        emitter.birthRate = startBirthRates[cc] * coefs[index]

proc playCardStressholderEvent(n: Node, compName: string, amount: int64, cb: proc(), soundCB: proc(p: float)): EventWinPopup =
    var conf = getConfig(n, compName, cb)
    var counters: seq[Node] = @[]

    conf.amount = amount
    conf.particleConf.add((pattern:"coin_particles", path: "slots/card_slot/particles/coins_wawe"))

    proc onInit() =
        for i in 1..3:
            let counter = n.findNode("counter_" & $i & "_@noloc")
            let fill = counter.getComponent(GradientFill)

            fill.startPoint.y = -150
            fill.endPoint.y = 0
            counters.add(counter)

    proc onCountup(p: float) =
        for counter in counters:
            counter.getComponent(Text).text = $(interpolate(0'i64, amount, expoEaseOut(p)))
        soundCB(p)

    conf.onInit = onInit
    conf.onCountup = onCountup
    result = playEventMessage(conf)

proc playBigWin*(n: Node, amount: int64, soundCB: proc(p: float), cb: proc()): EventWinPopup =
    result = n.playCardStressholderEvent("bigwin", amount, cb, soundCB)

proc playHugeWin*(n: Node, amount: int64, soundCB: proc(p: float), cb: proc()): EventWinPopup =
    result = n.playCardStressholderEvent("hugewin", amount, cb, soundCB)
    result.setParticleRate(@[2.0], @[0.5])

proc playMegaWin*(n: Node, amount: int64, soundCB: proc(p: float), cb: proc()): EventWinPopup =
    result = n.playCardStressholderEvent("megawin", amount, cb, soundCB)
    result.setParticleRate(@[2.0, 3.0], @[0.3, 0.6])

proc playResults*(n: Node, amount: int64, resultEventName: string, soundCB: proc(p: float), cb: proc()): EventWinPopup =
    echo "playResults: ", PREFIX, resultEventName
    result = n.playCardStressholderEvent(resultEventName, amount, cb, soundCB)

proc playFiveOfAKind*(n: Node, cb: proc()): EventWinPopup =
    var conf = getConfig(n, "five_of_a_kind", cb)
    result = playEventMessage(conf)