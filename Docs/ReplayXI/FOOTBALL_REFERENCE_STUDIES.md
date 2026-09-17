# Football reference studies

The featured catalogue now has five video-referenced scenes across two matches.
Three Strategy analysis scenes reference FIFA's [Argentina–France 2022 final broadcast](https://www.youtube.com/watch?v=RgqKdplLIk4).
Two Match replay scenes reference the official FA Cup [Manchester City–Liverpool quarter-final](https://www.youtube.com/watch?v=05ny1bmo-Kk).
Windows were checked in the browser, without downloading or bundling footage.
Legacy synthetic IDs/data remain available for saved reviews; they are no longer
featured beside the five referenced scenes and are not given false source labels.

## Verified video windows

| Scene | Video window | Direct observation |
|---|---|---|
| Counterattack, 36′ | [36:45–37:00](https://www.youtube.com/watch?v=RgqKdplLIk4&t=2205s) | 36:50 shows match35:15. At36:55/35:20, Mac Allister advances right and Di María is free left. Celebration by37:00. Captions name Álvarez then Mac Allister. |
| One-two volley, 81′ | [1:30:39–1:31:00](https://www.youtube.com/watch?v=RgqKdplLIk4&t=5439s) | Coman's recovery at1:30:44/80:45; Thuram in the combination at1:30:54/80:55; 2–2 celebration by1:30:59/81:00. |
| Rebound, 108′ | [2:09:39–2:10:00](https://www.youtube.com/watch?v=RgqKdplLIk4&t=7779s) | Build-up at2:09:45/107:49; shot/rebound with keeper down at2:09:50/107:54; celebration by2:09:55/107:59. |
| Overlap and header, 45+2′ | [46:26–46:48](https://www.youtube.com/watch?v=05ny1bmo-Kk&t=2786s) | Cherki releases Semenyo on the right; right-foot cross; Haaland header. |
| Underlap and cutback, 57′ | [59:34–59:51](https://www.youtube.com/watch?v=05ny1bmo-Kk&t=3574s) | Doku releases O’Reilly inside; left-foot cutback; Haaland checks and finishes left-footed. |

These are useful viewing windows, not exact contact-frame timestamps. Broadcast offsets differ across halves; match-minute labels cannot be used as video timestamps.

## Teaching objectives

- **Counterattack:** Molina → Mac Allister → Messi → Álvarez → Mac Allister → Di María. Release early, make the third-man run and preserve far-side width. The early Mac Allister layoff was corrected after a fresh source review.
- **One-two:** Coman recovery → Rabiot → Mbappé → Thuram → Mbappé. Keep running after the pass and meet the return before defenders reset. The [French federation report](https://www.fff.fr/selection/matchs/3181-argentine-france.html) describes Mbappé's headed exchange with Thuram and volley.
- **Rebound:** Lautaro → Messi → Fernández → Lautaro shot → Lloris parry → Messi right-foot finish. [FIFA's Fernández account](https://www.fifa.com/it/articles/enzo-fernandez-specialista-finali) corroborates the final release. The opening layoff and finishing foot were corrected against the official video.
- **City overlap:** release outside, cross before the recovering line settles, and attack across the centre-back.
- **City underlap:** hold width with the winger; release inside; striker checks away from his marker for the cutback.

The compact source badge is available beside the situation title and in the spatial
deck. It opens the main timestamped source and verified alternate replay angles.
See [second-match evidence](SECOND_MATCH_REFERENCE.md) for frames, alternate views,
match-specific rosters and remaining uncertainty.

## Tracking-data investigation

StatsBomb's public final-match event and 360 files exist, but are sparse event
snapshots, not full-body or continuous tracking. Their published user agreement
restricts redistribution and commercial exploitation; no raw files or coordinates
were bundled in the app or committed. Factual action corrections were independently
checked against the official video. PFF offers access to World Cup broadcast
tracking through a form; no user details were submitted and its licence/data
quality must be checked before integration. No open exact-match City–Liverpool
continuous tracking feed was found in the focused search.

## On-pitch rosters

Shirt-number sets, reconstructed from the starters and substitution events in the [official FIFA report, pages1–3](https://fdp.fifa.org/assetspublic/ce44/r2864/pdf/FullTimeMatchReport-English.pdf):

| Moment | Argentina | France |
|---|---|---|
| 36′ | 23, 26, 13, 19, 3, 24, 7, 20, 10, 9, 11 | 1, 5, 4, 18, 22, 8, 14, 7, 11, 9, 10 |
| 81′ | 23, 26, 13, 19, 3, 24, 7, 20, 10, 9, 8 | 1, 5, 4, 18, 25, 8, 14, 20, 12, 26, 10 |
| 108′ | 23, 4, 13, 19, 3, 24, 5, 20, 10, 22, 8 | 1, 5, 4, 18, 25, 8, 13, 20, 12, 26, 10 |

At108′, **Tagliafico #3 is still on**; De Paul #7 left at102′. **Fofana #13 replaced Rabiot #14 at96′.** Montiel #4 and Lautaro #22 are also on. Konaté does not replace Varane until113′. Array order is a convenient teaching layout, not measured formation.

## Reconstruction limits

The app authors its own coordinates, durations, supporting runs, body/head animation, contacts and neutral kits. These are **broadcast-inspired strategy studies**, not video-to-3D extraction, recovered tracking or exact replicas. Goal order, relevant identities and the explicitly checked striking feet above are source-backed. Full-body poses, gaze, incidental dribble feet and precise trajectories are not measured. Football timing may be compressed for the lesson, but the app must keep this distinction visible.

The corrected counterattack and rebound use versioned IDs. Their original IDs,
routes and contact timing remain available for existing saved annotations. Neither
an old save nor its marks are silently migrated onto the new action.

## Playback shortcuts

The existing previous/next icons beside Play step through admitted passes, receives, shots, headers and saves. Routine dribble touches are skipped. Each jump pauses at the exact native contact time without switching POV or editing annotations. Hover/accessibility details identify the action, shirt number, player and time. The controls do not wrap, and cannot interrupt drawing, scrubbing or geometry edits. Legacy scenes retain their original teaching-cue navigation; unprepared native studies never substitute intended beat times.

## Native scene inspection — earlier three-study checkpoint

`FootballReferenceStudyVisualTests` captures one actual Factory scene per study at its final recorded shooting contact. It uses the bundled player, pitch and ball assets and the native recording directly. The test verifies all planned contacts and goal entry, then renders a fixed attacking-third camera. Only the whole scene's room-placement transform is normalised; internal player/ball poses and labels remain unchanged. Colour, channel order and row direction use the existing native renderer calibration.

The three latest captures passed in `replayxi-native125-full-03` and were inspected in `/private/tmp/replayxi-native125-full-03-attachments`:

- Counterattack: `F2BC9998-4D2B-4670-BE90-9D4A6CE2281B.png`
- Volley: `A02ED33E-0FF3-4718-A26C-81A16EDF564A.png`
- Rebound: `864D869F-3425-416D-BB4F-BF5A72E9C824.png`

Pitch, goals, both teams, selected shirt numbers and final-shot locations are visible. The 512 px output has no antialiasing, so distant numbers and goal nets are jagged. Fine boot–ball alignment cannot be judged reliably at this scale; it has separate contact tests. These stills do not validate animation continuity, UI interaction, headset comfort or FM/EA-level visual fidelity.

The new visual test initially left optional player assets warm, changing later cold-fallback tests. Test-only cleanup now restores those resettable providers on success and failure. Full-03 confirmed isolation. The final full-04 run also passes: 1,046 XCTest cases, one optional skip, zero failures, plus both separate asset tests passing.
