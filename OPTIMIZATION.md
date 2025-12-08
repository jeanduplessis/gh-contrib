# GitHub API Call Optimization Analysis

> **Status**: Phase 1 optimizations ✅ **COMPLETED** (25-75% reduction in API calls)

## What Was Accomplished

Phase 1 optimizations have been successfully implemented, delivering significant API call reductions:

- ✅ **Removed unnecessary PR details API call** - eliminated 1 API call per PR
- ✅ **Implemented response caching** - prevents redundant fetches for multiple users
- ✅ **25% reduction** for single-user scenarios
- ✅ **63-75% reduction** for multi-user scenarios (2-3 users)

**Next Steps:** Phase 2 (GraphQL) and Phase 3 (Batching) remain optional future optimizations.

---

## Current State (After Phase 1 Optimizations)

### API Call Pattern

The script makes API calls per issue/PR discovered, with caching enabled:

**For Issues:**
- 1 call: `repos/{repo}/issues/{number}/comments` (cached)

**For Pull Requests:**
- Call 1: `repos/{repo}/issues/{number}/comments` (cached)
- Call 2: `repos/{repo}/pulls/{number}/reviews` (cached)
- ~~Call 3: `repos/{repo}/pulls/{number}` (PR details)~~ ✅ **REMOVED**

**Example Workload (Single User):**
- 100 items (50 issues, 50 PRs):
  - 50 issues × 1 call = **50 calls**
  - 50 PRs × 2 calls = **100 calls**
  - **Total: ~150 API calls** (down from ~200, **25% reduction**)

**Example Workload (Multiple Users on Shared Items):**
- 100 shared items, 2 users:
  - **~150 API calls total** (down from ~400, **63% reduction**)
  - Cache hits prevent redundant fetches for the same comments/reviews

### ~~Critical Issue: Multi-User Redundancy~~ ✅ **SOLVED**

~~In `process_item_for_users()` (line 244-266), when processing multiple users, the script calls `process_item()` → `fetch_additional_interactions()` for EACH user separately, re-fetching identical API data.~~

**Solution Implemented:** API response caching with `gh_api_cached()` now prevents redundant fetches. When processing the same item for multiple users, API responses are cached and reused.

```python
# Line 249: Called once per user, per item
for username in item.get("_usernames", []):
    processed = process_item(item.copy(), username, since_dt, end_dt)
    # ✅ Now uses cached API responses - no redundant calls!
```

**With 2 users on 50 shared items:**
- ~~Before Phase 1: 50 items × 2 users × 2-3 calls = **200-300 API calls**~~
- **After Phase 1: 50 items × 2-3 calls = **100-150 API calls** ✅**

---

## Optimization Opportunities

### 1. 🎯 ✅ Remove PR Details Call (COMPLETED)

**Status:** ✅ Implemented in commit (removed lines 199-204)

**What Was Done:**
- Removed the PR details API call from `fetch_additional_interactions()`
- Eliminated unnecessary fetching of `requested_reviewers`
- Removed `"review-requested"` passive interaction tracking

**Rationale:**
- `review-requested` was a passive interaction type that didn't contribute to summary statistics
- Items with only passive interactions were filtered out anyway
- The API call provided no value to the final output

**Impact Achieved:**
- PRs: 3 calls → 2 calls per PR (**33% reduction for PRs**)
- Overall: ~200 calls → ~150 calls (**25% reduction**)

---

### 2. ⚡ ✅ Add API Response Caching (COMPLETED)

**Status:** ✅ Implemented in commit (added lines 127-141, updated lines 184 & 201)

**What Was Done:**
- Added module-level `_api_cache` dictionary to store API responses
- Created `gh_api_cached()` function that wraps `gh_api()` with caching logic
- Updated `fetch_additional_interactions()` to use `gh_api_cached()` for:
  - Comments fetching (line 184)
  - Reviews fetching (line 201)

**How It Works:**
- Cache persists for the entire script execution
- First API call for an endpoint stores the result in the cache
- Subsequent calls to the same endpoint return cached data instantly
- Comments/reviews fetched once per item, regardless of user count

**Impact Achieved:**
| Users | Items | Current Calls | With Cache | Reduction |
|-------|-------|---------------|------------|-----------|
| 1 | 100 | ~150 | ~150 | 0% |
| 2 | 100 (shared) | ~300 | ~150 | **50% ↓** |
| 3 | 100 (shared) | ~450 | ~150 | **67% ↓** |

---

### 3. 🚀 Switch to GraphQL API (Major Optimization)

**Impact:** 50% reduction in API calls

**Current:** 2 separate REST calls per PR (after removing PR details):
```python
# Call 1
comments = gh_api(f"repos/{repo}/issues/{number}/comments")

# Call 2
reviews = gh_api(f"repos/{repo}/pulls/{number}/reviews")
```

**Optimized:** 1 GraphQL query per item:
```graphql
query GetItemInteractions($owner: String!, $repo: String!, $number: Int!, $isPR: Boolean!) {
  repository(owner: $owner, name: $repo) {
    issue(number: $number) @skip(if: $isPR) {
      comments(first: 100) {
        nodes {
          author { login }
          createdAt
          body
        }
      }
    }
    pullRequest(number: $number) @include(if: $isPR) {
      comments(first: 100) {
        nodes {
          author { login }
          createdAt
          body
        }
      }
      reviews(first: 100) {
        nodes {
          author { login }
          submittedAt
          state
        }
      }
    }
  }
}
```

**Implementation:**
- Create `gh_api_graphql()` function
- Replace REST calls in `fetch_additional_interactions()`
- Parse GraphQL response structure

**Benefits:**
- 2 calls → 1 call per item
- More efficient for GitHub's infrastructure
- Can add more fields without additional calls

**Complexity:** Medium (requires GraphQL query construction and response parsing)

---

### 4. ⚡⚡ Batch GraphQL Queries (Maximum Optimization)

**Impact:** 80-90% additional reduction on top of GraphQL

**Concept:** Use GraphQL query aliases to batch multiple items per request:

```graphql
query GetBatchInteractions {
  item1: repository(owner: "org", name: "repo1") {
    pullRequest(number: 123) { ...InteractionFields }
  }
  item2: repository(owner: "org", name: "repo2") {
    issue(number: 456) { ...InteractionFields }
  }
  # ... batch 10-20 items per query
}
```

**Implementation Strategy:**
- Batch items into groups of 10-20 (respect GitHub query complexity limits)
- Generate dynamic GraphQL with aliases
- Parse batched responses back to individual items
- Modify parallel processing to use batch queries

**Example Savings:**
| Items | GraphQL (unbatched) | Batched (10/query) | Reduction |
|-------|---------------------|-------------------|-----------|
| 100 | 100 calls | 10 calls | 90% |
| 200 | 200 calls | 20 calls | 90% |

**Complexity:** High (requires careful batch construction, error handling per alias)

---

### 5. 📊 Smarter Pagination (Minor Optimization)

**Current:** Always requests `per_page=100` (line 28: `API_PAGE_SIZE = 100`)

**Optimization:**
- Default to `per_page=30` for initial request
- Check response headers for `Link: rel="next"`
- Only paginate if more results exist

**Trade-offs:**
- Adds complexity for edge cases
- Marginal benefit (most items have <30 comments/reviews)
- Could cause 2 requests for high-activity items

**Recommendation:** Skip this optimization - complexity not worth the minimal gains

---

## Recommended Implementation Strategy

### Phase 1: Quick Wins ✅ **COMPLETED**

**Status:** ✅ Both optimizations implemented and deployed

1. **✅ Remove PR Details API Call**
   - ✅ Deleted lines 199-204 in `fetch_additional_interactions()`
   - ✅ Removed `"review-requested"` from interactions
   - **Savings:** 25% reduction overall

2. **✅ Add API Caching**
   - ✅ Implemented `gh_api_cached()` function (lines 127-141)
   - ✅ Replaced calls in `fetch_additional_interactions()` (lines 184, 201)
   - **Savings:** 50-67% for multi-user scenarios

**Phase 1 Impact Achieved:**
- Single user: ~200 → ~150 calls (25% reduction) ✅
- Two users: ~400 → ~150 calls (63% reduction) ✅
- Three users: ~600 → ~150 calls (75% reduction) ✅

---

### Phase 2: Major Optimization 🚀 (Optional)

**Switch to GraphQL API**
- **Effort:** 2-3 hours
- **Savings:** Additional 50% on top of Phase 1
- **When to implement:** If regularly processing 200+ items or hitting rate limits

---

### Phase 3: Advanced 🔥 (Optional)

**Batch GraphQL Queries**
- **Effort:** 4-6 hours
- **Savings:** Additional 80-90% on top of Phase 2
- **When to implement:** If processing 500+ items or need maximum performance

---

## Summary: API Call Reduction Table

| Scenario | Baseline | Phase 1 | Phase 2 | Phase 3 |
|----------|----------|---------|---------|---------|
| **100 items, 1 user** | ~200 | ~150 (25% ↓) | ~100 (50% ↓) | ~10-20 (90-95% ↓) |
| **100 items, 2 users (shared)** | ~400 | ~150 (63% ↓) | ~100 (75% ↓) | ~10-20 (95-98% ↓) |
| **100 items, 3 users (shared)** | ~600 | ~150 (75% ↓) | ~100 (83% ↓) | ~10-20 (97-98% ↓) |

---

## Implementation Priority

1. ✅ **COMPLETED:** Remove PR details call + Add caching (Phase 1)
2. ⏳ **Consider Next:** GraphQL if processing >200 items regularly (Phase 2)
3. 🤔 **Maybe Later:** Batching if processing >500 items or need max performance (Phase 3)

---

## GitHub API Rate Limits

**Reference:** https://docs.github.com/en/rest/overview/rate-limits

- **Authenticated:** 5,000 requests/hour
- **GraphQL:** 5,000 points/hour (queries cost 1+ points based on complexity)

**Current Usage Example:**
- 100 items @ ~200 calls = 4% of hourly limit
- With Phase 1: ~150 calls = 3% of hourly limit
- With Phase 2: ~100 calls = 2% of hourly limit

**Conclusion:** Rate limits aren't a concern for typical usage (<1000 items), but optimizations still improve performance and reduce latency.
