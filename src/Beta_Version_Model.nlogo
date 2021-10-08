globals
[
  k
  t
  z
  cop-defect-threshold
  a1
  a2
  a3
  a4
  c1
  c2
]

breed [rebels rebel]
breed [cops cop]

turtles-own
[
  movement-patch
  active-in-vision
]

rebels-own
[
  jailed?
  active?
  r-hardship
  grievance
  risk-aversion
  arrest-probability
  cops-in-vision
  net-risk
  jail-time
  perceived-legitimacy
  team
]

cops-own
[
  target
  c-hardship
  c-grievance
  c-bias
  c-greed
  c-tendency-greed
  c-tendency-grievance
  c-tendency-avg
  c-prob-defect
  not-defected?
]

patches-own
[
  distance-from-nearest-cop
  movement-value
  area-value
  total-value
]

to setup
  clear-all
  if initial-rebel-density + initial-cop-density >= 1.0 [ error "Population density + Cop density should not be equal to or larger than 1.0" stop ]
  set k 2.3
  set t 0.1
  set z 1.8
  set a1 0.2
  set a2 0.2
  set a3 0.25
  set a4 0.35
  set c1 0.6
  set c2 0.4
  ifelse area-seed = 0 [random-seed new-seed] [random-seed area-seed]
  set cop-defect-threshold 0.7
  setup-patches
  setup-turtles
  random-seed new-seed
  reset-ticks
end

to setup-turtles
  set-default-shape turtles "circle"
  create-rebels initial-rebel-density * count patches
  [
    move-to one-of patches with [not any? turtles-here]
    set color blue
    set size 0.9
    set jailed? false
    set active? false
    set r-hardship random-float 1
    set risk-aversion random-float 1
    if rebel-perceived-legitimacy?
    [
      set perceived-legitimacy random-normal legitimacy 0.1
      if perceived-legitimacy > 1.0 [ set perceived-legitimacy 1.0 ]
      if perceived-legitimacy < 0.0 [ set perceived-legitimacy 0.0 ]
    ]

  ]

  ;; Initialize friend groups
  ask n-of (count rebels / 4) rebels with [ team = 0 ] [
    set team 1
    if rebel-movement = "Custom" and friends? [
      set color blue
      set shape "team-one"
    ]
  ]
  ask n-of (count rebels / 4) rebels with [ team = 0 ] [
    set team 2
    if rebel-movement = "Custom" and friends? [
      set color blue
      set shape "team-two"
    ]
  ]
  ask n-of (count rebels / 4) rebels with [ team = 0 ] [
    set team 3
    if rebel-movement = "Custom" and friends? [
      set color blue
      set shape "team-three"
    ]
  ]
  ask n-of (count rebels / 4) rebels with [ team = 0 ] [
    if rebel-movement = "Custom" and friends? [
      set color blue
      set shape "team-four"
    ]
  ]

  ;; non-defection cop candidates
  create-cops floor((initial-cop-density * (100 - defect-cop-candidates-percent) / 100) * count patches)
  [
    move-to one-of patches with [not any? turtles-here]
    set color black
    set size 0.9
    set c-hardship random-float 0.5
    set c-bias random-float 0.7
    set c-greed random-float 0.5
    set not-defected? true
  ]

  ;; plausible defection cop candidates
  create-cops ceiling(initial-cop-density * (defect-cop-candidates-percent / 100) * count patches)
  [
    move-to one-of patches with [not any? turtles-here]
    set color black
    set size 0.9
    set c-hardship 0.5 + random-float 0.5
    set c-bias 0.7 + random-float 0.3
    set c-greed 0.5 + random-float 0.5
    set not-defected? true
  ]
end

to setup-patches
  ask patches [
    set pcolor 39
    set movement-value 0
    set area-value 0
  ]

  ;; area-values are always set in case the areas are switched on later
  ask n-of 6 patches [  ;; Retail shop
    ask patches in-radius 1.5 [
      if rebel-movement = "Custom" and add-areas? [ set pcolor 58 ]
      set area-value 4
    ]
  ]
  ask n-of 3 patches with [ area-value = 0 ] [  ;; Government building
    ask patches in-radius 1.5 [
      if rebel-movement = "Custom" and add-areas? [ set pcolor 53 ]
      set area-value 10
    ]
  ]
  ask n-of 2 patches with [ area-value = 0 ] [  ;; Police station
    ask patches in-radius 1.5 [
      if rebel-movement = "Custom" and add-areas? [ set pcolor 44 ]
      set area-value -10
    ]
  ]
  ask n-of 2 patches with [ area-value = 0 ] [  ;; Park
    ask patches in-radius 2.9 [
      if rebel-movement = "Custom" and add-areas? [ set pcolor 55 ]
      set area-value 6
    ]
  ]
end

to go
  rebel-rule
  cop-rule
  update-view
  tick
end

to rebel-rule  ;; The rebel rule: first rebels move, then they turn active or quiet
  ask rebels
  [
    ifelse jail-time = 0    ;; Only if the rebel is not jailed will the rebel do things
    [
      set jailed? false

      ;; Move
      if rebel-movement != "Off"
      [
        rebel-movement-rule
        if movement-patch != nobody
        [move-to movement-patch]
      ]

      ;; Ask nearby rebels about their perceived legitimacy
      if rebel-perceived-legitimacy? [
        set perceived-legitimacy (perceived-legitimacy + [ perceived-legitimacy ] of one-of rebels in-radius rebel-vision) / 2
      ]

      ;; Become active/quiet

      ifelse rebel-perceived-legitimacy?
      [ set grievance r-hardship * (1 - perceived-legitimacy) ]                                         ;; G = H(1-L)
      [ set grievance r-hardship * (1 - legitimacy) ]
      set cops-in-vision count (cops-on patches in-radius rebel-vision) with [not-defected? = true]                            ;; C
      set active-in-vision 1 + count (rebels-on patches in-radius rebel-vision) with [ active? = true and jailed? = false]     ;; A
      set arrest-probability 1 - exp ( - k * floor (cops-in-vision / active-in-vision))                 ;; P = 1 - exp[-k(C/A)]
      set net-risk risk-aversion * arrest-probability                                                   ;; N = RP
      ifelse grievance - net-risk > t [ become-active ] [ become-quiet ]                                ;; If G - N > T, become active
    ]
    [
      set jail-time jail-time - 1  ;; decrease the jail time each tick if the rebel is jailed
    ]
   ]
end

to cop-become-non-defect ;; Change a cop from defection to non-defection
  set color black
  set not-defected? true
end

to cop-become-defect  ;; Change a cop to defect based on grievance
  set color lime
  set not-defected? false
end

to become-active  ;; Change a rebel to active
  set color red
  set active? true
end

to become-quiet ;; Change a rebel to quiet
  set color blue
  set active? false
end

to cop-rule ;; The cop rule: first, a cop moves, then they possibly defect, then, if they have not defected, they arrest a nearby active rebel
  ask cops [

    ;; Move
    if cop-movement != "Off"
      [
        cop-movement-rule
        if movement-patch != nobody
        [move-to movement-patch]
      ]

    ;; Defect (or not)
    set c-tendency-greed (1 - cop-benefits) * c-greed
    set c-tendency-grievance c-hardship * (1 - cop-perceived-legitimacy)
    set c-tendency-avg (c-tendency-greed + c-tendency-grievance) / 2
    set c-prob-defect 1 - exp(- z * floor(c-bias / (1 - c-tendency-avg)))

    ifelse c-prob-defect > cop-defect-threshold
    [cop-become-defect]
    [cop-become-non-defect]

    ;; Arrest active rebel (if there is one in vision)
    if not-defected?
    [
      set target one-of (rebels-on patches in-radius cop-vision) with [ active? = true and jailed? = false ]
      ifelse target != nobody
      [ set movement-patch target arrest-target ]
      [ set movement-patch one-of patches in-radius cop-vision with [not any? cops-here and not any? rebels-here with [ jailed? = false ]]]
      if cop-movement != "Off"
      [
        if movement-patch != nobody [ move-to movement-patch ]
      ]
    ]
  ]
end

to arrest-target  ;; A cop arrests an active rebel
  ask target [
    set jailed? true
    set active? false
    set color gray
    ifelse maximum-jail-time = "Infinity"
    [set jail-time random 2147483647]                ;; As close to infinity as we can get
    [set jail-time random maximum-jail-time-years]
   ]
end


to rebel-movement-rule ;; There are several options for rebel movement

  if rebel-movement = "Random" [ ;; The rebel moves to a random patch in vision
    set movement-patch one-of patches in-radius rebel-vision with [not any? cops-here and not any? rebels-here with [ jailed? = false ] ]
  ]

  if rebel-movement = "Avoidance" [ ;; The rebel stays as far away from cops as possible
    let current-distance-from-cop [ distance-from-nearest-cop ] of patch-here
    set movement-patch one-of patches in-radius rebel-vision with [not any? cops-here and not any? rebels-here with [ jailed? = false ] and distance-from-nearest-cop >= current-distance-from-cop]
  ]

  if rebel-movement = "Custom" [ ;; The user of the model can choose what things to take into account for the rebel movement
    ask patches in-radius rebel-vision with [ not any? cops-here and not any? rebels-here with [ jailed? = false ] ][
      let current-team [ team ] of myself

      let friends-in-new-vision 0
      ( ifelse current-team = 0 [ set friends-in-new-vision 0 ]
        current-team = 1 [ set friends-in-new-vision count rebels in-radius 2 with [ team = 1 and jailed? = false ] ]
        current-team = 2 [ set friends-in-new-vision count rebels in-radius 2 with [ team = 2 and jailed? = false ] ]
        current-team = 3 [ set friends-in-new-vision count rebels in-radius 2 with [ team = 3 and jailed? = false ] ]
        current-team = 4 [ set friends-in-new-vision count rebels in-radius 2 with [ team = 4 and jailed? = false ] ]
      )

      let distance-to-patch distance myself

      ifelse add-areas? [ set total-value a1 * area-value ] [ set total-value 100 ]
      if distance-to-patch? [ set total-value total-value - a2 * distance-to-patch ]
      if friends? [ set total-value total-value + a3 * friends-in-new-vision ]
      if avoid-cops? [ set total-value total-value + a4 * distance-from-nearest-cop ]

      ;; if all settings are enabled, the formula looks like this: a1 * area-value - a2 * distance-to-patch + a3 * friends-in-new-vision + a4 * distance-from-nearest-cop
    ]
    let current-distance-from-cop 0
    if avoid-cops? [ set current-distance-from-cop [ distance-from-nearest-cop ] of patch-here ]
    set movement-patch max-one-of patches in-radius rebel-vision with [not any? cops-here and not any? rebels-here with [ jailed? = false ] and distance-from-nearest-cop >= current-distance-from-cop ] [ total-value ]
  ]
end

to cop-movement-rule ;; There are several options for cop movement

  if cop-movement = "Random" [ ;; The cop moves to a random patch in vision
    set movement-patch one-of patches in-radius rebel-vision with [not any? cops-here and not any? rebels-here with [ jailed? = false ] ] ]

  if cop-movement = "Custom" [ ;; The user of the model can choose what things to take into account for the cop movement
    ask patches in-radius cop-vision [
      let cops-in-new-vision count cops-on patches in-radius cop-vision
      let active-in-new-vision count rebels-on patches in-radius cop-vision
      let active-rebel-density active-in-new-vision / cops-in-new-vision
      let distance-to-patch distance myself

      ifelse active-rebel-density? [ set total-value c1 * active-rebel-density ] [ set total-value 100 ]
      if distance-to-patch-cop? [ set total-value total-value - c2 * distance-to-patch ]

      ;; if all settings are enabled, the formula looks like this: c1 * active-rebel-density - c2 * distance-to-patch
    ]
    set movement-patch max-one-of patches in-radius cop-vision with [not any? cops-here and not any? rebels-here with [ jailed? = false ] ] [ total-value ]
  ]
end

to update-view           ;; Update the view in case of changed parameters
  update-patches
  update-rebels
end


to update-patches
  ask patches [
    set distance-from-nearest-cop distance min-one-of cops [ distance myself ]
    ifelse heatmap?
    [ set pcolor scale-color orange distance-from-nearest-cop -10 10 ]
    [ set pcolor 39
      if rebel-movement = "Custom" and add-areas? [
        (ifelse
          area-value = 4 [ set pcolor 58 ]
          area-value = 10 [ set pcolor 53 ]
          area-value = -10 [ set pcolor 44 ]
          area-value = 6 [ set pcolor 55 ]
        )
      ]
    ]
  ]
end

to update-rebels
  ask rebels with [ active? = false and jailed? = false ] [ ;; Quiet rebels
    ifelse friends? and rebel-movement = "Custom"
    [
      set color blue
      (ifelse team = 1 [set shape "team-one"]
        team = 2 [set shape "team-two"]
        team = 3 [set shape "team-three"]
        team = 4 [set shape "team-four"]
        )
    ]
    [
      set color blue
      set shape "circle"
    ]
  ]
  ask rebels with [ active? = true and jailed? = false ] [  ;; Active rebels
    ifelse friends? and rebel-movement = "Custom"
    [
      set color red
      (ifelse team = 1 [set shape "team-one"]
        team = 2 [set shape "team-two"]
        team = 3 [set shape "team-three"]
        team = 4 [set shape "team-four"]
        )
    ]
    [
      set color red
      set shape "circle"
    ]
  ]
  ask rebels with [ jailed? = true ] [  ;; Jailed rebels
    set color gray
    ifelse friends? and rebel-movement = "Custom"
    [
      (ifelse team = 1 [set shape "team-one"]
        team = 2 [set shape "team-two"]
        team = 3 [set shape "team-three"]
        team = 4 [set shape "team-four"]
        )
    ]
    [
      set shape "circle"
    ]
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
931
55
1345
470
-1
-1
10.15
1
10
1
1
1
0
1
1
1
0
39
0
39
1
1
1
ticks
30.0

BUTTON
8
10
71
43
setup
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
9
56
230
89
initial-rebel-density
initial-rebel-density
0
1
0.7
0.01
1
NIL
HORIZONTAL

SLIDER
10
97
231
130
initial-cop-density
initial-cop-density
0
1
0.04
0.001
1
NIL
HORIZONTAL

SLIDER
11
147
232
180
legitimacy
legitimacy
0
1
0.8
0.01
1
NIL
HORIZONTAL

SLIDER
14
231
234
264
cop-vision
cop-vision
0
10
7.0
0.1
1
NIL
HORIZONTAL

SLIDER
13
187
233
220
rebel-vision
rebel-vision
0
10
7.0
0.1
1
NIL
HORIZONTAL

SLIDER
15
327
233
360
maximum-jail-time-years
maximum-jail-time-years
0
100
10.0
1
1
years
HORIZONTAL

CHOOSER
14
271
233
316
maximum-jail-time
maximum-jail-time
"Amount of years (see slider)" "Infinity"
0

BUTTON
85
11
148
44
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
499
24
902
286
Active Rebels
Time
Amount
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Active" 1.0 0 -2674135 true "" "plot count rebels with [ active? = true ]"
"Quiet" 1.0 0 -13345367 true "" "plot count rebels with [ active? = false ]"
"Jailed" 1.0 0 -7500403 true "" "plot count rebels with [ jailed? = true ]"

PLOT
498
296
906
530
Active Rebels 2
Time
Amount
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"default" 1.0 0 -2674135 true "" "plot count rebels with [ active? = true ]"

SWITCH
12
527
232
560
rebel-perceived-legitimacy?
rebel-perceived-legitimacy?
1
1
-1000

MONITOR
11
568
217
613
Average rebel perceived legitimacy
precision mean [ perceived-legitimacy ] of rebels 6
17
1
11

SLIDER
11
424
233
457
defect-cop-candidates-percent
defect-cop-candidates-percent
0
100
15.0
1
1
%
HORIZONTAL

SLIDER
15
373
233
406
cop-benefits
cop-benefits
0
1
0.8
0.01
1
NIL
HORIZONTAL

SLIDER
12
476
231
509
cop-perceived-legitimacy
cop-perceived-legitimacy
0
1
0.74
0.01
1
NIL
HORIZONTAL

MONITOR
563
543
684
588
defect-cop-candidates
ceiling(initial-cop-density * (defect-cop-candidates-percent / 100) * count patches)
17
1
11

MONITOR
694
544
842
589
non-defect-cop-candidates
floor((initial-cop-density * (100 - defect-cop-candidates-percent) / 100) * count patches)
17
1
11

MONITOR
854
545
920
590
total-cops
floor(initial-cop-density * count patches)
1
1
11

MONITOR
474
543
556
588
defected-cops
count cops with [ not-defected? = false ]
17
1
11

CHOOSER
244
101
480
146
rebel-movement
rebel-movement
"Off" "Random" "Avoidance" "Custom"
1

CHOOSER
245
397
480
442
cop-movement
cop-movement
"Off" "Random" "Custom"
1

SWITCH
246
55
480
88
heatmap?
heatmap?
1
1
-1000

SWITCH
256
213
412
246
avoid-cops?
avoid-cops?
0
1
-1000

SWITCH
256
260
413
293
add-areas?
add-areas?
0
1
-1000

SWITCH
255
307
414
340
distance-to-patch?
distance-to-patch?
0
1
-1000

SWITCH
255
353
414
386
friends?
friends?
0
1
-1000

SWITCH
277
504
449
537
active-rebel-density?
active-rebel-density?
0
1
-1000

SWITCH
276
550
450
583
distance-to-patch-cop?
distance-to-patch-cop?
0
1
-1000

TEXTBOX
267
18
471
60
Note: updates to the view only happen on setup or on the next tick
11
0.0
1

TEXTBOX
253
161
489
217
When setting the rebel-movement to Custom, these switches can be used to set the desired movement.
11
0.0
1

TEXTBOX
253
449
477
505
When setting the cop-movement to Custom, these switches can be used to set the desired movement.
11
0.0
1

INPUTBOX
423
288
488
348
area-seed
0.0
1
0
Number

TEXTBOX
424
237
491
300
Fill in 0 for random seed
11
0.0
1

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

team-four
false
9
Circle -13791810 true true 0 0 300
Circle -16777216 true false 30 30 240
Polygon -13791810 true true 45 60 285 105 195 285 45 120 60 60
Polygon -13791810 true true 15 165
Circle -13791810 true true 30 120 0
Polygon -13791810 true true 225 30 75 30 15 120 30 210 120 285 240 255 270 195 270 105 210 30 135 15 75 45 45 60 15 165 75 270 180 285
Circle -13791810 true true 60 195 0
Polygon -13791810 true true 60 75 30 195 90 285 210 300 210 210 60 75 30 165
Polygon -13791810 true true 120 15 60 75 210 120 270 105 255 45 120 15
Polygon -13840069 true false 105 105 165 45 210 45 210 255 165 255 165 90 105 150 105 105
Circle -13791810 true true 71 86 67
Circle -13791810 true true 60 15 60
Circle -13791810 true true 150 165 0
Circle -13791810 true true 195 120 0
Circle -13791810 true true 65 20 170
Circle -13791810 true true 39 99 192
Polygon -13840069 true false 75 90 120 45 195 45 225 90 135 210 240 210 240 240 105 240 105 180 195 90 180 75 120 75 105 90 75 90
Circle -13791810 true true 78 33 85
Circle -13791810 true true 9 69 192
Circle -13791810 true true 81 6 108
Circle -13791810 true true 113 8 134
Circle -13791810 true true 39 69 42
Circle -13791810 true true 95 125 170
Polygon -13840069 true false 105 60 210 60 210 105 165 150 210 180 210 240 105 240 105 210 180 210 135 180 135 135 180 90 180 75 120 75 105 60 105 75 150 75
Polygon -13840069 true false 105 45 210 45 210 75 105 75 105 45
Circle -13345367 true false 150 120 0
Circle -13791810 true true 39 24 192
Circle -13791810 true true 116 26 127
Circle -13791810 true true 89 134 153
Polygon -16777216 true false 120 45 75 135 210 135 210 105 135 105 180 15 135 15 120 45
Polygon -16777216 true false 210 105 255 105 255 135 210 135 210 105
Polygon -16777216 true false 195 75 195 240 225 240 225 75 195 75

team-one
false
9
Circle -13791810 true true 0 0 300
Circle -16777216 true false 30 30 240
Polygon -13791810 true true 45 60 285 105 195 285 45 120 60 60
Polygon -13791810 true true 15 165
Circle -13791810 true true 30 120 0
Polygon -13791810 true true 225 30 75 30 15 120 30 210 120 285 240 255 270 195 270 105 210 30 135 15 75 45 45 60 15 165 75 270 180 285
Circle -13791810 true true 60 195 0
Polygon -13791810 true true 45 60 15 180 75 270 195 285 195 195 45 60 15 150
Polygon -13791810 true true 105 15 45 75 195 120 255 105 240 45 105 15
Polygon -16777216 true false 105 105 165 45 210 45 210 255 165 255 165 90 105 150 105 105

team-three
false
9
Circle -13791810 true true 0 0 300
Circle -16777216 true false 30 30 240
Polygon -13791810 true true 45 60 285 105 195 285 45 120 60 60
Polygon -13791810 true true 15 165
Circle -13791810 true true 30 120 0
Polygon -13791810 true true 225 30 75 30 15 120 30 210 120 285 240 255 270 195 270 105 210 30 135 15 75 45 45 60 15 165 75 270 180 285
Circle -13791810 true true 60 195 0
Polygon -13791810 true true 60 75 30 195 90 285 210 300 210 210 60 75 30 165
Polygon -13791810 true true 120 15 60 75 210 120 270 105 255 45 120 15
Polygon -13840069 true false 105 105 165 45 210 45 210 255 165 255 165 90 105 150 105 105
Circle -13791810 true true 71 86 67
Circle -13791810 true true 60 15 60
Circle -13791810 true true 150 165 0
Circle -13791810 true true 195 120 0
Circle -13791810 true true 65 20 170
Circle -13791810 true true 39 99 192
Polygon -13840069 true false 75 90 120 45 195 45 225 90 135 210 240 210 240 240 105 240 105 180 195 90 180 75 120 75 105 90 75 90
Circle -13791810 true true 78 33 85
Circle -13791810 true true 9 69 192
Circle -13791810 true true 81 6 108
Circle -13791810 true true 113 8 134
Circle -13791810 true true 39 69 42
Circle -13791810 true true 95 125 170
Polygon -16777216 true false 105 60 210 60 210 105 165 150 210 180 210 240 105 240 105 210 180 210 135 180 135 135 180 90 180 75 120 75 105 60 105 75 150 75
Polygon -16777216 true false 105 45 210 45 210 75 105 75 105 45

team-two
false
9
Circle -13791810 true true 0 0 300
Circle -16777216 true false 30 30 240
Polygon -13791810 true true 45 60 285 105 195 285 45 120 60 60
Polygon -13791810 true true 15 165
Circle -13791810 true true 30 120 0
Polygon -13791810 true true 225 30 75 30 15 120 30 210 120 285 240 255 270 195 270 105 210 30 135 15 75 45 45 60 15 165 75 270 180 285
Circle -13791810 true true 60 195 0
Polygon -13791810 true true 45 60 15 180 75 270 195 285 195 195 45 60 15 150
Polygon -13791810 true true 120 15 60 75 210 120 270 105 255 45 120 15
Polygon -13840069 true false 105 105 165 45 210 45 210 255 165 255 165 90 105 150 105 105
Circle -13791810 true true 71 86 67
Circle -13791810 true true 60 15 60
Circle -13791810 true true 150 165 0
Circle -13791810 true true 195 120 0
Circle -13791810 true true 95 35 170
Circle -13791810 true true 39 99 192
Polygon -16777216 true false 75 90 120 45 195 45 225 90 135 210 240 210 240 240 105 240 105 180 195 90 180 75 120 75 105 90 75 90

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.2.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
