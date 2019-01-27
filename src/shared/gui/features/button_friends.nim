import button_feature
import core / zone
import rod / node

import shared / localization_manager
import shared / window / social / social_window


type ButtonFriends* = ref object of ButtonFeature


method onInit*(bf: ButtonFriends) =
    bf.icon = "Friends"
    bf.title = localizedString("GUI_FRIENDS_BUTTON")
    bf.zone = "facebook"

    bf.onAction = proc(enabled: bool) =
        if enabled:
            bf.playClick()
            showSocialWindow(SocialTabType.Friends, bf.source)


template newButtonFriends*(parent: Node): ButtonFriends =
    ButtonFriends.new(parent)