import shafa / game / narrative_types
export narrative_types
import shared / localization_manager


proc name*(c: NarrativeCharacterType): string =
    if c == None:
        return ""
    result = localizedString("CHARACTER_" & $c)