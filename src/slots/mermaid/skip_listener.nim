import nimx.timer
proc skipListener*(bSkip: proc(): bool, job: proc(callback: proc()), ev: proc()) = 
    var timer: Timer
    var checkableEv: proc()
    
    checkableEv = proc() = 
        checkableEv = nil
        if not timer.isNil:
            timer.clear()
        ev()

    timer = setInterval(0.1) do():
        if bSkip(): 
            if not checkableEv.isNil: checkableEv()
    

    job do():
        if not checkableEv.isNil: checkableEv()
