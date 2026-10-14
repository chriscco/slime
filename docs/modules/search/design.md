# Search design

## Responsibility

`Search.rank` is a pure filter/ranking function: take windows ordered by MRU and a query, return matching windows ordered by match quality. Window enumeration, MRU maintenance, rendering, and selection belong to other modules. Search makes no system calls.

## Data and flow

`Window` is an immutable Core struct with pid, UInt32 windowID, appName, title, minimized state, and onscreen state. UInt32 avoids importing CoreGraphics into Core. `Window.label` is `appName — title`, or just appName for an empty title; display and search share this value.

1. An empty query returns the input unchanged.
2. Match each label greedily, case-insensitively, as a subsequence.
3. Sort matches by descending score, then ascending original index to retain MRU for ties.

Each matched character scores one base point, one for adjacency to the previous match, and one for a word boundary (start, whitespace, hyphen, em dash, or underscore). Adjacency and boundary bonuses have equal weight.

```swift
public static func rank(_ windows: [Window], query: String) -> [Window]
```

## Correctness assumptions

Input must already be MRU ordered; otherwise an empty query cannot put recently used windows first. Taking the earliest feasible match preserves subsequence feasibility, although its score need not be optimal where multiple alignments exist, such as `a_b_ab`. This can affect ranking but must not hide a valid match. Callers must use the shared label rather than independently constructing searchable text.

## Limits and UI integration

There is no position penalty, length normalization, optimal fzf-style alignment, or pinyin matching. Unicode lowercasing follows the standard library; special cases such as Turkish İ were not separately calibrated in the original implementation.

In 0.0.6, the panel shows explicit search focus and an immediately positioned end caret. The tap still owns the append/backspace filter; typing while holding Command makes the session persistent, and arrows navigate windows. No full text editor or IME integration is added. Search itself remains synchronous and pure. Skip unchanged grid/image work before introducing a debounce or background ranking; validate the 10/50/100-window release matrix first.
