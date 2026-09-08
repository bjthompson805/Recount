# Recount Changelog

<!-- charset-ok: the v1.18.4 entry lists the Addon Language dropdown's own labels, which are the
     native-script names the game shows (Русский, 한국어, 简体中文, 繁體中文). Transliterating them
     would misquote the UI this file is documenting. -->

## [v1.18.8] (2026-08-25) - the reset button actually resets on retail Midnight

### Fixed

- **Retail (Midnight): the Reset confirmation's Yes button did nothing.** Reported from a live client and reproduced here: the reset icon opened "Reset Recount? Do you wish to reset the data?", and answering Yes left every bar exactly where it was. The reset routine clears Recount's own combatant tables -- and on 12.0 those tables are **empty**, because the client took the combat log away and the numbers on screen are read live out of Blizzard's own meter session instead. So the reset was wiping a store that held nothing and then re-drawing the window from the session it had never touched, which on screen is indistinguishable from the button being dead. The reset now also clears the game's combat sessions, through the same call Blizzard's own damage-meter window uses for its "reset all sessions" menu item, and it runs **before** the redraw so the window comes back empty rather than being repainted from the data we just failed to clear. Confirmed working in a retail client.

  Every Classic flavour and pre-12.0 retail are untouched: the new step is gated on Midnight, does not exist at all on the Classic builds, and reports failure quietly rather than erroring on a retail client whose meter API is absent.

### Documentation

- **The README and the CurseForge description were audited against the code, and both were wrong about reporting.** Each claimed the report window offers "Say, Party, Raid, Guild, or a custom channel". The real list (`GUI_Report.lua:34-50`) is Say, Party, Instance, Raid, Guild, Officer, RealID, Whisper and Whisper Target, plus every chat channel you are joined to, with destinations you cannot currently use omitted from the list. Both now say so.

- **Two shipped features were documented nowhere.** **Ctrl+click a bar** pops out a live per-player graph -- it has been in the bar's right-click menu as "Show Realtime Graph (Ctrl Click)" the whole time and in neither document. And the live meter windows were one line under *Reporting* on the CurseForge page, which is also the wrong section; they now have their own, naming what they can actually track (per player, the whole raid's DPS/DTPS/HPS/HTPS, and FPS / latency / traffic / remaining addon bandwidth). Also added: how to drive the window at all -- the CurseForge page had no click, shift-click, right-click, alt-wheel or resize instructions anywhere -- along with **Keep Only Boss Segments**, the who/where recording filters, and the auto-clear-on-instance/group options.

- **The Midnight explanation now has a permanent home instead of living in a patch note.** The one full account of what does and does not work on 12.0 sat inside the v1.18.6 entry under *Recent Updates*, a section this repo holds to the last five patches -- so it was two releases from being deleted, taking the explanation with it. It is a standing section now, updated for what has changed since: the breakdown naming its targets, and reset clearing the game's own sessions.

### Testing

- **Five examples cover the reset path on the Midnight flavour, and the first one is the bug.** It renders a session, asserts a bar is on screen, resets, and asserts the *session* is gone -- not the combatant table, which was always empty and is precisely why the old code looked correct. The rest drive the confirmation dialog's Yes button end to end (the actual reported entry point, which no example had exercised), assert the window is left with no bars, assert a client with no meter API reports failure instead of throwing, and assert the whole thing is absent on Classic. The offline environment gained the `ResetAllCombatSessions` half of `C_DamageMeter`, which it had never modelled.

## [v1.18.7] (2026-08-25) - the retail 12.0 fixes: secret aura data, a removed mouse-over helper, an updated LibGraph, and a spell breakdown that finally names what you hit

### Fixed

- **Retail 12.0: Recount no longer throws every time an aura changes on you or anyone in your group.** Reported as 27 errors in one session: `TrackerModule_Mitigation.lua:198: attempt to perform boolean test on field 'isFullUpdate' (a secret boolean value, while execution tainted by 'Recount')`. The 12.0 client can hand an addon aura data whose fields are *secret* -- readable enough to hand straight to the game's own display widgets, but illegal for an addon to test, compare or use as a lookup key. Damage Prevented does all three: it asks whether an update is a full refresh or a delta, and it files each aura under its spell id and its instance id. Each of those is now checked first and skipped when the client will not let us read it, so the tracking simply goes quiet on that client instead of erroring. `isFullUpdate` was only the first line reached -- the two ids sit two lines further down and would have thrown next, so all four reads are guarded rather than just the one in the report.

  What this costs, said plainly: on a client that makes the fields secret, Damage Prevented records nothing for the auras it cannot read. That is an undercount and never a wrong number, which is the same direction every other unknown in that mode is resolved. It affects retail only; no Classic flavour makes anything secret, and nothing about their behaviour changes.

- **Retail 12.0: the graph windows no longer error continuously while the cursor is near them.** `MouseIsOver` -- the function that answers "is the mouse over this?" -- was removed from the retail client in 12.0, and four places in Recount grabbed it once when the addon loaded and then called it forever after. Because two of them are per-frame handlers, that is not one error but one per frame for as long as the window is open; the same defect in our embedded copy of LibGraph produced 148 in a single sitting. All four now call the widget's own `IsMouseOver` method, which is what the removed function did internally anyway and which every supported flavour has had all along -- so this is one spelling on all six versions, with no version check and no fallback. Affects the damage-over-time graph, the comparison graph, and LibGraph's pie chart.

- **Retail (Midnight): the spell breakdown no longer switches which spell it is showing you, without moving the highlight.** Clicking a spell in the breakdown opens its per-target split below. The window remembered your choice as a ROW NUMBER, and the rows are ranked by damage -- so the moment another spell overtook the one you had selected, the refresh re-selected the same row, which was now a different spell. The highlighted row did not move, so nothing on screen said anything had changed: you would be reading one spell's name against another spell's targets. It now remembers the spell itself and follows it up or down the list.

- **Retail (Midnight): the spell breakdown now names the mobs you hit, and how much you did to each.** Clicking a spell showed a single target row with no name against 0 damage. The damage-done data genuinely has no target side -- the game hands addons one target slot per spell there and leaves it blank -- but the information does exist, in a separate part of the meter that lists each ENEMY and, beneath it, the spells that hit it and who cast them. Read backwards, that is exactly "which mobs did I hit, and for how much", and the lower list is built from it now. Three things had to be right for it to work, and each was wrong in turn: the entries on that side are keyed by a spell id that comes back as `0`, so a per-spell lookup matched nothing and the list stayed empty; the per-target figure lives on the spell entry's own total rather than in the target record, which is blank there too, so the row first arrived correctly named and reading zero; and the percentage was still being taken against the selected spell's total, which is not a share of anything once the list spans every spell. The lower list now reconciles with the Damage Taken view of the same fight.

  Two limits worth stating. Matching a spell to you is done on your **name**, because that record carries no unique id -- so during a raid or dungeon encounter, where the game hides names from addons, the match cannot be made and the list falls back to what it showed before. And where the game reports no usable spell id, the list is everything you damaged rather than just what the selected spell hit; that is broader than the row above it, never a wrong name.

- **Retail (Midnight): per-second figures below 1,000 no longer print all of their decimals.** The breakdown's DPS column showed `161.82124328613` on one row and `5.2K` on the row above it. The game's own number-shortening only shortens at 1,000 and above and hands anything smaller straight back, so a fractional rate arrived at the column with every digit intact. Rates are rounded to whole numbers before the column formats them.

- **Retail (Midnight): the spell breakdown's column headings sat outside the window.** "Name of Ability", "DPS", "Damage" and the two below them were drawn above the window's top border, across the title bar and the close button. The window is a port of the Classic detail window, and the port dropped the container frame that everything in the original hangs off -- a frame 32 pixels shorter than the window, bottom-aligned, so that its top edge starts below the title strip. Every position inside is measured from that container, so with it gone the whole contents -- headings, rows and both pie charts -- were laid out 32 pixels too high. The container is back, so the layout matches the Classic window it was copied from.

- **Retail (Midnight): spells tied on exactly the same total no longer swap places on their own.** With two spells on equal damage the ordering was left to chance, and this window re-sorts several times a second while it is open -- so tied rows could visibly trade places on a tick where nothing had happened at all. Ties now break consistently, so the list only changes when the numbers do. Ties are commonest at the start of a fight, when several spells have landed once each, which is exactly when the breakdown is most likely to be open.

### Libraries

- **The bundled LibGraph-2.0 is replaced with the shared copy, and it now supersedes every other copy on the client.** Recount embeds LibGraph-2.0 for the damage-over-time graph, the comparison graph and the pie charts. The copy shipping here is the merged shared build, carrying the retail 12.0 `IsMouseOver` fix, and it registers in a `+2000` version band.

  That band is the point. Only **one** LibGraph is ever live in a session: every copy registers under the same library name, the highest version number wins, and each loser stops at its own first few lines without defining anything -- silently. Measured across this install on 2026-08-25, the field was Details at `90062` and Recount at `90068` (both stock, both carrying the crash) and FastGuildInvite at `91068` (a private fork, also carrying it). FastGuildInvite's was therefore the copy actually driving Recount's graphs, which is why the earlier fix to Recount's own copy changed nothing in game. At `92068` this one wins outright, so **installing this release fixes the graphs even for players who also run an addon shipping an older LibGraph.** The bands are now `+0` stock, `+1000` a private per-addon fork, `+2000` the shared copy.

  Only the `.lua` changed: all eleven textures were compared byte-for-byte against the shared copy and are identical. The library also gains two hooks Recount does not use yet -- a label hook for localising the axis numbers, and optional X-axis labels -- which are additive and change nothing about current behaviour. This is a stopgap while the library goes out as a proper external dependency; the version bands stop mattering once there is only one copy to install.

### Testing

- **The mitigation suite gained seven examples covering the two paths above.** Six drive each secret field individually -- an unreadable full-update flag, a secret spell id, a secret instance id, a secret id during a full rescan, and a secret caster -- and each asserts the resulting state rather than merely that nothing threw, because the failure worth catching is a guard that skips the wrong thing. The seventh drives the module's own event frame, which is where the reported crash actually entered and which no example had exercised before: calling the tracking function directly cannot catch a dispatcher that stops forwarding the payload.

- **Harness pin moved `b307a9b` -> `1f8fe09`, and contract 22 was withdrawn because it was already delivered.** The window suite reddened the moment the `IsMouseOver` fix landed -- the shared harness stubs the removed `MouseIsOver` *global* and, at our pin, did not stub the widget method it forwarded to. Contract 22 was raised for it; the harness had shipped exactly that the same day, on the `Region` type so textures and font strings get it too, in an adoption entry that cites this addon's crash. Our pin was six entries behind, which is why the request was written at all. Whole suite green after the move. The staged stand-in in `Tests/env_recount.lua` stays for now and is written to yield on its own: every Recount spec loads that private environment rather than the harness's frame layer, so the harness's method does not reach it -- removing it is part of the environment migration already on the repo's todo list, not a loose end from this release.

  Also picked up in that range: the harness now runs `after_each` when an example *fails*. Previously one red example could leave a substituted global installed for every later spec file, turning a single genuine failure into a wall of unrelated ones. Recount's counts did not change; nothing here depended on it.

- **The Midnight suite gained eight examples, every one of them written from a defect seen in a live client rather than imagined.** Both column headers are asserted to sit below the title strip (driven red by giving the container the window's full height, which reproduces the 32-pixel shift exactly); the enemy-side target lookup is covered by its real shape, including the `spellID = 0` that made the first implementation match nothing, the amount that has to come from the spell entry rather than the target record, and a percentage that must be a share of the target list rather than of one spell; and a sub-1,000 rate is asserted to render as `162` rather than `161.82124328613`.

  Two of them are honest about what they do **not** catch, which matters more than the count. The row-position example stays green under the mutation that reddens the header one -- the rows travel with the header, so their relative positions stay valid while the whole block is misplaced -- and that measurement is written at the call site so it is not mistaken for a second catch. Writing the aggregate example also found a real bug before the code shipped: the substitution was being applied inside the per-spell loop, so a second entry for the same spell appended into the shared aggregate table and corrupted the list for every other spell.

- **A fixture that could only produce the happy shape is why none of this went red earlier.** The spell builder in the Midnight suite took a target name as a parameter and every call passed a real one, so the blank record the live client actually sends was never exercised. The general form is worth keeping: when a fixture builder takes a value as a parameter, ask what the live source puts there when it has nothing to put.

- **Reported the same LibGraph defect to FastGuildInvite**, which embeds the same fork and produced the error the user saw, as finding S36 in its `docs/AUDIT.md`. Its copy is that addon's to fix.

- **Answered peer-review round 7 (findings 31, 32 and 33), each driven red before being fixed.** Both breakdown-window fixes above had their production change reverted and the suite re-run to prove the new examples catch them: the selection example failed with the wrong spell under an unmoved highlight, and the ordering example failed with raw encounter order. The pre-existing selection example stayed *green* under both mutations, which is the reviewer's process point demonstrated rather than accepted -- it is retitled for what it actually pins. Finding 33's remedy is a shared `env.widgetsCreatedBy` helper in `Tests/env_recount.lua`, so the two spec files that ask "did this click build a menu" can no longer answer it two different ways; one of them had been counting the whole widget registry, which is both unsound against a weak-valued table and a weaker claim than counting what the click produced. Suite 758 -> 771 passed.

## [v1.18.6] (2026-08-19) - Mana Given, Damage Prevented, a live Midnight spell breakdown, and correct interface versions on every flavour

### Added

- **New "Mana Given" display mode: who *gave* the mana, not just who received it.** Every power gain was recorded against the player who received it, so a question like "how much mana did my Judgement of Wisdom restore to the group this run" had no answer -- the paladin's own record held nothing, and the total was scattered across each recipient. Healing has always recorded both directions (that is what makes "Healing Done" and "Healing Taken" separate modes); power gains only ever had the receiving half. Now they have both. Bars in the new mode are the players who granted mana; clicking one breaks it down two ways -- **by ability** (Judgement of Wisdom, Vampiric Touch, Innervate, Mana Tide Totem) and **by recipient**. Mana only, deliberately: rage, energy and focus are self-generated, so a "given" view of them would never have a row in it.

  Note this records from this version onward. Fights already in your saved data have no giving-side numbers and will show blank in the new mode; nothing is lost or converted, it simply starts accumulating.

- **New "Damage Prevented" display mode: how much damage a mitigation buff actually stopped.** Flat and percentage damage reduction is invisible in the combat log -- the server takes it off before the event is written, so a swing that would have hit for 530 arrives as 500 and looks identical to one that was always 500. But it is still countable, because the reduction is a known constant: a melee swing that lands for anything at all while Stoneskin is up had exactly that constant prevented, and for a percentage buff the pre-reduction number follows from the one that landed. So the number is arithmetic, not an estimate. Bars are the players whose buff did the preventing; clicking one breaks it down **by ability** and **by who it was prevented for**. Armour is deliberately not counted: its reduction changes with attacker level and armour value, so it is not a constant and the same arithmetic does not hold.

  The buff list starts small on purpose. Every entry needs its exact per-rank value confirmed before it goes in, because a wrong number here produces a confident, plausible, wrong figure that nobody can spot by looking -- and a buff that is not listed is simply not counted, which is the right way round to be wrong. Shaman Stoneskin is in; more follow as each is verified. Like Mana Given, this records from this version onward.

### Fixed

- **Retail: moving the opacity slider on a Realtime window's colour dropdown no longer throws a Lua error.** `GUI_Realtime.lua` captured the global `OpacitySliderFrame` when the file loaded and then used it without checking. That global does not exist in the retail client at all -- zero occurrences anywhere in its source -- so on a Midnight client the captured value was nil and the opacity handler errored the moment it ran. It was reachable in normal use: the guard on the neighbouring colour handler is skipped on exactly the paths that open a picker with opacity enabled.

- **Window transparency is no longer applied backwards in one of the two places that read it.** `colors.lua` read the picker's alpha as `1.0 - slider value` on the pre-Dragonflight path, while `GUI_Realtime.lua` read the same slider straight. The client settles it: on Classic Era `ColorPickerFrame:GetColorAlpha()` returns the slider value **unchanged**, so `GUI_Realtime.lua` was right and `colors.lua` was inverted. Both files now call `GetColorAlpha()`, which exists on every flavour and hides the difference between Classic (the opacity slider) and retail (the picker's own colour widget). Nothing in Recount references `OpacitySliderFrame` any more, so the two files can no longer drift apart -- there is only one expression left.

- **Power gains are no longer dropped because the *other* participant is untracked, in either direction.** One shared routine records every power gain, and it is reached from two events that sit at opposite ends of it: an energize is somebody granting you mana, a drain is you taking it from somebody. The check that decided whether to record anything was a single fixed choice, so it was right for one of those and inverted for the other. Mana granted to you by an untracked caster used to vanish; correcting that alone would have started losing a warlock's own drained mana whenever mob tracking was off. Which participant to check is now decided by the event rather than assumed once, so both cases record. Drained mana is also no longer filed under "Mana Given" for the mob it was taken from, which would have credited a boss for giving away mana somebody took off it.

- **The graph window's legend was broken on every flavour, and is fixed.** One anchor point in `GUI_Graph.lua` was spelled `"Right"` instead of `"RIGHT"`. Anchor points are a fixed set of names and the game rejects a mis-spelled one outright, so building the graph window raised an error at that line every single time. Recount catches errors during startup so the rest of the addon still loads -- which is why this showed up only as a small orange "init warning" in your chat frame at login rather than as a broken addon -- but the error stopped the graph window's construction three lines before it created its legend rows. Anything that then tried to read those rows failed too. If you have ever seen a Recount init warning mentioning the graph window, this was it.

- **Shield and death records no longer vanish mid-fight either.** The same sweep as below reached three more places: the record of who shielded whom, written when a shield goes up and when it is refreshed, and the death record itself. Shields are the worst case of the three, because that record is deliberately kept even for someone your filters exclude -- so that a tracked player's detail view can still show who shielded them -- which means it is the one record that could be accumulating and be swept away at the same time. A death is also, by its nature, likely to be the last thing a combatant does for a while, which is exactly the state the sweep collects. All now hold their place.

- **Mana Given, Damage Prevented and absorb credit no longer vanish mid-fight when the person being credited does nothing else.** Recount deletes a combatant it can find no other reason to keep after thirty seconds, and it keeps that clock ticking from a "last seen doing something" stamp that every recorder writes when it credits someone. Three did not: the new Mana Given side, the new Damage Prevented side, and shield absorbs. Somebody credited only by one of those -- a paladin whose Judgement of Wisdom is proccing mana off other people's swings, a shaman whose totem is soaking hits, a priest whose shield is eating damage -- looked idle to that sweep however much they were contributing, and their whole record could be dropped and then start again from zero part-way through a fight. All three now stamp. The comment claiming the omission was deliberate was wrong on the facts: that stamp is a liveness marker for cleanup and has nothing to do with the "active time" that per-second figures are divided by, so writing it cannot inflate anyone's DPS or HPS. This only ever bit players who had turned time/graph data on for a tracked type, because the sweep does not run otherwise.

- **With "Merge Pets w/ Owners" on, a pet's damage now appears in its owner's breakdown instead of only in the bar total.** The merge added the pet's total to the owner's bar and stopped there, so the bar read owner+pet while the ability list underneath it showed the owner's abilities only and added up to less -- with nothing on screen saying the difference was the pet. On a hunter that looks exactly like the pet not being recorded at all, which it always was: every pet has its own combatant record the whole time, and unticking the option shows it as its own bar. The breakdown now reconciles with the bar it sits under. Pet rows are listed separately and named, as `Claw (Fluffy)`, rather than folded into the owner's own abilities -- a pet's Claw is not the hunter's ability, and merging the two would merge the per-hit detail behind each of them too. Applies to damage and healing, and to the "Damaged Who" / "Healed Who" views alongside the ability lists.

- **Retail (Midnight): the spell breakdown window no longer sits there showing a finished fight's numbers.** Clicking a bar on 12.0 opens a spell breakdown for that player, and nothing ever refreshed it. Every function that touches that window after it opens re-draws the rows captured at the instant of the click -- so it could be scrolled, re-sorted and clicked through all day and still be showing the same frozen snapshot. In practice: open it mid-fight, keep fighting, and the main window climbs while the breakdown stands still; the fight ends, the meter resets, the main window empties, and the breakdown is left listing the dead fight's spells with nothing on screen saying which of the two is live. On every other version the same sequence keeps both windows in step, because the ordinary refresh ends by re-filling the detail view and the Midnight path returns 200 lines before it. It now has that step of its own: the window re-reads live data on every meter update, empties when the meter is reset, and keeps the spell you had selected rather than jumping back to the top one each time. This is a retail-only path; no other flavour loads it.

- **A Lua error on death is fixed.** When someone died with no attributable killer and no killing ability, and Recount had already noted a second death event for them moments earlier (the pattern a Spirit of Redemption or a raised ghoul produces), the death handler compared a value that was never set against a number and threw. The comparison is now made from the recorded time of that earlier event, and a missing one means "not a double death" rather than an error.

- **A memory leak that also pinned a per-frame handler on permanently is fixed.** Recount keeps a short list of auras to ignore and sweeps it every fifth of a second, dropping entries older than ten seconds. The sweep was clearing a copy rather than the list itself, so nothing was ever actually dropped: the list grew for the whole session, and because it could never be seen to be empty, the repeating handler that does the sweeping never switched itself off either. Both stop now. Longer sessions were paying for this continuously.

- **Recount is no longer flagged out of date on Classic Era, TBC/Anniversary, Wrath, Cata or retail.** Four of the six manifests declared a stale `## Interface`, and one of the four was the unsuffixed fallback that serves any flavour without a file of its own. `Recount.toc` moves `11508` -> `11509`, `Recount_Cata.toc` `40400` -> `40402`, `Recount_Wrath.toc` `30403` -> `30405`, and `Recount_Mainline.toc` gains `120100` alongside its existing list. Note `11508` is the Vanilla **Test** interface and is *lower* than live Vanilla's `11509`, so the base manifest was not merely a patch behind, it was pointing at a different client. Every value was re-derived two independent ways that agree: the installed clients' own build manifest (`.build.info` -- retail `12.1.0.69382`, Classic Era `1.15.9.69109`, Anniversary `2.5.6.69110`) and the interface-version table on warcraft.wiki.gg for the three flavours with no install on this machine.

- **`Recount_BCC.toc` is renamed `Recount_TBC.toc` (Interface `20505` -> `20506`), which is the only spelling a client actually reads.** The separator is part of the special filename: modern suffixes take an underscore and only the two legacy suffixes (`-BCC`, `-WOTLKC`) take a hyphen, so `_BCC` was neither form and was almost certainly never read by any client rather than having stopped working. The legacy `-BCC` spelling is dead in any case as of Classic Anniversary patch 2.5.5. With no recognised name, TBC and Anniversary clients fell through to `Recount.toc` and were handed a Vanilla manifest -- and because Anniversary is an installed, active product here, that fall-through was live rather than theoretical. `_TBC` covers TBC Classic **and** Classic Anniversary; no separate file is needed.

- **`wow-version-replication.ps1` no longer copies `Tests/` and `docs/` into the other WoW installs.** `Convert-GlobToRegex` set its directory flag only from a trailing backslash -- which the BigWigs packager forbids writing in `.pkgmeta`, so `.pkgmeta` correctly uses bare names and the flag was never true. A bare `Tests` therefore compiled to `^Tests$`, a pattern that matches only a *file* of that name, so the folder was listed in `.pkgmeta`, reported as loaded at startup, and replicated anyway. Bare non-wildcard entries are now resolved against the repo and promoted to directory patterns. The packaged CurseForge zip was never affected; `.pkgmeta` was correct all along and this was the second, drifted implementation of the same rules.

- **The same script no longer copies dotfiles either.** It skipped only the four git dotfiles by name, so `.busted`, `.luacheckrc`, `.luarc.json`, `.markdownlint.json` and `.markdownlintignore` were all being replicated, and any dotfile added later would have been too. It now prunes **any** path component beginning with a dot, matching what the packager does unconditionally -- a rule that cannot be expressed in `.pkgmeta` at all, since dot-prefixed entries there are silently ignored. This one is load-bearing rather than cosmetic: `.git` in these repos is a one-line pointer file to a git directory kept outside the WoW tree, and replicating it aims the copy at the wrong repository.

- **Removed 495 files of previously replicated `Tests/` and `docs/` material from the `_anniversary_`, `_classic_` and `_retail_` installs**, left there by earlier syncs before the two fixes above. Nothing the game loads was involved and the source install was untouched.

### Testing

- **The offline environment stopped carrying its own copies of five things the shared harness now provides.** `Tests/env_recount.lua` had stand-ins for the aura API, number abbreviation, the per-unit-token model, group-channel addon messages and the colour picker, staged while the harness was asked for each. All five are now the harness's and the copies are deleted, which is the point of the migration: one implementation, so the thing the tests exercise is the thing every other addon exercises too.

- **One of those copies had been quietly cancelling the fix it stood in for, and the way that was found is the useful part.** Three predictions were made about which tests would break when the shared code arrived. Only one broke. That looked like good news and was not: two of the stand-ins replaced their globals unconditionally rather than yielding, so the new code never ran at all and the tests passed on the old copies. **The tell for a stand-in that is masking a fix is a prediction that fails to fire, not a test that fails** -- a green suite proves nothing until the replacement is known to be reachable. With them deleted, all 35 sync tests exercise the real message echo, including the one that checks Recount learns its own version from its own broadcast, which is the whole reason that behaviour was requested.

- **Three specs pin the merged-pet fix listed under Fixed above.** They assert the ability breakdown adds up to the bar it sits under, that the pet's rows are named, and that the breakdown is untouched when merging is off. Neutralising the fix reproduces the reported symptom exactly -- bar 700, breakdown 500, one row instead of two -- while the merging-off spec stays green, which is what shows the other two are pinning the merge rather than something both settings share. The pet tests that existed before counted *bars* (two, one, none) and could never have caught this, because the whole defect lives inside a single bar.

- **`Tests/toc_spec.lua` now asserts the live interface number per flavour, not just a plausible range.** The spec already checked interface versions and passed on all four stale manifests, because it only required the number to fall inside a 10000-wide band -- `20505` sits inside `20000-29999` exactly as comfortably as `20506`. A range that wide can only catch a flavour mix-up, which is not the failure that occurs; the failure that occurs is a number one or two patches behind. Each flavour now carries the live value, asserted to be among those declared, with the measurement and its date recorded in the file so a later reader knows what it rests on. The range check is kept alongside it because the two fail differently and the difference is the diagnosis. Six new assertions.

- **The same spec now checks each manifest against the *repository*, not just against the disk, because those are different questions and only the first was being asked.** A test called "loads only files that exist" opens each path a TOC lists and passes if the file is there -- and every file is there, on the machine the work was done on. It says nothing about whether the file is in the repository, which is what the released zip is built from. That gap came within one commit of shipping: all six manifests were tracked, modified, and already listed `TrackerModules\TrackerModule_Mitigation.lua`, while the module itself had never been added to git. The package would have carried six manifests pointing at a file no clone has, on every flavour, and the suite would have stayed green throughout. Each flavour now also asserts that its own TOC is tracked and that every file it lists is tracked; if git cannot be consulted at all the test says so in those words rather than reporting a catastrophe. Made to fail first, and the proof is that the older test passed in the same run.

- **The offline picker now models the client's alpha contract instead of a stored value, which is what made the inverted read survive.** `Tests/env_recount.lua` answered `GetColorAlpha()` from a field it kept itself, on both picker shapes -- something no client does. A spec therefore could not observe the opacity slider at all, so the suite was free to assert the inverted convention indefinitely, and did. The Classic-shaped picker now returns the slider's value as the real client does; the retail-shaped one keeps the stored field as a stand-in for the picker's own colour widget. The spec that asserted `0.25` for a slider at `0.75` now asserts `0.75`, and its comment records why.

- **The offline suite's widget layer is now the shared harness's, not a private re-implementation, and that is what found the graph-window bug.** `Tests/env_recount.lua` carried its own ~240-line widget model whose `SetPoint` simply stored whatever arguments it was handed and whose `GetLeft`/`GetRight`/`GetTop`/`GetBottom` returned made-up numbers. Nothing that mis-spelled an anchor point, or that depended on where a frame actually sat, could ever fail a test. The harness resolves real rectangles from the anchor chain and rejects an invalid anchor exactly as the client does. Swapping the two took the suite from 712 passing to 80, and every one of the 632 failures was traced to a cause: one shipped defect, two harness gaps, and a set of specs that had been asserting against the private model's fictions. All 712 pass again.

- **Several specs were reading methods the game does not have on the widget they were reading them from.** The private model served one flat method table to every widget type, so a StatusBar answered `GetVertexColor` and a Texture answered `GetText` -- neither of which is true in game. Those specs now read the API the client actually exposes (`GetStatusBarColor` for a bar), and two of them were verifying that a value had landed somewhere that does not exist.

- **Five further specs cover the liveness stamp on the absorb, shield, death and damage-prevention paths**, again all made to fail on purpose first. Each asserts the stamp is *current* rather than merely present, which matters because every fixture registers its combatant with an event that already stamps it -- an assertion against "not nil" would have passed with the fix removed. Each of the seven live stamps was then disabled on its own and the whole suite re-run, seven times: every one of them takes at least one spec red on its own, so not a single one is unverified. An eighth apparent call site, in the shield-guessing branch of the absorb path, turns out to sit inside a block that has been commented out since long before this release -- it is not a stamp at all, and an earlier note describing it as an untested gap was describing code that cannot run. The comment there now says so.

- **Two new specs cover the liveness stamp on the giving side of a power gain**, and both were made to fail on purpose before being trusted. One asserts the stamp directly; the other drives the idle sweep across a minute of ten-second gifts and asserts the running total. With the stamp removed the second reports `expected: 60, actual: 10` -- the 10 being the gift that re-created the combatant after the sweep had deleted it, which is the failure in the shape a player would actually see it. The sweep's own preconditions are recorded in the spec: it only runs when time data is on for a tracked type, and the filter clause of its idler test cannot fire for a combatant that has recorded anything, because `AddAmount` gates on the same table.

- **A spec of mine passed for the wrong reason and is fixed.** One of the four new power-gain specs asserted `is_nil` against a combatant name that never existed in the fixture, so it verified nothing while reading as a passing test -- in a spec written to catch a real bug. It now asserts that the receiving side still records while the giving side does not.

- **The linter is trustworthy again.** `.luacheckrc` imported the language server's globals list wholesale into its *read-only* set, and that list contains `_G`. Since every file in the addon opens with `local Recount = _G.Recount`, luacheck read the addon's basic declaration idiom as writing to a read-only global -- roughly fourteen warnings per file across fifty files, a permanently non-empty report in which no real finding could be noticed. The import now filters out anything the addon legitimately writes. Several pieces of genuinely dead code turned up once the noise cleared and were removed -- and so did the death-handler error and the leak listed under **Fixed** above, which is where they belong; a crash filed as tidying is a crash nobody reads about.

- **The unused-argument exemption is gone entirely, rather than being narrowed.** Combat-log handlers are dispatched by position and must declare the client's full argument list whether or not they read each name, so the checker's unused-argument rule had been switched off for the whole addon. That was wrong twice over: the same switch also silences unused *loop variables*, which have no such excuse (measured, it was hiding 54 of those in shipped code, none in a handler), and switching a check off is not how to express a calling convention anyway. Every unread position now carries a leading underscore instead -- the name still records what the client puts there, the position is untouched, and the checker treats the omission as deliberate. 191 parameters across the dispatcher and the tracker modules, with no configuration exemptions left anywhere in the repo.

- **Two blanket `luacheck: ignore` blocks in the dispatcher were replaced with actual fixes.** One hid fourteen combat-log flag constants that were simply never used; they are deleted, and the copied-from-upstream table is now trimmed to what the addon reads. The other hid two near-identical copies of the absorbed-damage handler, one per payload shape; they are now a single body that reads its arguments by index, with the two layouts written out once in a comment above it. The suite covers both shapes and still passes.

- **`.markdownlint.json` stops disabling the rules that decide how the release notes render.** This file is published verbatim as the GitHub release body, so a blank line inside a quote silently splitting it in two, or a list running into the paragraph above it, is a defect in the product rather than a style preference. Four of the five disabled rules were of that kind and are back on; duplicate-heading checking returns in its standard changelog form, where a repeated `### Fixed` under different versions stays legal. Only the line-length rule stays off, because prose that explains *why* runs long. Re-enabling them turned up three real violations repo-wide, all now fixed.

- **The offline picker no longer defines a global the retail client does not have.** `Tests/env_recount.lua` installed `OpacitySliderFrame` on both picker shapes, so the retail-shaped environment modelled a client that has never existed -- and that is the specific unfaithfulness that let the crash above ship, because a load-time capture of the global found an object offline and nil in the real game. The retail shape now omits it, which makes the existing spec a genuine reproduction rather than a guard against re-introducing the call-time form only.

- **The offline environment was running every spec as Classic Era, whatever flavour the spec asked for.** `Tests/env_recount.lua` selected the flavour and then called the shared harness's reset, which ends by restoring the flavour to Classic Era -- so the selection was overwritten before anything read it, and the line that looked like it restored the value was reading the harness's default back. Every version-dependent piece of the environment was therefore built for the wrong client on every run. Found by instrumenting the one call site that visibly disagreed and printing the value: a load asking for retail reported Classic Era. The requested flavour is now handed over directly instead of through a global the harness owns. The remaining half -- that the harness picks its own per-flavour widgets before a consumer can say which flavour it wants -- is raised as a harness contract item.

- **The colour picker's shape now follows the client version, and two selectors became one.** Which of the two colour-picker shapes a spec got was chosen by a bespoke option while the client version was chosen by another, so a run nominally on Classic Era was handed the retail picker -- and the one global that tells the two apart was therefore missing on the only version that has it. Two tests named for "a client with no opacity slider at all" were asserting retail's behaviour on a Classic Era run and passing. The option is deleted rather than kept as an override, because the only thing it could still express is a client that has never shipped; four call sites now name the version they mean.

- **Fifty-six tests asserted nothing, and nine more had their assertion behind a condition that was never true.** Each display mode was driven through four tests, two of which had no assertion at all -- "opens the detail window" clicked a bar and checked nothing -- while a third was wrapped in "if there are any bars", which for three modes there never are. The unfed modes were measured rather than guessed (Absorbs, Threat and Damage Prevented, the last two of which no reading of the fixture would have shown) and the list is now asserted in both directions, so a mode that starts or stops producing bars fails loudly. The rest assert what their names promise: that the click selects the combatant and puts the detail window on screen, and that the right-click builds a menu. 112 mode tests became 150.

- **Ten more tests asserted that a window the setup had just opened was still open.** Locking a detail row, selecting one, selecting a pie slice, walking every detail view, rendering each saved fight, plotting a graph series, toggling the compare window's options -- each ended by checking a window was shown, which nothing in the test could have changed. Three were worse than that: the helper that "opened" the detail window bypassed the code that fills it, so the three selection calls under test hit an empty-table guard and returned immediately, which is why only that assertion could pass. The helper now clicks the bar the way a player does, and each test asserts the state its subject actually writes. Two were then confirmed by deleting the code they cover and watching exactly one test go red each.

- **`Tests/mitigation_spec.lua` is new**, covering the Damage Prevented module: that credit lands on the buff's caster rather than the player who was hit, that a buff refresh arriving as a removal and an addition in the same event never leaves a gap the swings in between fall through, that a swing reduced to nothing is skipped rather than guessed at, and that a swing whose absorbed portion is filed as a second row is still only counted once. Twenty-one assertions.

- **The offline harness pin moves 239 commits**, from `c46cb89` (2026-08-02) to `ff379c2` (2026-08-16). The old checkout predated the harness's Ace3 loader, widget layer, library loader, coverage tool and verification tooling.

- **`Tests/coverage.lua` is deleted; coverage now runs on the harness's own multi-target implementation.** The local file was the staged reference implementation for a request the harness delivered on 2026-08-07, and an addon-local copy of a shared tool is how divergent copies accumulate across the suite. `lua Tests/run_coverage.lua` is unchanged as the entry point, but it is now only a driver: it enumerates the shipped files and hands them to `Tests/wowapi/coverage.lua`. The detail flag is inverted from the old copy -- uncovered lines print by default and `COVERAGE_SUMMARY=1` suppresses them.

- **`.busted` no longer tells the reader to run `busted`.** The file itself is kept, because it is inert and is what stops an accidental invocation collecting recursively, but its header said to run the executable from the Recount root and that instruction gets followed. Doing so collects the harness's *own* self-tests and runs them from the wrong working directory, producing failures the addon did not cause. The one supported command is `lua Tests/wowapi/run.lua`.

- **The two new display modes are now tested by value, not just driven.** The existing mode sweep walks every registered mode through select, refresh, hover and click, which proves nothing raises -- and cannot see a mode reading the *wrong field*, because it still renders a title, still fills a tooltip and still opens a detail window. That is the likeliest defect in both new modes: Mana Given mirrors Mana Gained and reads four sibling keys, and Damage Prevented reads three keys written into the same table. Fifteen specs now assert the values that reach the bar, the two detail views and their order, the totals agreeing between the bar and the detail form, and the tooltip naming the right ability and the right player. Verified by mutation rather than by writing them green: swapping Mana Given onto the gaining fields fails four of them while **all 112 generic mode tests still pass**, which is the argument for having them. One of the fifteen exists only because that exercise found it -- the detail form's own total was asserted by nothing.

- **A limitation the description page had stopped mentioning is back, in the right terms.** The page carried a Midnight warning that had become obsolete -- it said the bars stay empty, which they no longer do -- and removing it left the page silent about what the client genuinely restricts. It now says plainly that on Retail Midnight the game hides combat numbers from addons, so Recount can display live per-player bars and open a breakdown on click, but cannot sort them itself, show a Total bar or percentages, or put a tooltip on a bar. Stated as the game's restriction, which is what it is, and scoped to Midnight so no Classic player reads it as applying to them.

Suite: **727 passing, 0 failing**.

## [v1.18.5] (2026-08-03) - MoP Classic support, TOC metadata corrections

### Fixed

- **MoP Classic gets its own TOC (`Recount_Mists.toc`, Interface 50504/50503).** Recount branches on `WOW_PANDA_CLASSIC` in several places and both the README and the CurseForge description claimed MoP support, but there was no `_Mists` TOC -- so the client fell back to the base `Recount.toc` (Interface 11508), flagged the addon as out of date, and it only loaded at all with "Load out of date AddOns" ticked. Worse, the packager derives the game versions it publishes from the TOC files, so **the v1.18.4 upload registered 1.15.8, 2.5.5, 3.4.3, 4.4.0, 11.2.7, 12.0.5 and 12.0.7 but no 5.5.x** -- CurseForge never offered the build to MoP players at all. The new TOC is byte-identical to the Cata one apart from the interface version.

### Changed

- **Retail now requires VersionCheck-1.0, like every other flavour.** `Recount_Mainline.toc` declared `Dependencies: Ace3` while every Classic TOC declared `Ace3, VersionCheck-1.0` -- and had never listed it in the file's history, so retail players got no in-game notification when a new Recount shipped. Both are hard dependencies now on all six flavours. CurseForge already installs both automatically (they are listed under `required-dependencies` in `.pkgmeta`), so this changes nothing for anyone installing through the app; a manual installer needs VersionCheck-1.0 present, as Classic players already did. `Tests/toc_spec.lua` asserts the dependency lines stay in step from here on.

- **The bundled libraries are declared as embedded rather than as optional dependencies.** Every TOC listed `LibDropdown-1.0, LibSharedMedia-3.0, LibBossIDs-1.0, LibGraph-2.0` (and Classic Era alone also listed `LibDataBroker-1.1, LibDBIcon-1.0`) under `## OptionalDeps:` -- but all six of those ship inside `libs/` and are loaded by `embeds.xml` or by explicit TOC lines. `OptionalDeps` only reorders *standalone addons* of the same name, so those entries were inert and described the addon incorrectly. Replaced across all six TOCs with `## X-Embeds: LibStub, LibDropdown-1.0, LibBossIDs-1.0, LibSharedMedia-3.0, LibGraph-2.0, LibDataBroker-1.1, LibDBIcon-1.0` -- the field that actually means "bundled inside this addon", now identical on every flavour and naming all seven (the old line missed `LibStub` entirely and used the wrong capitalisation for `LibDropdown-1.0`). `Tests/toc_spec.lua` cross-checks the declaration against the contents of `libs/`, so a library cannot be bundled in future without being recorded.

### Testing

- **`Tests/toc_spec.lua` guards the flavour TOCs against drift.** They are near-identical by design, so the failure mode is one TOC gaining a file the others do not (that flavour silently loses a feature) or a flavour having no TOC at all. The spec asserts every supported flavour has a TOC, that its interface version is in that flavour's range, that every file it lists exists on disk, that the Classic flavours load exactly the same files in the same order, that retail loads that same list plus the two Midnight files and no Classic flavour loads them, that all 15 locale files are listed, and that dependencies, saved variables, title and project id match across flavours.

## [v1.18.4] (2026-08-03) - Addon Language selector, nine bug fixes, offline test suite

### Added

- **"Addon Language" dropdown in Settings.** Recount's own interface text can now be forced to any bundled translation, independent of your WoW client language -- a player on an English client can run Recount in German, a German client in English, and so on. The dropdown lists **Auto** (the previous behavior -- follow the client locale) plus all 14 bundled languages: English, Deutsch, Español, Español (AL), Français, Italiano, Nederlands, Português (BR), Русский, 한국어, 简体中文, 繁體中文, Thai, Filipino. The choice is saved (`RecountLanguage`) and applies on the next `/reload`. In-game item / spell / unit names still come from your client and are unaffected.

- **`README.md` now ships with the addon.** A player-facing guide sitting next to `CHANGELOG.md` in the installed folder and on the GitHub page: what Recount does, what it needs installed alongside it (Ace3 and VersionCheck-1.0), how to drive the window, every display mode, the detail / graph / compare / death-log views, fight history, live meter windows, reporting, the minimap button and broker feed, the settings worth knowing about, the full slash-command and keybinding surface, the retail Midnight differences, and a short troubleshooting section. It is deliberately **not** in `.pkgmeta`'s ignore list — it is meant to be read after installing, not only on the web.

### Fixed

- **Right-clicking the minimap button no longer throws an error when opening Recount's settings.** On clients that ship `C_SettingsUtil.OpenSettingsPanel` (TBC and other flavors on the newer settings backend), `Settings.OpenToCategory` forwards its argument to `C_SettingsUtil.OpenSettingsPanel`, which requires a **numeric** category ID. `GUI_Minimap.lua` passed the literal string `"Recount"`, producing `bad argument #1 to 'OpenSettingsPanel' (outside of expected range …)` from `Blizzard_Settings.lua:144`. Recount now uses the real category identifier handed back by AceConfigDialog when the panel is registered.

- **The main window is no longer hidden when "Hide window when not collecting" is off.** `Recount:SetZoneGroupFilter` — the combined zone+group filter that every zone change actually goes through — was missing a pair of parentheses: `HideCollect and IsShown() or not GlobalDataCollect` binds as `(HideCollect and IsShown()) or (not GlobalDataCollect)`, so turning global data collection off hid the window even though auto-hide was never enabled. The zone-only and group-only filters had the correct grouping; all three now agree.

- **Lowering "Max Fights" now trims the fight list even when there is no data.** `Fights:DeleteOverflowFights` cleared `Recount.db2.FoughtWho` inside its per-combatant loop, so with zero combatants recorded (right after a reset, for instance) the fight names survived and the fight dropdown kept offering entries with nothing behind them. The name list and the death log are per-meter, not per-combatant, and are now trimmed once.

- **Recount no longer writes into Blizzard's class-colour table.** `Colors:GetColor("Class", …)` stamped `a = 1` onto the `RAID_CLASS_COLORS` / `CUSTOM_CLASS_COLORS` entry it was reading, mutating a table shared with the default UI and every other addon. It now returns a copy.

- **Clicking a bar on retail Midnight no longer throws.** `Recount:CreateMidnightDetailWindow` never registered its window with `Recount:AddWindow`, so the frame had no `Above` / `Below` links; its own `OnShow` calls `Recount:SetWindowTop`, which then indexed `window.Below` — nil. Every attempt to open the spell breakdown from a bar errored. The window now joins the stacking chain like every other Recount window, and `SetWindowTop` falls back to `UIParent`'s frame level when a window has nothing below it instead of erroring.

- **Other players' pets no longer resolve to your own pet.** `Recount:FindPetUnitFromFlags` tested affiliation with `bit_band(COMBATLOG_OBJECT_AFFILIATION_MINE)` — no mask argument. LuaBitOp returns the value unchanged for a one-argument `band`, so the test was `MINE ~= 0`, i.e. always true, and **every** pet resolved to the `"pet"` unit token. Any unit lookup for a raid or party pet (tooltips, health, threat) pointed at the player's own pet instead. Now masked against `unitFlags`.

- **Disabling the addon no longer errors.** `Recount:OnDisable` called `Recount:UnregisterAllEvents()`, but Recount embeds AceConsole / AceComm / AceTimer and **not** AceEvent, so the addon object has no such method. The client events live on the `Recount.events` frame, which is what is unregistered now.

- **`Recount:AddGraphNameEntry` works.** The public registration point tracker modules use to label their own graph series called `GraphName.insert(k, v)` on a plain lookup table, which has no `insert` field — every call errored. It assigns `GraphName[k] = v`.

- **`Recount:FlagSync` no longer errors on a group member with no recorded data.** It indexed the combatant record without checking it exists.

- **A pet's owner is now recorded on the pet.** `Recount:SetOwner` registered the pet on its owner but never set `Owner` on the pet itself — the field was only ever written as `false` (the "not a pet" marker), so three separate features that read it were dead: pet damage and healing were **left out of the raid data sync** entirely, deleting a pet left its name behind on the owner's pet list, and the "Merge Pets" option's owner inheritance never applied, so a pet stayed on the meter even when its owner's category was filtered out.

### Testing

- **Offline unit-test suite (`Tests/`).** Recount now carries a busted-compatible spec suite built on the shared [WoWAPITesting](https://github.com/Pimptasty/WoWAPITesting) harness (added as a submodule at `Tests/wowapi`), runnable with nothing but a Lua 5.1 interpreter: `lua Tests/wowapi/run.lua`. **596 specs, all passing.** The suite loads Recount's *real shipped files* — and the real Ace3 / LibDBIcon / LibGraph / LibDropdown libraries from the sibling AddOns folders — into an offline environment, then drives the addon through its actual entry points (combat-log events, minimap clicks, widget scripts, colour-picker callbacks, addon-to-addon sync messages) rather than testing reimplementations.
  - `Tests/env_recount.lua` stages what the shared harness does not yet provide: a `bit` library faithful to LuaBitOp (bare Lua 5.1 has none), a frame system whose unknown keys resolve to `nil` rather than to no-op functions, named children for `FauxScrollFrameTemplate` / `OptionsSliderTemplate` / `GameTooltipTemplate`, a client-style `debugstack` (LibGraph-2.0 parses its own stack trace to find its textures and errors without it), a WoW-compatible `xpcall` (stock Lua 5.1 drops the extra arguments ChatThrottleLib passes through it, so no addon message ever reached the wire), `C_DamageMeter` with 12.0 secret-value semantics, a `UIDropDownMenu` that actually runs its initializer, and selectable settings-backend / colour-picker contracts. Each is written up in `Tests/HARNESS_CONTRACT.md` for upstreaming; the submodule was not modified.
  - `Tests/coverage.lua` measures exact line coverage from Lua 5.1 bytecode debug info rather than a source-text heuristic. `lua Tests/run_coverage.lua` reports **16980/19275 executable lines (88.1%)** across every shipped file; excluding the locale data files that is **≈83%** of the code. Every file is above 63%, and 24 of 32 are above 84%: `WindowOrder` 98%, `GUI_DeathGraph` 98%, `GUI_Detail_Midnight` 97%, `GUI_Reset` 96%, `Fonts` 96%, `PowerGains` 96%, `GUI_TitanPanel` 95%, `Resurrection` 95%, `Tracker_Midnight` 94%, `CCBreakers` 94%, `colors` 91%, `Fights` 91%, `zonefilters` 91%, `Interrupts` 91%, `Dispels` 91%, `roster` 90%, `deletion` 90%, `GUI_Config` 90%, `Threat` 89%, `Widgets` 87%, `GUI_Minimap` 86%, `Recount_Modes` 84%, `Recount.lua` 84%, `GUI_Report` 82%, `GUI_Graph` 80%, `Tracker` 79%, `LazySync` 77%, `GUI_Detail` 77%, `GUI_CompareGraph` 74%, `GUI_Main` 73%, `GUI_Realtime` 69%. What is left is drag-to-move, drag-to-resize and code that branches on anchor-resolved geometry or real font metrics — all three need a layout/interaction model in the shared harness, written up as items 11–13 of `Tests/HARNESS_CONTRACT.md`.
  - Specs: `smoke` (loads and initializes cleanly on all six flavours, with no init warnings), `core` (lifecycle, events, slash commands, table pool, combat state), `minimap`, `colors`, `windoworder`, `zonefilters`, `fights`, `roster`, `deletion`, `locale`, `tracker` and `combatlog` (the combat-log pipeline and the whole dispatch table), `modes` (every display mode select → render → hover → click), `mainwindow`, `interactions` (dropdowns, formatting, detail tables, threat polling), `guiwindows` (graph, compare, death graph, reset, report, realtime, Titan Panel), `config`, `midnight` (12.0 secret values), `lazysync` (the sync protocol, asserted on the wire) and `guidepth` (graph series maths — integrate, normalize, stack, thin — plus compare-graph series and realtime window pooling).
  - `Tests` is excluded from the packaged zip.

### Packaging

- **Fixed `.pkgmeta` ignore patterns that were matching nothing.** The BigWigs packager matches with shell `case` globbing, which has no recursive `**` support, so `"**/*.ps1"` and `"**/*.bat"` never matched and `wow-version-replication.ps1` was shipping to players. They are now `"*.ps1"` / `"*.bat"`. The dot-prefixed entries (`.git`, `.github`, `.vscode`, `.claude`, `.luarc.json`, …) were no-ops — the packager prunes dotfiles unconditionally — and have been removed rather than left implying coverage they never provided.

### Implementation

- **`Recount.lua` captures the Blizzard category identifier.** `AceConfigDialog:AddToBlizOptions("Recount Blizz", "Recount")` returns `(frame, categoryID)`; the second value is stored as `Recount.BlizOptionsCategory`. This is version-agnostic by construction: on older AceConfigDialog builds (and clients without `C_SettingsUtil`) the library deliberately overrides `category.ID` to the category *name*, so the captured value is the string `"Recount"` and behaviour is unchanged; on newer builds the override is skipped and the captured value is Blizzard's generated numeric ID. `GUI_Minimap.lua` passes `Recount.BlizOptionsCategory or "Recount"` to both `Settings.OpenToCategory` and the legacy `InterfaceOptionsFrame_OpenToCategory` path, so the fallback still works if the panel registration ever fails.

- **Every locale file now registers through `ns.NewLocale` (`locales/Recount-LocaleCore.lua`).** AceLocale-3.0 keeps only the locale table matching `GetLocale()` (plus the enUS default) and discards the rest via `if not L then return end`, so a UI-language override had no strings to switch to. `ns.NewLocale(code, isDefault, silent)` records every `L[key] = value` into both `ns.Locales[code]` (always — so the override path has every language in memory) and AceLocale's table (only when it matches the client / is default — so auto-detect is unchanged). The 9 community locales (deDE, esES, esMX, frFR, ptBR, ruRU, koKR, zhCN, zhTW) were converted from the stock `LibStub("AceLocale-3.0"):NewLocale(...)` + `if not L then return end` header to `local _, ns = ...` / `local L = ns.NewLocale("<code>")`. (itIT, nlNL, thTH, filPH already used it.)
- **English is selectable too.** `Recount-enUS.lua` now routes through `ns.NewLocale("enUS", true, debug)`. enUS uses AceLocale's `L[key] = true` convention (the value *is* the key); for that case `ns.NewLocale` stores the key string itself in `ns.Locales` (AceLocale still receives `true`), so forcing English on a non-English client overlays real English text rather than the boolean `true`. The existing `debug` flag is forwarded as AceLocale's `silent` argument.
- **Load-time overlay (top of `Recount.lua`).** On load, if `RecountLanguage` is set and not `"auto"`, it copies `ns.Locales[override]` onto the shared `L` table before any other file captures `L[...]` into its own structures (mode list, option tables). `RecountLanguage` is a plain SavedVariable, readable at load before those captures happen. Keys missing from the chosen language keep the client/English fallback.
- **Dropdown labels.** Native-script names for Latin scripts (Deutsch, Español, Français…); CJK and Cyrillic carry an English hint in parentheses (`한국어 (Korean)`, `简体中文 (Chinese, CN)`, `繁體中文 (Chinese, TW)`, `Русский (Russian)`) because WoW's default Western fonts render those scripts as boxes on a non-native client; Thai is shown as `"Thai"` for the same reason.

### Notes

- The community translations (deDE, esES, esMX, frFR, ptBR, ruRU, koKR, zhCN, zhTW) are older WoWAce exports and are likely **partial** — untranslated and newer strings (Compare Graph, Midnight, etc.) fall back to English. They are now *selectable*, not necessarily *complete*.
- Every translation now stays resident in memory rather than only the client's locale — a small, intentional cost for the override feature.

### Multi-version safety

- Pure locale-layer + options change; no version-specific code paths. Identical on Classic Era, TBC, Wrath, Cata, MoP Classic, and retail (incl. Midnight). With the dropdown left on **Auto**, auto-detect is byte-for-byte unchanged.
- The minimap settings fix carries no client check of its own — it reads whatever identifier the installed AceConfigDialog registered, so it is correct on every flavor regardless of which settings backend that client runs.

### Files Changed

- `locales/Recount-LocaleCore.lua` — `ns.NewLocale` gains `silent` forwarding and key-as-value handling for the `= true` convention
- `locales/Recount-enUS.lua` — routed through `ns.NewLocale("enUS", true, debug)`
- `locales/Recount-{deDE,esES,esMX,frFR,ptBR,ruRU,koKR,zhCN,zhTW}.lua` — converted to the `ns.NewLocale` header
- `Recount.lua` — "Addon Language" dropdown expanded from 5 entries to all 15 (Auto + 14 languages); captures `Recount.BlizOptionsCategory` from `AddToBlizOptions`
- `GUI_Minimap.lua` — right-click opens the settings panel by category identifier instead of the hard-coded name
- `zonefilters.lua` — parenthesised the auto-hide condition in `SetZoneGroupFilter`
- `Fights.lua` — `DeleteOverflowFights` trims `FoughtWho` and the death log once, outside the per-combatant loop
- `colors.lua` — `GetColor` returns a copy of the client class colour instead of mutating it
- `WindowOrder.lua` — removed a dead `v:GetScript("OnMouseUp")` statement in `ScaleWindows` that fetched a handler and discarded it; `SetWindowTop` no longer indexes a nil `Below`
- `GUI_Detail_Midnight.lua` — the Midnight detail window registers with `AddWindow`
- `Recount.lua` — masked the affiliation test in `FindPetUnitFromFlags`; `OnDisable` unregisters events on `Recount.events`
- `GUI_Main.lua` — `AddGraphNameEntry` assigns into the label table instead of calling a non-existent `insert`
- `LazySync.lua` — `FlagSync` skips group members with no recorded data
- `Recount.lua` — `SetOwner` records the owner on the pet, not just the pet on the owner
- `Tests/` — new offline suite (see Testing above)
- `.pkgmeta`, `.luacheckrc`, `.busted`, `.luarc.json` — packaging and lint configuration for the suite

## [v1.18.3] (2026-06-10) - Retail Midnight (12.0) live damage meter display

### Fixed

- **Recount bars now populate live during combat on retail Midnight (12.0+).** This completes the work scaffolded in v1.18.1, where the addon loaded cleanly but its bars stayed empty because `C_DamageMeter` returns *secret* combat values. The v1.18.1/v1.18.2 approach — poll `C_DamageMeter.GetCombatSessionSourceFromType`, diff against a snapshot, feed deltas through `AddAmount` — could never work: it did arithmetic (`total - snapshot`) and comparison (`delta > 0`) on secret values, which is exactly what taints addon execution, so it skipped every secret and applied no data. That whole snapshot/diff path is removed.

- **New approach — display passthrough, no arithmetic.** The rule (verified in-game): an addon may *pass* a secret value straight into a display sink — `FontString:SetText`, `StatusBar:SetValue` / `SetMinMaxValues`, `AbbreviateNumbers` — and it renders live, mid-fight, with no error and no taint. What an addon must never do is *operate* on a secret (arithmetic, comparison, sort, percentage, total, string op) or route a secret into a **shared** frame (above all `GameTooltip`); either silently taints the running execution, and that taint then poisons whatever shared resource it next touches (the classic symptom is an unrelated Blizzard tooltip — e.g. world-map POIs — throwing "Secret values are only allowed during untainted execution"). `pcall` does **not** help and is never used to "guard" a secret: it catches the throw but leaves the taint in place, which is worse because it's silent.

### Implementation

- **`Tracker_Midnight.lua` rewritten** as a secret-safe renderer. On the `DAMAGE_METER_CURRENT_SESSION_UPDATED` / `DAMAGE_METER_COMBAT_SESSION_UPDATED` / `DAMAGE_METER_RESET` events (and via the periodic refresh, see below) it calls `C_DamageMeter.GetCombatSessionFromType(Enum.DamageMeterSessionType.Current, metric)` for the on-screen mode's metric and writes each `combatSources[i]` straight into the existing `Recount.MainWindow.Rows[i]` widgets: `LeftText:SetText(src.name)`, `RightText:SetText(AbbreviateNumbers(amount))`, `StatusBar:SetMinMaxValues(0, session.maxAmount)` + `SetValue(src.totalAmount)`. No value is ever computed on.
  - Uses the **session** API `GetCombatSessionFromType` (returns the whole `combatSources` array, pre-ranked) rather than the per-source `GetCombatSessionSourceFromType` the v1.18.1 scaffolding used.
  - Field secrecy honoured per the API docs: `name` / `totalAmount` / `amountPerSecond` and session `maxAmount` are secret in combat (passed through, never computed on); `classFilename`, `specIconID`, `classification`, `isLocalPlayer`, `deathRecapID`, `sourceGUID` are `NeverSecret` (used directly — class colour comes from `classFilename`).
  - Bar order is the API's pre-ranked order (we can't sort by a secret value). No Total bar and no percentages on Midnight (both need addition). `#combatSources` is a plain count, safe for scrollbar maths and row indexing.
  - Each Midnight row's `OnEnter` / `OnLeave` / `OnClick` handlers are stripped once, so a secret value can never reach the shared `GameTooltip` via a bar tooltip.
  - Mode → metric map (matched by English mode label): Damage Done → `DamageDone`, DPS → `DamageDone` (per-second text), Damage Taken → `DamageTaken`, Healing Done → `HealingDone`, Absorbs → `Absorbs`, Deaths → `Deaths`. Modes with no `C_DamageMeter` source (Friendly Fire, Healing Taken, Overhealing, DOT/HOT Uptime, Activity, Threat) render blank.

- **`GUI_Main.lua`** — added `local WOW_RETAIL` / `local WOW_RETAIL_MIDNIGHT` upvalues (same expression as `Recount.lua`) and a single guarded early-return at the top of `RefreshMainWindow`: `if WOW_RETAIL_MIDNIGHT and Recount.RefreshMainWindow_Midnight then return Recount:RefreshMainWindow_Midnight(datarefresh) end`. On every other client this `if` is false and `RefreshMainWindow` runs byte-for-byte as before. Routing through the existing periodic refresh means the bars also keep updating between events. Also cached `C_PetBattles` as a file-local upvalue (was referenced unqualified at line 661).

- **`.luarc.json`** — added `AbbreviateNumbers`, `LOCALIZED_CLASS_NAMES_MALE`, `canaccessvalue`, and a batch of pre-existing WoW globals that were triggering `undefined-global` warnings across the project (`BackdropTemplateMixin`, `C_PetBattles`, `UnitGUID`, `UnitHealth`, `UnitHealthMax`, `UnitIsPlayer`, `UnitIsConnected`, `UnitIsVisible`, `UnitAffectingCombat`, `UnitCanAttack`, `UnitDetailedThreatSituation`, `UnitIsFeignDeath`, `GetScreenHeight`, `UIFrameFade`, `GetMouseButtonClicked`, `GetFramerate`, `GetLocale`, `GetNetStats`, `GetNumDeclensionSets`, `GetChannelList`, `GetZonePVPInfo`, `BNGetNumFriends`, `BNGetSelectedFriend`, `Ambiguate`, `DeclineName`, `debugstack`, `strsplit`, `ChatThrottleLib`).

- **`.pkgmeta`** — fixed the `ignore` entries so `docs/` is actually excluded from the CurseForge zip. The packager appends `/*` to directory entries, so a trailing slash produced `docs//*` which matched nothing and silently shipped the folder. Removed the trailing slash from `docs`, `.git`, `.github`, `.vscode`; added `.claude`; documented the rule in a comment.

### Multi-version safety

- Everything keys off `WOW_RETAIL_MIDNIGHT` (`WOW_PROJECT_MAINLINE` and build >= 120000). Classic Era, TBC, Wrath, Cata, MoP Classic, and **pre-12.0 retail (11.x)** are untouched — they never load the Midnight code path and `RefreshMainWindow` is unchanged for them.

### Known limitations on Midnight

- During an instance encounter / Mythic+ / PvP match the values are passed through and display live; views Blizzard exposes no data for stay blank (listed above). No Total bar, no percentages, and bars are non-interactive (no click-to-detail / graph) on Midnight, because those paths need to read the underlying numbers or open a tooltip.

### Files Changed

- `Tracker_Midnight.lua` — rewritten as the secret-safe display-passthrough renderer; old snapshot/diff `AddAmount` path removed
- `GUI_Main.lua` — `WOW_RETAIL` / `WOW_RETAIL_MIDNIGHT` upvalues, guarded `RefreshMainWindow` hook, `C_PetBattles` local
- `.luarc.json` — added the secret-value globals and a batch of pre-existing WoW globals to `diagnostics.globals`
- `.pkgmeta` — fixed `docs/` (and other directory) ignore globs so docs are excluded from the package

## [v1.18.2] (2026-05-16) - Bug fixes

### Bug Fixes

- **Prayer of Mending now credits the priest, not the unit being healed.** Reported by a user: PoM heals were being attributed to the target rather than the healer. Root cause: Blizzard's combat log reports the buffed unit as the source of the `SPELL_HEAL` proc (spell ID 33110) — `srcGUID` and `dstGUID` are both the target — so Recount was attributing every PoM tick to whoever happened to be wearing the buff. Fix landed in `Tracker.lua`:
  - New module-local tables `PoMAuraSpellId = {[41635] = true}`, `PoMHealSpellId = {[33110] = true}`, and `PoMOrigCaster = {}`. The aura ID is the bouncing PoM buff; the heal ID is the heal-on-damage proc; the table is keyed by the GUID currently wearing the buff and stores `{srcGUID, srcName, srcFlags}` of the original priest.
  - `Recount:SpellAuraApplied` and `Recount:SpellAuraRefresh` write `PoMOrigCaster[dstGUID]` whenever a PoM aura lands or refreshes. The buff naturally rewrites the table entry as it bounces between targets (fresh `SPELL_AURA_APPLIED` events from the priest each hop).
  - `Recount:SpellAuraRemoved` clears `PoMOrigCaster[dstGUID]` when the buff falls off.
  - `Recount:SpellHeal` checks `PoMHealSpellId[spellId]` at the top of the function; if matched and `PoMOrigCaster[srcGUID]` exists, it swaps `srcGUID`, `srcName`, `srcFlags` to the recorded priest *before* dispatching to the existing `AddHealData` path. All downstream attribution (Healing Done, HealedWho, WhoHealed, overhealing, time-heal, etc.) now records the priest correctly with zero changes to the heal-tracking code itself.
  - PoM does not exist on Classic Era (Vanilla 1.x), so the lookups are a no-op there — no version guard required. Applies on TBC Classic, Wrath Classic, Cata Classic, MoP Classic, and Retail (where PoM uses the same spell IDs 41635 / 33110).

## [v1.18.1] (2026-05-05) - Retail Midnight (12.0) support via C_DamageMeter

### Bug Fixes

- **Window color picker fixed on Classic Era and other Classic flavors.** Reported by a user: "any chance of fixing the feature to change window colours?". Two bugs in one — both fixed:
  1. The picker code in `colors.lua` branched on `WOW_RETAIL` to choose between the new (Dragonflight-era) `ColorPickerFrame.Content.ColorPicker` API and the old `OpacitySliderFrame` / `ColorPickerFrame.func` API. But the new picker has since rolled out to every Classic flavor too — Vanilla Classic 11507/11508, Cata Classic, Wrath Classic, MoP Classic — leaving Classic clients in a half-migrated state where `swatchFunc` was set on Vanilla but the alpha read still went through the long-removed `OpacitySliderFrame` (which is `nil`). Replaced every `WOW_RETAIL`/`WOW_VANILLA_CLASSIC`/`WOW_PANDA_CLASSIC` flag check inside the picker with a runtime test for `ColorPickerFrame.Content and ColorPickerFrame.Content.ColorPicker`.
  2. Per-field assignment of `swatchFunc` / `opacityFunc` / `cancelFunc` on `ColorPickerFrame` followed by `:Show()` is silently dropped on the new picker — the OkayButton's OnClick reads from the info table the picker captured during setup, not from the frame's fields. Confirmed in-game: pressing OK on the new picker threw `attempt to call field 'swatchFunc' (a nil value)` from Blizzard's `ColorPickerFrame.xml:79_OnClick`. Refactored `Colors:EditColor` to use `ColorPickerFrame:SetupColorPickerAndShow({r=, g=, b=, opacity=, hasOpacity=, swatchFunc=, opacityFunc=, cancelFunc=})` on the new picker (the documented Dragonflight+ pattern); the old per-field-then-Show path is preserved verbatim for any pre-Dragonflight client that still uses it. Position-relative-to-Attach moved to after Setup since the new picker re-anchors during its own setup.

  3. The first new-picker detector tested for `ColorPickerFrame.Content.ColorPicker`, but that field returned nil on at least Classic Era 11507/11508 even though the new-style OkayButton (which reads `swatchFunc`) was active — `SetupColorPickerAndShow` was never called and the second OK click reproduced the same error. Switched the detector to test for `ColorPickerFrame.SetupColorPickerAndShow` directly (the canonical 10.2.5+ method); if that method exists, the info-table contract is in force.

  4. Alpha reads in `Color_Change` and `Opacity_Change` previously reached into `ColorPickerFrame.Content.ColorPicker:GetColorAlpha()`. Switched to the documented top-level `ColorPickerFrame:GetColorAlpha()` so the same code works regardless of inner widget naming differences across Classic flavors.

  5. `Color_Cancel` no longer manually rewinds the picker's internal opacity slider — `Colors:SetColor(Cur_Branch, Cur_Name, PreviousColor)` already re-paints the registered visual elements via `UpdateColor`, and the picker frame is closing anyway. Removes the last `ColorPickerFrame.Content.ColorPicker` reference from the file.

  Also removed three now-unused project-flag locals from `colors.lua` (`WOW_RETAIL`, `WOW_VANILLA_CLASSIC`, `WOW_PANDA_CLASSIC`) and the dangling MoP-only `swatchFunc = func` post-Show fallback.

- **No more `ADDON_ACTION_FORBIDDEN` Lua error at login on retail Midnight (12.0).** A user reported `25x [ADDON_ACTION_FORBIDDEN] AddOn 'Recount' tried to call the protected function 'Frame:RegisterEvent()'` traced to `Recount.lua:1868` (the `Recount.events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")` call inside `OnEnable`). Root cause: in patch 12.0, Blizzard removed addon access to `COMBAT_LOG_EVENT_UNFILTERED` unconditionally. The call now fires `ADDON_ACTION_FORBIDDEN` in every context, including at login outside any combat / encounter / instance. Two prior research dead-ends ruled out before landing the real fix: (1) `C_RestrictedActions.IsAddOnRestrictionActive(0..3)` is not a useful gate — it reports "no restrictions" at login while the underlying call is still blocked. (2) `pcall` does not help — `ADDON_ACTION_FORBIDDEN` is dispatched asynchronously by Blizzard, not raised at the call site.

### Retail Midnight scaffolding (data path NOT yet functional — tracked for v1.18.2)

- **New file `Tracker_Midnight.lua`** (loaded only on Mainline TOC, never on Classic flavors) is the intended CLEU-free data path. Subscribes to `DAMAGE_METER_CURRENT_SESSION_UPDATED`, `DAMAGE_METER_COMBAT_SESSION_UPDATED`, and `DAMAGE_METER_RESET`. On each session update, polls `C_DamageMeter.GetCombatSessionSourceFromType(Current, metric, GUID)` for every group member and *would* compute per-(player, datatype) deltas against a snapshot table, feeding them through the existing `Recount:AddAmount(combatant, datatype, amount)` so the rest of Recount (modes, fight history, bars, reports, etc.) works unchanged.
- **In-game test outcome on retail Midnight (12.0.5.67314):** `source.totalAmount` reads always come back as *secret number values* — not just during combat as the wiki's `SecretWhenInCombat` annotation suggested, but also after combat. Tainted addon code can hold a secret value but cannot do arithmetic on it (`"attempt to perform arithmetic on local 'total' (a secret number value, while execution tainted by 'Recount')"`). The first iteration of `Tracker_Midnight.lua` threw this Lua error every combat. The current iteration uses `issecretvalue(total)` to skip the metric and does NOT update the snapshot when the value is secret — eliminates the Lua error, but post-combat reads also come back secret in practice, so no deltas are ever applied and the Recount bars stay empty on retail Midnight.
- **Net v1.18.1 effect on retail Midnight:** addon loads cleanly, no Lua errors, settings / minimap / Titan Panel all work, but combat data does not populate. v1.18.2 will pursue the workaround — likely involving Skada's `SecretValueHelper.lua` pattern or finding a non-tainted code path the wiki documents elsewhere.
- **Self-help warning kept in place:** if `C_DamageMeter.IsDamageMeterAvailable()` returns false (in-game damage meter setting is OFF), Recount emits a yellow chat message at login telling the user to enable it under `Options > Gameplay Enhancements > Damage Meter`. (Won't matter until the secret-value problem is solved, but the warning is harmless and the setting is needed regardless.)

### Implementation

- **`Recount.lua` top-of-file** — added `local WOW_RETAIL = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE` (matching the convention in `colors.lua`) and `local WOW_RETAIL_MIDNIGHT = WOW_RETAIL and ((select(4, GetBuildInfo()) or 0) >= 120000)`. `GetBuildInfo` and `select` cached as locals per project convention.

- **`Recount.lua` new dispatcher `Recount:RegisterCombatLogEvent`** — on Midnight, calls `Recount:RegisterCombatLogEvent_Midnight()` (defined in `Tracker_Midnight.lua`). On every other client, calls `Recount.events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")` exactly as before.

- **`Recount.lua` `OnEnable`** — line 1868 changed from `Recount.events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")` to `Recount:RegisterCombatLogEvent()`. The `INSTANCE_ENCOUNTER_ENGAGE_UNIT` registration on the next line is unchanged — that event is not subject to the CLEU restriction.

- **`Tracker_Midnight.lua` (new file)** — implements `Recount:RegisterCombatLogEvent_Midnight()`, the `Recount:DAMAGE_METER_*` event handlers, and the snapshot/diff polling. Uses synthesized `COMBATLOG_OBJECT_*` flags (Self/Party/Raid + Player + Friendly + ControlPlayer) when calling `Recount:AddCombatant` since real CLEU flags aren't available on this code path. Every `C_DamageMeter` call is wrapped in `pcall`, including the field access on the returned struct (the `DamageMeterCombatSessionSource` is marked `SecretWhenInCombat`).

- **Secret-value handling** — confirmed in-game on retail Midnight that `source.totalAmount` reads return *secret number values* during combat. Reading them does not throw, but arithmetic on them does (`"attempt to perform arithmetic on local 'total' (a secret number value, while execution tainted by 'Recount')"`). Worked around by checking `issecretvalue(total)` before any arithmetic and skipping the update when true. The snapshot is left alone in the secret case so the next non-secret read produces the correct delta against the last public total. Belt-and-suspenders `pcall` wraps the subtraction itself in case `issecretvalue` isn't reliable on a given build. Practical effect: bars don't tick up live during combat, but populate fully once the next post-combat session update fires.

- **`Recount_Mainline.toc`** — added `Tracker_Midnight.lua` immediately after `Tracker.lua`. The other four TOCs (`Recount.toc` for Classic Era, `Recount_BCC.toc`, `Recount_Wrath.toc`, `Recount_Cata.toc`) do NOT reference the new file, so Classic-flavor clients literally never load it. Zero risk of accidental cross-version interference.

- **`.luarc.json`** — added `GetBuildInfo` and `C_DamageMeter` to `diagnostics.globals`.

### Behavior

- **Pre-12.0 retail and all Classic flavors** — no behavior change. CLEU registers immediately at `OnEnable` exactly as before. `Tracker_Midnight.lua` is not loaded.
- **Midnight retail (12.0+)** — login Lua error fixed; addon loads cleanly. `Tracker_Midnight.lua` registers the `DAMAGE_METER_*` events but in practice every poll returns secret values that we cannot operate on, so the Recount bars stay empty until v1.18.2 lands an actual workaround for secret values.
- **No more login Lua error** in any scenario, including on retail Midnight.

### What's deferred to v1.18.2

- **Get retail Midnight bars actually populating.** The `Tracker_Midnight.lua` scaffolding is in place; the missing piece is a way to either (a) extract numeric values from secret-value returns, (b) call `C_DamageMeter` from a non-tainted execution path, or (c) display secret values directly via FontString widgets without the addon ever doing arithmetic. Likely path: study Skada's `SecretValueHelper.lua` (visible in `zarnivoop/skada` on GitHub) which is the only public reference for a working Midnight damage meter.
- **Tracker modules on Midnight retail.** Dispels, Interrupts, CC Breakers, Power Gains, Resurrections write to per-spell table-data structures (`AddTableDataStats`, `AddTableDataSum`) that don't have a 1:1 mapping to `C_DamageMeter`'s `combatSpells` array. Will need module-specific shims once the basic data path works.
- **Fight rotation alignment.** Recount's fight boundaries come from `PLAYER_REGEN_*` (still works on Midnight), but Blizzard's session reset cadence may not match exactly. If the snapshots and Recount's `CurrentFightData` get out of sync at fight boundaries, follow-up tuning is required.

### Files Changed

- `Recount.lua` — added Midnight version guard and the `RegisterCombatLogEvent` dispatcher; replaced the unconditional CLEU `RegisterEvent` call in `OnEnable`
- `Tracker_Midnight.lua` — **new file**, Midnight-only data collection via `C_DamageMeter`
- `Recount_Mainline.toc` — added `Tracker_Midnight.lua` to the load order
- `colors.lua` — replaced `WOW_RETAIL` / `WOW_VANILLA_CLASSIC` / `WOW_PANDA_CLASSIC` flag checks inside the color picker with a runtime test for the new `ColorPickerFrame.Content.ColorPicker` API; removed the three now-unused project-flag locals and the post-Show `swatchFunc = func` fallback
- `.luarc.json` — added `GetBuildInfo`, `C_DamageMeter`, and `issecretvalue` to `diagnostics.globals`

---

## [v1.17.5] (2026-04-29) - Fix Bars Not Appearing on First Launch

### Bug Fixes

- **Main window bars now render on first launch without needing a manual mode pick.** Three users reported installing Recount, entering combat, and seeing the window appear with no bars or numbers — the workaround was to right-click the title bar and pick a display mode from the dropdown. Root cause: `Recount.MainWindow.GetData` is the function pointer the 1-second refresh timer in `GUI_Main.lua:RefreshMainWindow` uses to read combat data, and it is only ever assigned inside `Recount:SetMainWindowMode`. That assignment normally happens during `OnInitialize` via the chain `SetupMainWindow → LoadMainWindowData → SetMainWindowMode(MainWindowMode or 1)`. If any earlier call in the `OnInitialize` Create chain (`CreateMainWindow → CreateDetailWindow → CreateGraphWindow → CreateFilterWeights → InitOrder → SetupMainWindow`) threw a Lua error, `SetupMainWindow` never ran, `GetData` stayed nil, and the timer-driven refresh silently early-returned forever. The right-click trick worked because picking a mode from the dropdown invokes `SetMainWindowMode` directly, bypassing the broken init path.

### Implementation

Two complementary additive fixes in `OnInitialize` and `RefreshMainWindow`:

- **`Recount.lua` `OnInitialize`** — the six-call init chain (`CreateMainWindow`, `CreateDetailWindow`, `CreateGraphWindow`, `CreateFilterWeights`, `InitOrder`, `SetupMainWindow`) is now individually wrapped in `pcall` via a local `safeInit` helper. A failure in any one step no longer prevents the others from running, so `SetupMainWindow` always gets a chance to bind `GetData`. Failures emit a yellow `|cffff8800Recount init warning:|r <step> failed: <error>` line to `DEFAULT_CHAT_FRAME` so users can screenshot and report the actual failing call instead of just "no numbers."

- **`GUI_Main.lua` `RefreshMainWindow`** — the function-entry gate `if not MainWindow.GetData or not MainWindow:IsShown() then return end` was split. The visibility check still early-returns. The `GetData` check now self-heals: if `GetData` is nil but `Recount.MainWindowData` has been populated, `RefreshMainWindow` calls `Recount:SetMainWindowMode(Recount.db.profile.MainWindowMode or 1)` to bind it before continuing. Worst case for the regression scenario: bars appear ~1 second later than they would on a healthy init (next timer tick instead of immediately). Healthy installs see no behaviour change.

### Files Changed

- `Recount.lua` — `OnInitialize` Create chain wrapped in `pcall` via local `safeInit` helper
- `GUI_Main.lua` — `RefreshMainWindow` now self-heals when `GetData` is nil but `MainWindowData` is loaded

---

## [v1.17.2] (2026-04-15) - Compare Graph Window

### New Features

- **Compare Graph window** — A new multi-series time-series graph window accessible from the main toolbar. Add any number of player + metric combinations as overlaid lines and compare them side by side. Supports all 14 tracked metrics: Damage Done, DPS, Friendly Fire, Damage Taken, Healing Done, Absorbs, Healing Taken, Overhealing, Deaths, DOT Uptime, HOT Uptime, Activity, Threat (TPS), and Threat (Total).

- **Fight Filter dropdown** — Restrict the compare graph to a single recorded combat encounter using the Fight dropdown. Selecting a fight clamps the X axis to that window; "All Fights" shows the full session timeline.

- **Per Fight mode** — A "Per Fight" checkbox renders each recorded fight as a continuous sawtooth line on a shared session timeline. Each fight rises from 0 as the metric accumulates then snaps back to 0 at fight end, with flat-zero gaps between pulls. Useful for comparing output across an entire raid session.

- **Crosshair cursor with live tooltip** — Hovering over the compare graph draws a vertical hairline at the cursor and shows a `ANCHOR_CURSOR` tooltip with the interpolated value of every active series at that X position. Values are linearly interpolated between 1-second samples and formatted as raw, `k`, or `m` depending on magnitude. The X header shows elapsed seconds since the fight/session start.

- **Normalize checkbox** — Scales each series independently to 0–100% so metrics with vastly different magnitudes (e.g. 640k threat vs 11k damage) can be visually compared on the same axis.

- **Integrate checkbox** — Converts per-second rate data (DPS, TPS) into cumulative totals over time. Metrics that are inherently cumulative (Damage Done, Healing Done, Threat Total, etc.) integrate automatically regardless of this checkbox.

### Improvements

- **Threat time-series units corrected** — `TimeData["Threat"]` now stores raw threat/s (matching `TimeData["Damage"]` units) instead of k-threat/s. After integration, Threat (Total) now correctly reaches the same magnitude shown on the bar chart (e.g. 614,000). Requires one fresh fight after updating; existing saved data will be on the old scale.

- **Compare graph dropdown fix** — `UIDropDownMenu_Initialize` was being called inside the Fight and Metric dropdown `OnEnter` handlers, causing dropdown lists to close as soon as the cursor moved toward them. Removed the re-initialize call from `OnEnter`; init functions already read live data on every open.

- **Compare graph tooltip anchor** — All three Compare window dropdowns (Player, Metric, Fight) changed from `ANCHOR_LEFT` to `ANCHOR_TOPRIGHT` so the hover tooltip no longer overlaps the dropdown list that opens to the left.

### Files Changed

- `GUI_CompareGraph.lua` — New file; full Compare Graph window implementation
- `TrackerModules/TrackerModule_Threat.lua` — TPS units corrected to raw threat/s
- `GUI_Main.lua` — Compare button added to main window toolbar

---

## [v1.17.1] (2026-03-31) - Minimap Button Toggle Option

### New Features

- **Minimap button toggle in settings** — A checkbox has been added to the Recount settings panel (Options > Addons > Recount) to show or hide the minimap button. The checkbox calls `Recount:ToggleMinimapButton(v)` and the state is persisted in `db.profile.minimapButton.hide` so it survives reloads and is character-agnostic.

### Files Changed

- `Recount.lua` — `toggle` entry added to `consoleOptions.args` for the minimap button visibility checkbox

---

## [v1.17.0] (2026-03-30) - Minimap Button & Titan Panel Integration

### New Features

- **Minimap button (LibDBIcon-1.0)** — A persistent minimap button is now registered via LibDataBroker-1.1 and LibDBIcon-1.0. Left-click toggles the main Recount window; Shift+Left-click toggles the configuration window; Right-click opens the WoW addon settings panel. Cross-version compatible: uses `Settings.OpenToCategory` on Interface 11508+ and falls back to `InterfaceOptionsFrame_OpenToCategory` on older clients. Button position and visibility are persisted per-profile in AceDB.

- **Titan Panel integration (LibDataBroker data source)** — A `data source` LDB object is registered under the name `Recount_Stats`. Any LDB display addon (Titan Panel, Bazooka, DockingStation, etc.) picks this up automatically. The plugin shows a live per-player stat (`DPS: 842`) updated every 1 second via `C_Timer.NewTicker`. Right-clicking opens a native `UIDropDownMenu` to switch between six display stats (DPS, Damage Done, HPS, Healing Done, Damage Taken, Deaths) and three datasets (Overall, Last Fight, Current Fight). Hovering shows a full tooltip with all six stats at once. The selected stat is persisted in `Recount.db.profile.titanPanel.stat`.

### Files Changed

- `GUI_Minimap.lua` — New file; LibDataBroker launcher + LibDBIcon-1.0 minimap button
- `GUI_TitanPanel.lua` — New file; LibDataBroker data source for Titan Panel / LDB displays
- `libs/LibDataBroker-1.1/LibDataBroker-1.1.lua` — New bundled library
- `libs/LibDBIcon-1.0/LibDBIcon-1.0.lua` — New bundled library
- `Recount.toc` (and all 4 flavor TOCs) — Added new lib scripts and GUI files
- `Recount.lua` — `InitMinimapButton()` and `InitTitanPanel()` called from `OnInitialize()`

---

## [v1.16.0] (2026-03-30) - CurseForge Publishing, Multi-Flavor TOCs & Code Quality

### New Features

- **CurseForge project integration** — Added `## X-Curse-Project-ID: 1499579` to all TOC files and `curseforge-project-id: 1499579` to `.pkgmeta`. Version field now uses the `Recount-v1.18.8` packager token so releases are automatically versioned on CurseForge upload. Interface version updated to `11508` (Season of Discovery / Classic Era).

- **Multi-flavor TOC support** — Added separate TOC files for each WoW client flavor following the standard BigWigs Packager / CurseForge naming convention:
  - `Recount_BCC.toc` — Burning Crusade Classic (Interface 20505)
  - `Recount_Wrath.toc` — Wrath of the Lich King Classic (Interface 30403)
  - `Recount_Cata.toc` — Cataclysm Classic (Interface 40400)
  - `Recount_Mainline.toc` — Retail / The War Within (Interface 110207, 120001, 120000)

- **CurseForge addon description** — Created `docs/Curseforge_Description.html` with a full formatted addon description for the CurseForge project page, covering all display modes, tracker modules, features, slash commands, and credits.

### Improvements

- **Ace3 externalized** — Removed bundled Ace3 library source files from the repository. Libraries are now declared as externals in `.pkgmeta` and fetched by the CurseForge packager at release time, keeping the repository lean and libraries up to date.

- **VersionCheck-1.0 integrated** — Added VersionCheck-1.0 as a dependency in Classic Era / BCC / Wrath / Cata TOC files for out-of-date addon notification. Omitted from the Mainline TOC where it is not applicable.

### Bug Fixes

- **`table.getn()` and `table.maxn()` deprecated calls removed** — Replaced all occurrences with the `#` length operator across `GUI_Config.lua`, `GUI_Detail.lua`, `GUI_Graph.lua`, and `GUI_Main.lua`. These calls produce errors in modern Lua 5.1 environments and generate lint warnings.

- **`GUI_Graph.lua` nil guard** — Added `Filtered and Filtered[1] and` guard before `#Filtered[1]` access to prevent nil indexing when `FilterDataByTime` or `DataCopy` returns nil. Also applied `or 0` fallback to `Filtered[1][#Filtered[1]]` and `Filtered[1][1]` arithmetic to prevent nil subtraction errors.

- **`GUI_Detail.lua` row type mismatch** — Changed `Row = ... or 0` to `Row = ... or {}` so the LSP correctly infers `Row` as a table, preventing false type errors when fields like `Row.Data` are accessed.

- **`zonefilters.lua` scenario type handling** — Refactored `C_Scenario.IsInScenario()` assignment to use a separate `scenarioType` variable with `or "none"` fallback before assigning to `instanceType`, resolving a type-mismatch lint error. Added `---@diagnostic disable-next-line: deprecated` suppression for the `GetZonePVPInfo` call which has no non-deprecated replacement in Classic Era.

- **`Tracker.lua` duplicate table keys** — Commented out duplicate spell ID entries `[1463]`, `[6229]`, and `[31000]` in the shield absorb duration table. Duplicate keys silently overwrite earlier values in Lua and generate lint warnings.

- **`TrackerModules/TrackerModule_CCBreakers.lua` argument count mismatch** — Added `extraSpellId` parameter to the `AddCCBreaker` function signature to match the 8-argument call site (previously declared with only 7 parameters).

### Internal

- **Lua Language Server configuration (`.luarc.json`)** — Added 40+ WoW API globals to suppress false "undefined global" warnings, including all `COMBATLOG_OBJECT_*` filter constants, `CombatLogGetCurrentEventInfo`, `GetSpellInfo`, `BNGetFriendInfo`, `BNSendWhisper`, `LE_PARTY_CATEGORY_INSTANCE`, `InterfaceOptionsFrame`, `ColorPickerFrame`, `C_Scenario`, `RecountDeathTrack`, `RecountTempTooltip`, and WoW project version constants. Added `"duplicate-set-field"` to `diagnostics.disable`.

- **markdownlint `.pkgmeta` suppression** — Added `**/.pkgmeta` to both `.markdownlintignore` and `.vscode/settings.json` `markdownlint.ignore` to prevent YAML comment lines (`# comment`) from triggering false markdown heading warnings.

---
