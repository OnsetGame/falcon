import strutils

type LoadingInfo* = ref object
    ## Holds scene custom info for loading screen.
    mTitle : string
    mImageName : string

template title*(li: LoadingInfo): string = li.mTitle
template imageName*(li: LoadingInfo): string = li.mImageName

proc newLoadingInfo*(title: string, imageName: string) : LoadingInfo =
    result.new()
    result.mTitle = title
    result.mImageName = imageName
