import sets, times, osproc, json, os, strtabs, strutils, sequtils
import nimx.naketools

let gles2Only = true
proc isMobileTarget(b: Builder): bool = b.platform in ["android", "ios", "ios-sim"]

const additionalFonts = [
    "SpicyRice-Regular.ttf",
    "Folkster-Regular.ttf",
    "BoyzRGross.ttf",
    "AlfaSlabOne-Regular.ttf",
    "Exo2-Black.ttf",
    "Exo2-Bold.ttf",
    "Exo2-Regular.ttf",
    "Futura.ttf",
    "MagicSchoolOne.ttf",
    "Tokyo2097.ttf",
    "TannenbergFett.ttf"
]

proc versionCode(): int =
    if getEnv("GITLAB_CI").len > 0:
        let headCommitDate = execProcess("git", ["--no-pager", "show", "-s", "--format=%ci", "HEAD"], options = {poUsePath}).strip()
        result = versionCodeWithTime(parse(headCommitDate, "yyyy-MM-dd HH:mm:ss"))
    else:
        result = versionCodeWithTime(now())

proc rodasset(b: Builder, command: string, arguments: varargs[string]) =
    let downsampleRatio = if b.isMobileTarget: 2 else: 1
    var args = @["rodasset", command, "--platform=" & b.platform, "--downsampleRatio=" & $downsampleRatio]
    args.add(arguments)
    direShell(args)

beforeBuild = proc(b: Builder) =
    b.appName = "Slotopia"
    b.appVersion = "1.0"
    b.javaPackageId = "com.onsetgame.reelvalley"
    b.bundleId = "com.onsetgame.reelvalley"
    b.useGradle = true

    let vc = versionCode()
    b.appVersion = "1.0." & $vc

    if vc == 0:
        if b.platform != "ios":
            b.appVersion &= "a" # iOS version should not contain letters
    else:
        b.buildNumber = vc

    b.activityClassName = ".MainActivity"
    b.mainFile = "src/main"
    b.additionalNimFlags.add(["-d:useLibzipSrc", "--putenv:PREFS_FILE_NAME=falcon.json", "-d:ssl", "--path:src"])
    b.additionalNimFlags.add("--path:res") # TODO: Remove this line
    b.additionalNimFlags.add("-d:clientVersion=" & $vc)
    #b.additionalNimFlags.add("-d:bfsFind")

    # b.additionalNimFlags.add("-d:noAutoGLerrorCheck")
    #b.additionalNimFlags.add("--debugger:native")
    b.screenOrientation = "sensorLandscape"
    if b.isMobileTarget and gles2Only:
        b.additionalNimFlags.add("-d:gles2only")
    if b.platform == "android":
        b.appName = "ReelValley"
        b.androidApi = 24
        b.additionalLinkerFlags.add(["-lOpenSLES", "-lz"])
        if not gles2Only:
            b.additionalLinkerFlags.add("-lGLESv3")
        # b.additionalCompilerFlags.add("-g")
        b.targetArchitectures = @["armeabi-v7a"]
        b.androidPermissions.add("INTERNET")
        b.additionalNimFlags.add(["--dynlibOverride:ssl", "--dynlibOverride:crypto", "--lineDir:on", "--dynlibOverride:z", "-d:useRealtimeGC"])
        b.nimParallelBuild = 4
        b.androidStaticLibraries.add(["openssl_static", "opencrypto_static"])
        b.additionalLibsToCopy.add("openssl-android")
        b.additionalAndroidResources.add("rawdata"/"android_gradle")

        # b.additionalNimFlags.add(["-d:useGcAssert", "-d:useSysAssert"])
        if not b.debugMode:
            b.additionalNimFlags.add(["-d:noSignalHandler"])

    elif b.platform in ["ios" , "ios-sim"]:
        const fbID = "12345"
        b.codesignIdentity = "iPhone Developer:  123456"
        b.teamId = "12345"
        b.iOSMinVersion = "9.3"

        b.additionalPlistAttrs["CFBundleURLTypes"] = %*[{"CFBundleURLSchemes": ["fb" & fbID]}]
        b.additionalPlistAttrs["LSApplicationQueriesSchemes"] = %["fbapi", "fb-messenger-api", "fbauth2", "fbshareextension"]

        b.additionalLinkerFlags.add(["-Llib", "-lssl-ios", "-lcrypto-ios", "-framework", "AVFoundation", "-Flib/facebook-ios-frameworks", "-g"])
        b.additionalNimFlags.add(["--dynlibOverride:ssl", "--dynlibOverride:crypto", "--lineDir:on"])

    elif b.platform in ["emscripten", "wasm"]:
        b.additionalNimFlags.add("--lineDir:on")
        b.disableClosureCompiler = b.debugMode
        b.enableClosureCompilerSourceMap = false #not b.debugMode
        b.additionalLinkerFlags.add(["-s", "TOTAL_MEMORY=268435456"]) # 256MB

        for f in additionalFonts:
            b.emscriptenPreloadFiles.add(b.originalResourcePath & "/" & f & "@/res/" & f)
        b.rodasset("jsonmap", "--resDir=res", "--output=build/emscripten/assets.json")
        b.emscriptenPreJS.add("src/platformspecific/javascript/resource_mappings.js")

preprocessResources = proc(b: Builder) =
    if b.platform == "ios":
        copyDir(b.originalResourcePath / "ios", b.resourcePath)

    if b.platform == "ios" or b.platform == "ios-sim" or b.platform == "emscripten":
        b.copyResourceAsIs("OpenSans-Regular.ttf")
    for f in additionalFonts:
        b.copyResourceAsIs(f)

    var args = newSeq[string]()
    if b.debugMode:
        args.add("--debug")
    args.add(["--src=" & b.originalResourcePath, "--dst=" & b.resourcePath])
    b.rodasset("pack", args)

task "tests", "Run autotests":
    let b = newBuilder()
    let runTests = b.runAfterBuild
    if b.platform in ["js", "emscripten", "windows","macosx","linux"]:
        b.runAfterBuild = false
    b.additionalNimFlags.add "-d:runAutoTests"
    b.build()
    if runTests:
        let args = newStringTable({"nimxAutoTest": "all"})
        if b.platform in ["js", "emscripten"]:
            when defined(windows):
                b.runAutotestsInFirefox(args)
            else:
                b.runAutotestsInChrome(args)
        elif b.platform == "android":
            b.runAutotestsOnConnectedDevices(true, args)
        elif b.platform == "macosx":
            direShell("build/macosx/Slotopia.app/Contents/MacOS/Slotopia", "--nimxAutoTest", "all")
        elif b.platform in ["windows","linux"] :
            direShell("build" / b.platform / "Slotopia", "--nimxAutoTest", "all")

task "onlyTests", "Run autotests":
    let b = newBuilder()
    b.configure()
    var tests = newSeq[string]()
    for kind, key, val in getopt():
        case kind
        of cmdLongOption, cmdShortOption:
            case key
            of "nimxAutoTest":
                tests.add(val)
        else: discard

    let testsStr = tests.join(",")

    case b.platform
    of "js", "emscripten":
        let args = newStringTable({"nimxAutoTest": testsStr})
        when defined(windows):
            runAutotestsInFirefox("build/" & b.platform & "/main.html", args)
        else:
            runAutotestsInChrome("build/" & b.platform & "/main.html", args)
    of "android":
        let args = newStringTable({"nimxAutoTest": testsStr})
        let devId = getEnv("ANDROID_SERIAL")
        if devId.len > 0:
            b.runAutotestsOnAndroidDevice(devId, false, args)
        else:
            b.runAutotestsOnConnectedDevices(false, args)
    of "macosx":
        direShell("build/macosx/Slotopia.app/Contents/MacOS/Slotopia", "--nimxAutoTest", testsStr)
    of "linux", "windows":
        direShell("build" / b.platform / "Slotopia", "--nimxAutoTest", testsStr)

task "assets", "Build and cache assets":
    let b = newBuilder()
    b.rodasset("pack", "--onlyCache", "--src=res", "--dst=/dev/null")

task "ls-assets", "List assets":
    direShell("rodasset", "ls", "--resDir=res")

task "ls-external-assets", "List assets":
    direShell("rodasset", "ls", "--androidExternal", "--resDir=res")

task "versionCode", "Display version code":
    echo versionCode()

task "help", "Help":
    echo "-d:scene=SceneClassName - Start scene after splash screen (by default game starts from map)"
    echo "-d:loc=localization - Build with specific localization (by default localization is en)"
    echo "-d:local         - Build uses local server http://localhost:5001"
    echo "-d:js            - Javascript build"
    echo "-d:emscripten    - Emscripten build"
    echo "-d:android       - Android build"
    echo "-d:ios           - Ios build"
    echo "-d:ios-sim       - Ios simulator build"
    echo "-d:windows       - Windows build"
    echo "-d:release       - Release mode"
    echo "-d:enableEditor  - Allows editor usage with release option"
