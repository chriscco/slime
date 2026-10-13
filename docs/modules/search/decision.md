# Search decisions

## 2026-10-11 · Greedy subsequence matching and explicit stable tie-breaking

- **Context:** Window search needs to select the intended title from a few dozen candidates. fzf-style position penalties, normalization, and boundary weights would need tuning for little demonstrated benefit.
- **Decision:** Greedily take the earliest match from left to right. Score base, adjacent, and word-boundary matches; explicitly sort by `(score descending, original index ascending)` to preserve MRU ties.
- **Alternatives rejected:** Optimal fzf-style alignment; relying on the sort implementation for tie ordering; encoding MRU in the score, which would couple ranking tests to MRU scenarios. The original decision described Swift sort as not guaranteeing stability; explicit indices make this contract independent of that assumption.
- **Cost:** With multiple possible alignments, such as `ab` in `a_b_ab`, the selected alignment may not score best. Matching itself remains complete.
- **Revisit:** Real ranking becomes awkward, for example long titles consistently outrank exact matches for short queries. Then consider optimal alignment and position penalties.
