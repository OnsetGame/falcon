import rod / [node, asset_bundle]
import rod / tools / [ serializer ]
import rod / utils / [ property_desc, serialization_codegen ]
import rod / component
import rod / component / sprite
import nimx / [types, property_visitor, image]

import core / net / remote_image
export RemoteImageStatus

import loader_component


type RemoteImageComponent* = ref object of Component
    downloader: RemoteImage
    image: Image
    iNode: Node

    onStart*: proc()
    onProgress*: proc(total, progress, speed: BiggestInt)
    onComplete*: proc(image: Image)
    onError*: proc(err: string)
    onAbort*: proc()

proc setImage(c: RemoteImageComponent) =
    if c.iNode.isNil or c.image.isNil:
        return
    let comp = c.iNode.component(Sprite)
    comp.image = c.image
    comp.offset = newPoint(-c.image.size.width / 2, -c.image.size.height / 2)

proc status*(c: RemoteImageComponent): RemoteImageStatus = c.downloader.status
proc cacheable*(c: RemoteImageComponent): bool = c.downloader.cacheable
proc imageNode*(c: RemoteImageComponent): Node = c.iNode

proc `ignoreCache=`*(c: RemoteImageComponent, ignoreCache: bool) = c.downloader.ignoreCache = ignoreCache
proc url*(c: RemoteImageComponent): string = c.downloader.url
proc `url=`*(c: RemoteImageComponent, url: string) =
    c.image = nil
    c.downloader.url = url
    c.downloader.download()

method init*(c: RemoteImageComponent) =
    c.downloader = newRemoteImage()

    c.downloader.onStart = proc() =
        discard c.node.addComponent(LoaderComponent)
        if not c.onStart.isNil:
            c.onStart()

    c.downloader.onProgress = proc(total, progress, speed: BiggestInt) =
        if not c.onProgress.isNil:
            c.onProgress(total, progress, speed)

    c.downloader.onComplete = proc(image: Image) =
        c.node.removeComponent(LoaderComponent)
        c.image = image
        c.setImage()
        if not c.onComplete.isNil:
            c.onComplete(image)

    c.downloader.onError = proc(err: string) =
        c.node.removeComponent(LoaderComponent)
        if not c.onError.isNil:
            c.onError(err)

    c.downloader.onAbort = proc() =
        c.node.removeComponent(LoaderComponent)
        if not c.onAbort.isNil:
            c.onAbort()
        
method componentNodeWasAddedToSceneView*(c: RemoteImageComponent) =
    c.iNode = c.node.newChild("RemoteImageComponent")
    c.iNode.position = c.node.anchor
    c.setImage()

method componentNodeWillBeRemovedFromSceneView*(c: RemoteImageComponent) =
    c.node.removeComponent(LoaderComponent)
    c.iNode.removeFromParent()
    c.iNode = nil

method visitProperties*(c: RemoteImageComponent, p: var PropertyVisitor) =
    p.visitProperty("url", c.url)

registerComponent(RemoteImageComponent)