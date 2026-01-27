@{
    # Exclude tests from strict analyzer rules while we iteratively fix production code.
    ExcludePaths = @(
        'tests\\**',
        '.github\\**',
        'tools\\**'
    )
    # Keep rules enabled by default; you can disable specific rules here if desired.
    Rules = @{
        # Suppress PSReviewUnusedParameter for now (false positives in dynamic code paths)
        'PSReviewUnusedParameter' = @{ Enable = $false }
        # You can add more rule toggles here if needed
    }
}
