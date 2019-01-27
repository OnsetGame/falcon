import json, strutils, times, logging
import preferences

const DEFAULT_TAG* = "DefaultTag"
const GAMESTATES_KEY = "GameStates"

proc setGameStateVal(key, tag: string, val: JsonNode)=
    if GAMESTATES_KEY notin sharedPreferences():
        sharedPreferences()[GAMESTATES_KEY] = newJObject()

    if tag notin sharedPreferences()[GAMESTATES_KEY]:
        sharedPreferences()[GAMESTATES_KEY][tag] = newJObject()

    sharedPreferences()[GAMESTATES_KEY][tag][key] = val
    syncPreferences()

proc getGameStateVal(key, tag: string): JsonNode=
    try:
        result = sharedPreferences()[GAMESTATES_KEY][tag][key]
    except:
        warn "Game state ", key, " by tag ", tag, " not found "
        discard

proc hasGameStateVal(key, tag: string): bool=
    result = not sharedPreferences(){GAMESTATES_KEY, tag, key}.isNil

proc setGameState*[T](name:string, value: T, tag: string = DEFAULT_TAG) =
    setGameStateVal(name, tag, %value)

proc setGameState*(name: string, value: JsonNode, tag: string = DEFAULT_TAG) =
    setGameStateVal(name, tag, value)

proc getGameState*(name: string,  tag: string = DEFAULT_TAG): JsonNode =
    let state = getGameStateVal(name, tag)
    return state

proc getStringGameState*(name: string,  tag: string = DEFAULT_TAG): string =
    let state = getGameStateVal(name, tag)
    if not state.isNil and state.kind == JString:
        return getStr(state)

    warn "State type mismatch (state is not string)!"

proc getIntGameState*(name: string,  tag: string = DEFAULT_TAG): int =
    let state = getGameStateVal(name, tag)
    if not state.isNil and state.kind == JInt:
        return getInt(state)
    warn "State type mismatch (state is not int)!"

proc getFloatGameState*(name: string,  tag: string = DEFAULT_TAG): float =
    let state = getGameStateVal(name, tag)
    if not state.isNil and state.kind == JFloat or state.kind == JInt:
        return getFloat(state)
    warn "State type mismatch (state is not float)!"

proc getBoolGameState*(name: string,  tag: string = DEFAULT_TAG): bool =
    let state = getGameStateVal(name, tag)
    if not state.isNil and state.kind == JBool:
        return getBool(state)
    warn "State type mismatch (state is not bool)!"

proc hasGameState*(name: string,  tag: string = DEFAULT_TAG): bool =
    result = hasGameStateVal(name, tag)

proc removeGameState*(name: string,  tag: string = DEFAULT_TAG) =
    if hasGameState(name, tag):
        var tagNode = sharedPreferences()[GAMESTATES_KEY][tag]
        tagNode.delete(name)
        if tagNode.len == 0:
            sharedPreferences()[GAMESTATES_KEY].delete(tag)
        syncPreferences()

proc getAllStates*(): string =
    result = $sharedPreferences()[GAMESTATES_KEY]

proc removeStatesByTag*(tag: string) =
    if not sharedPreferences(){GAMESTATES_KEY, tag}.isNil:
        sharedPreferences()[GAMESTATES_KEY].delete(tag)
        syncPreferences()

proc removeAllStates*() =
    sharedPreferences().delete(GAMESTATES_KEY)
    syncPreferences()
