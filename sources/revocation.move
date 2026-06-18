module sentinel::revocation;

/// Canonical policy status codes, shared with `agent_policy` and the indexer.
public fun active(): u8 { 0 }
public fun paused(): u8 { 1 }
public fun revoked(): u8 { 2 }
public fun expired(): u8 { 3 }
