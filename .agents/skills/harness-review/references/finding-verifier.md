<!-- flutter-agentic-harness-managed -->

# Finding verifier

Attempt to falsify every candidate finding independently from the original reviewer.

For each candidate:

1. Confirm that the cited symbol and changed behavior exist.
2. Confirm that the named contract applies to this layer and workflow.
3. Establish a reachable call path or state interleaving for the claimed impact.
4. Determine whether the issue is introduced, worsened, or merely pre-existing.
5. Check whether another layer, guard, adapter, or test already prevents the consequence.
6. Recalculate severity and confidence from the common contract.
7. Merge duplicates that describe the same invariant and consequence.

Return `accepted`, `rejected`, and `merged` lists. Give a concise evidence-based reason for every rejection or downgrade. Do not add unrelated speculative findings during verification.
