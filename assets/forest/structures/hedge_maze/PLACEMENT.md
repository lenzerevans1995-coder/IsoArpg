# Hedge maze / city wall pieces

Tree B4 and Tree B5 are directional hedge-wall pieces for composing
maze structures and walled city sections. Each `_N/_S/_E/_W` variant
is a specific piece, not just a rotation.

## Bracket primitives

Two pieces combine into a `]` bracket with the opening facing the
player:

```
B5_W + B5_N  =  ┐  (top-right corner + top edge)
                │
                ┘
```

## Extending the bracket

Placing `B4_N` between `B5_W` and `B5_N` lengthens the top edge:

```
B5_W + B4_N + B5_N
```

`B4_E` and `B4_W` are the vertical wall segments for the left/right
sides of the maze.

## Closing into a square (maze with entrance)

```
B5_W + B4_N + B5_N
B4_E             B4_W
B5_S + B4_S + B5_E
```

Forms a square enclosure. Leaving any one piece out gives that side
an entrance.

## Biome usage

- `Tree B2 / B3` → city only (in `hedge_city/`).
- `Tree B4 / B5` → city + maze (in this folder).
- These should NEVER appear in the open-forest biome. They're
  templated structures that the generator only stamps inside city or
  maze regions.
