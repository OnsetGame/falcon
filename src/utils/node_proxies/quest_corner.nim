import node_proxy.proxy
import rod / [ node, component ]
import rod / component / [ text_component, color_balance_hls ]
import nimx / [ formatted_text, types, matrixes ]

nodeProxy CornerGreen:
    hls* ColorBalanceHLS {onNode: "corner_placeholder.png"}:
        hue = 86 / 360
        saturation = -0.05

    cornerText* Text {onNode:"corner_text"}:
        mText.boundingSize = newSize(200, 50)
        verticalAlignment = vaCenter
        horizontalAlignment = haCenter
        node.position = newVector3(73, 65)
        node.anchor = newVector3(100, 50)

nodeProxy CornerYellow:
    hls* ColorBalanceHLS {onNode: "corner_placeholder.png"}:
        hue = 52 / 360
        saturation = 0.16

    cornerText* Text {onNode:"corner_text"}:
        mText.boundingSize = newSize(200, 50)
        verticalAlignment = vaCenter
        horizontalAlignment = haCenter
        node.position = newVector3(73, 65)
        node.anchor = newVector3(100, 50)

nodeProxy CornerRed:
    hls* ColorBalanceHLS {onNode: "corner_placeholder.png"}:
        hue = 0.0

    cornerText* Text {onNode:"corner_text"}:
        mText.boundingSize = newSize(200, 50)
        verticalAlignment = vaCenter
        horizontalAlignment = haCenter
        node.position = newVector3(73, 65)
        node.anchor = newVector3(100, 50)