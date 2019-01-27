import tables, json, ospaths, strutils
import nimx / assets / [ asset_loading, json_loading ]

const DEFAULT_LOC* = "en"
const SUPPORTED_LOCS* = ["en"]

type Strings = ref object
    name*: string
    table: Table[string, string]

type LocalizationManager* = ref object
    strings*: seq[Strings]
    currentLoc: string
    currStringsName*: string

var gLocManager: LocalizationManager

proc sharedLocalizationManager*(): LocalizationManager =
    if gLocManager.isNil():
        gLocManager.new()
        gLocManager.currentLoc = DEFAULT_LOC
        gLocManager.strings = @[]
    result = gLocManager

proc `localization=`*(manager: LocalizationManager, loc: string) =
    manager.currentLoc = loc

proc localization*(manager: LocalizationManager): string =
    result = manager.currentLoc

proc addStrings(manager: LocalizationManager, name: string, j: JsonNode) =
    let res = Strings.new()

    res.name = name
    res.table = initTable[string, string]()
    if j.hasKey("strings"):
        for p in j["strings"].pairs:
            res.table[toUpperAscii(p.key)] = p.val.getStr()
    manager.strings.add(res)

proc removeStrings*(manager: LocalizationManager, name: string) =
    var st = manager.strings
    for i in 0..st.len - 1:
        if st[i].name == name:
            manager.strings.del(i)
            break

proc isLocalizedStringExists*(key: string): bool =
    let st = sharedLocalizationManager().strings
    for i in countdown(st.len - 1, 0):
        if st[i].table.hasKey(key):
            return true

iterator localizationTables(): Strings =
    let lm = sharedLocalizationManager()
    for i in countdown(lm.strings.len - 1, 0):
        yield lm.strings[i]

proc localizedString*(key: string): string =
    let uprKey = key.toUpperAscii()
    for st in localizationTables():
        result = st.table.getOrDefault(uprKey)
        if result.len != 0: return
    return "$KEY_" & uprKey

proc localizedFormat*(key: string, args: varargs[string]): string =
    let uprKey = key.toUpperAscii()
    for st in localizationTables():
        let s = st.table.getOrDefault(uprKey)
        if s.len != 0:
            try: return s % args
            except: discard
    return "$KEY_" & uprKey

registerAssetLoader(["strings"]) do(url: string, callback: proc(j: JsonNode)):
    loadJsonFromURL(url) do(j: JsonNode):
        let n = url.splitFile().name
        let mng = sharedLocalizationManager()

        if n == mng.localization:
            mng.addStrings(mng.currStringsName, j)
        callback(j)
