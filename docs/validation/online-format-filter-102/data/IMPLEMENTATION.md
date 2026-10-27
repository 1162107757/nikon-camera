# Online preset format filtering: data/API slice (102)

Status: local source and isolated tests pass. This record does not certify a cloud deployment or APK publication.

The client supports `fetchPage(int page, int pageSize, String category, String fileFormat)`.
The existing three-argument method delegates to the all-format request. Empty or null format selects all; otherwise the exact supported values are `NCP` and `NP3`. Nonempty formats are appended as `&fileFormat=NCP` or `&fileFormat=NP3`; category encoding and the uncategorized sentinel remain unchanged.

`PageResult` adds `public final String fileFormat`. The other public fields retain their meaning: `presets`, server-filtered `total`, `page`, `pageSize`, `hasMore`, and global `categories`. A selected-format request requires the database's matching `fileFormat` acknowledgement and every returned row must match that format. An old server silently ignoring the parameter, a different acknowledgement, and mixed rows all reject the whole page instead of dropping rows or inventing totals. All-format requests remain compatible with old servers lacking the acknowledgement. Explicit malformed acknowledgement values are rejected.

Only `online-library/server/community.mjs` changes in the server bundle. The public feed validates `fileFormat`, rejects duplicate parameters, and passes it through the existing `nikon_community` JSON body. HTTP deliberately does not manufacture a response acknowledgement: the database must first apply the filter.

`015-preset-format-filter.sql` patches only the feed branch in `public.nikon_community(text,uuid,uuid,jsonb)`. Category and file format predicates apply to both the count and the page query; sorting remains `published_at DESC,id`. Missing legacy file metadata counts as NCP. Categories remain global, and omitted formats preserve the all-format behavior. The migration verifies a unique known fragment, runs in a transaction, is idempotent, and preserves dispatcher setup, every other branch, function ownership/ACLs, other functions, and release records/policy.

No manifest/recipe/download cache semantics change. Fetching a page still does not write the legacy manifest cache or add downloaded presets. This slice does not change the pre-existing client page bounds (up to 100 records) versus server bounds (up to 50); the product UI uses 20.

Validation captured in adjacent files:

- `tests/run-community.ps1`: 33 repository + 46 paging + 94 reply-paging + 9 recipient checks passed.
- `node --test online-library/test/community.test.mjs`: 15 HTTP/service tests passed.
- `node online-library/test/preset-format-filter-postgres.mjs`: 641 PostgreSQL checks passed after all migrations 001..014. Includes rerun and fail-closed migration, feed-only definition change, all function ownership/ACL preservation, 65 mixed curated/community fixtures, exact multiple-page totals, category/format combinations, empty results, legacy NCP, strict invalid values, fixture rollback, and untouched release records.
- `node --test online-library/test/preset-formats.test.mjs`: 5 format/upload/download/catalog tests passed.
- `node online-library/scripts/check.mjs`: 64 JavaScript modules passed syntax/source checks.

MainActivity filtering controls, request epochs, cached-result presentation and app version are owned by the parent task. No app build, ADB action, cloud SQL execution or release operation was performed by this data/API slice.
