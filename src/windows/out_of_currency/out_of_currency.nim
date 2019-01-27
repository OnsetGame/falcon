import variant
import falconserver / common / [ currency, game_balance ]
import core / flow / [ flow, flow_state_types ]
import core / notification_center
import shared / user
import shared / window / [ out_of_money_window, beams_alert_window, exchange_window, window_manager, button_component ]
import windows / store / store_window

import out_of_currency_flow


proc showOutOfCurrency*(outOf: string, cb: proc() = nil) =
    if outOf == "chips":
        let user = currentUser()
        if user.withdraw(0, exchangeRates(user.exchangeNumChips, Currency.Chips).bucks, 0, "exchange"):
            showExchangeChipsWindow("slot_out_of_chips", cb)
        else:
            showStoreWindow(StoreTabKind.Chips, "out_of_chips_alert")
    elif outOf == "parts":
        let win = sharedWindowManager().show(BeamsAlertWindow)
    elif outOf == "tp":
        let win = sharedWindowManager().show(TourPointsAlertWindow)
    else:
        let oc = sharedWindowManager().showAlert(OutOfMoneyWindow)
        oc.setUpDescription(outOf)

        oc.buttonCancel.onAction do():
            oc.buttonClose.sendAction()
            showStoreWindow(StoreTabKind.Bucks, "out_of_bucks_alert")

        if not oc.buttonExchange.isNil:
            oc.buttonExchange.onAction do():
                sharedWindowManager().playSound("COMMON_GUI_CLICK")


proc showOutOfCurrencyState*(outOf: string, cb: proc() = nil) =
    let st = findFlowState(OutOfCurrencyFlowState)

    if st.isNil:
        let st = newFlowState(OutOfCurrencyFlowState)
        st.outOf = outOf
        st.cb = cb
        pushFront(st)
    else:
        if not cb.isNil:
            cb()


method wakeUp*(state: OutOfCurrencyFlowState) =
    showOutOfCurrency(state.outOf, state.cb)
    state.pop()