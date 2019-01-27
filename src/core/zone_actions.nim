import zone
import quest / [quests, quests_actions]


proc unlock*(z: Zone, cb: proc())=
    sharedQuestManager().completeQuestWithDeps(z.feature.unlockQuestConf.id, cb)